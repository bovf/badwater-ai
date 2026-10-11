{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai.artcraft;
  names = ["photocraft" "artcraft" "lightcraft" "filmcraft" "pdfcraft" "vectorcraft" "effectcraft" "designcraft" "wordcraft" "cadcraft" "gridcraft" "deckcraft" "soundcraft"];
  selected = builtins.filter (name: cfg.applications.${name}.enable) names;
  verified = builtins.filter (name: name != "artcraft") names;
  exposureType = lib.types.enum ["codemode" "deferred" "direct" "hidden"];
  server = name: let
    application = cfg.applications.${name};
    settings = pkgs.writeText "craft-${name}-mcp.json" (builtins.toJSON {
      application = name;
      command = "${application.package}/bin/${name}-cli";
      inherit (cfg.mcp) readRoots writeRoot;
    });
  in {
    command = "${cfg.mcp.package}/bin/badwater-craft-mcp";
    args = ["${settings}"];
    exposure = cfg.mcp.exposure;
  };
in {
  options.badwater.ai.artcraft = {
    enable = lib.mkEnableOption "independently selected Craft applications from the existing artcraft-nix producer";
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = {};
      description = "Inject exact artcraft-nix.packages for this system (remove its default alias). No producer nixpkgs/font/compiler follows or repackaging. Individual package overrides are optional.";
    };
    applications =
      {
        all = lib.mkEnableOption "all thirteen applications, including explicit non-free ArtCraft selection; individual false overrides this default";
      }
      // lib.genAttrs names (name: {
        enable = lib.mkEnableOption name;
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = cfg.packages.${name} or null;
          description = "Exact producer ${name} output. Non-free licenses/notices and redistribution restrictions remain upstream-owned.";
        };
      });
    mcp = {
      enable = lib.mkEnableOption "verified native stdio MCP servers through Pi's builtin MCP (no GUI bridges or network endpoints)";
      applications = lib.mkOption {
        type = lib.types.listOf (lib.types.enum names);
        default = builtins.filter (name: builtins.elem name verified) selected;
        description = "Selected verified application servers; ArtCraft is install-only and cannot be explicitly requested here. Native tools can return document/image content to Pi's model: obtain permission for real media before tool calls.";
      };
      exposure = lib.mkOption {
        type = exposureType;
        default = "codemode";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.badwater-craft-mcp or null;
        description = "pi-nix's lightweight private namespace launcher, not a repackaged application suite.";
      };
      readRoots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Explicit raw/document read roots; no implicit private-home access. Must be absolute, symlink-free and disjoint from writeRoot.";
      };
      writeRoot = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.dataHome}/badwater/craft";
        description = "Persistent derived projects/private MCP settings; never removed on disablement.";
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      badwater.ai.artcraft.applications = lib.mkIf cfg.applications.all (lib.genAttrs names (_: {enable = lib.mkDefault true;}));
      home.packages = lib.unique (builtins.filter (p: p != null) (map (name: cfg.applications.${name}.package) selected));
      assertions =
        map (name: {
          assertion = cfg.applications.${name}.package != null;
          message = "badwater.ai.artcraft.applications.${name}.enable requires an exact producer package: inject badwater.ai.artcraft.packages or set this application's package.";
        })
        selected;
    })
    (lib.mkIf cfg.mcp.enable {
      assertions = [
        {
          assertion = cfg.enable && config.badwater.ai.pi.enable;
          message = "Craft MCP requires badwater.ai.artcraft.enable and badwater.ai.pi.enable; application installation alone does not require Pi.";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux && cfg.mcp.package != null;
          message = "Craft MCP's verified private namespace launcher requires Linux and the pi-nix overlay.";
        }
        {
          assertion = lib.all (name: builtins.elem name verified && builtins.elem name selected) cfg.mcp.applications;
          message = "Craft MCP applications must be selected, verified native interfaces; ArtCraft has no verified companion CLI/MCP.";
        }
        {
          assertion = builtins.length (lib.unique cfg.mcp.applications) == builtins.length cfg.mcp.applications;
          message = "Craft MCP application names must be unique.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && cfg.mcp.enable && config.badwater.ai.pi.enable && pkgs.stdenv.hostPlatform.isLinux && cfg.mcp.package != null && lib.all (name: cfg.applications.${name}.package != null) cfg.mcp.applications) {
      badwater.ai.pi.mcpServers = builtins.listToAttrs (map (name: {
          name = "craft-${name}";
          value = server name;
        })
        cfg.mcp.applications);
    })
  ];
}
