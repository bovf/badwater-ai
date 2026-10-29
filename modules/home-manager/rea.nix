{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai;
  supported = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  package = cfg.rea.package;
  validPackage = package != null && (package.mcpArgs or null) == ["mcp"] && (package.skillRelativePath or null) == "share/rea/skills/reverse-engineer-anything";
in {
  options.badwater.ai = {
    rea = {
      enable = lib.mkEnableOption "REA's Nix-owned reverse-engineering CLI (not permission to inspect live targets)";
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        # Do not force an unsupported producer package for disabled/non-native homes.
        default =
          if cfg.rea.enable && supported
          then pkgs.rea or null
          else null;
        description = "pi-nix REA package with the reviewed mcpArgs and skillRelativePath metadata; currently x86_64-linux only. No runtime installers or setup.";
      };
    };
    pi.rea = {
      enable = lib.mkEnableOption "register REA's packaged skill in Pi (requires rea.enable and pi.enable)";
      mcp = {
        enable = lib.mkEnableOption "register REA stdio with Pi's existing builtin MCP owner";
        exposure = lib.mkOption {
          type = lib.types.enum ["codemode" "deferred" "direct" "hidden"];
          default = "codemode";
          description = "Builtin Pi exposure for REA's large catalog; discovery does not guarantee backend availability or authorize tool calls.";
        };
      };
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.rea.enable || supported;
          message = "badwater.ai.rea.enable requires x86_64-linux; the reviewed Ghidra/native REA bundle is not supported on this platform.";
        }
        {
          assertion = !cfg.rea.enable || !supported || validPackage;
          message = "badwater.ai.rea.enable requires pi-nix's REA package with reviewed mcpArgs and skillRelativePath metadata.";
        }
        {
          assertion = !(cfg.pi.rea.enable || cfg.pi.rea.mcp.enable) || (cfg.pi.enable && cfg.rea.enable);
          message = "Pi REA skill/MCP integration requires badwater.ai.pi.enable and badwater.ai.rea.enable; CLI installation alone does not require Pi.";
        }
      ];
    }
    (lib.mkIf (cfg.rea.enable && supported && validPackage) {
      home.packages = [package];
      home.file = lib.mkIf (cfg.pi.enable && cfg.pi.rea.enable) {
        ".pi/agent/skills/reverse-engineer-anything".source = "${package}/${package.skillRelativePath}";
      };
      # Registration and disablement belong exclusively to badwaterPiMcp after writeBoundary.
      badwater.ai.pi.mcpServers = lib.mkIf (cfg.pi.enable && cfg.pi.rea.mcp.enable) {
        rea = {
          command = "${package}/bin/rea";
          args = package.mcpArgs;
          exposure = cfg.pi.rea.mcp.exposure;
        };
      };
    })
  ];
}
