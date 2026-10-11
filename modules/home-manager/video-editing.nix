{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai.pi.videoEditing;
  craft = config.badwater.ai.artcraft;
  ready = cfg.package != null && craft.applications.filmcraft.package != null && craft.applications.soundcraft.package != null;
  settings = pkgs.writeText "badwater-video-config.json" (builtins.toJSON {
    inherit (cfg) readRoots writeRoot concurrency timeoutSeconds maxAutomaticRepairAttempts;
    filmcraft = "${craft.applications.filmcraft.package}/bin/filmcraft-cli";
    soundcraft = "${craft.applications.soundcraft.package}/bin/soundcraft-cli";
  });
  configured = pkgs.symlinkJoin {
    name = "badwater-video-configured-${cfg.package.version}";
    paths = [cfg.package];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram "$out/bin/badwater-video" --set BADWATER_VIDEO_CONFIG ${settings}
    '';
    meta.mainProgram = "badwater-video";
  };
in {
  options.badwater.ai.pi.videoEditing = {
    enable = lib.mkEnableOption "local-first indexed native FilmCraft/SoundCraft editing through the shared JSON CLI/MCP engine and packaged Pi skill";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.badwater-video or null;
      description = "Linux-only pi-nix workflow runtime with pinned CPU tiny.en Whisper/model, not application repackaging.";
    };
    readRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["${config.home.homeDirectory}/Videos/Raw"];
      description = "Explicit raw-media read roots; operations require authorized files and never auto-scan them. No symlinks/traversal/root directory or overlap with writeRoot.";
    };
    writeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/badwater/video";
      description = "Persistent derived index/jobs/frames/native revisions/exports. Disabled workflow never deletes user data or cache.";
    };
    concurrency = lib.mkOption {
      type = lib.types.ints.between 1 4;
      default = 1;
      description = "Global bounded workers; at most one writer per project.";
    };
    timeoutSeconds = lib.mkOption {
      type = lib.types.ints.between 30 7200;
      default = 1200;
    };
    maxAutomaticRepairAttempts = lib.mkOption {
      type = lib.types.ints.between 0 3;
      default = 2;
    };
    mcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add the shared engine to Pi's existing MCP owner; no direct native server duplication or GUI launch.";
    };
    mcp.exposure = lib.mkOption {
      type = lib.types.enum ["codemode" "deferred" "direct" "hidden"];
      default = "codemode";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      badwater.ai.artcraft = {
        enable = lib.mkDefault true;
        applications.filmcraft.enable = lib.mkDefault true;
        applications.soundcraft.enable = lib.mkDefault true;
      };
      assertions = [
        {
          assertion = config.badwater.ai.pi.enable;
          message = "badwater.ai.pi.videoEditing.enable requires badwater.ai.pi.enable = true.";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux && ready;
          message = "Video editing requires Linux, pi-nix's badwater-video output and exact FilmCraft/SoundCraft producer packages.";
        }
        {
          assertion = craft.enable && craft.applications.filmcraft.enable && craft.applications.soundcraft.enable;
          message = "Video editing's implemented native audio path requires Craft master/FilmCraft/SoundCraft; explicit false is respected, so disable the workflow or select those dependencies.";
        }
        {
          assertion = cfg.readRoots != [] && lib.all (p: lib.hasPrefix "/" p && p != "/") cfg.readRoots && lib.hasPrefix "/" cfg.writeRoot && cfg.writeRoot != "/";
          message = "Video editing requires explicit absolute raw read roots and a separate non-root derived writeRoot.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && ready && config.badwater.ai.pi.enable) {
      home.packages = [configured];
      badwater.ai.pi.packages = lib.mkAfter [
        {
          name = "badwater-video";
          package = cfg.package;
        }
      ];
      badwater.ai.pi.mcpServers = lib.mkIf cfg.mcp.enable {
        badwater-video = {
          command = "${configured}/bin/badwater-video";
          args = ["mcp"];
          exposure = cfg.mcp.exposure;
        };
      };
    })
  ];
}
