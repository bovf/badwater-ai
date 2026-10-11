{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai.pi.videoEditing;
  craft = config.badwater.ai.artcraft;
  ready = cfg.package != null && craft.applications.filmcraft.package != null && craft.applications.soundcraft.package != null && (pkgs.badwater-craft-mcp or null) != null;
  settings = pkgs.writeText "badwater-video-config.json" (builtins.toJSON {
    inherit (cfg) readRoots writeRoot concurrency timeoutSeconds maxAutomaticRepairAttempts asrModel;
    model = cfg.package.models.${cfg.asrModel}.model;
    modelHash = cfg.package.models.${cfg.asrModel}.hash;
    maxEffectAssetBytes = cfg.effectAssetLimitMiB * 1024 * 1024;
    filmcraft = "${craft.applications.filmcraft.package}/bin/filmcraft-cli";
    soundcraft = "${craft.applications.soundcraft.package}/bin/soundcraft-cli";
    craftLauncher = "${pkgs.badwater-craft-mcp}/bin/badwater-craft-mcp";
    craftApplications = lib.mapAttrs (name: application: "${application.package}/bin/${name}-cli") (lib.filterAttrs (name: application: name != "artcraft" && application.enable && application.package != null) (builtins.removeAttrs craft.applications ["all"]));
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
    editorial.enable = lib.mkEnableOption "native EffectCraft word animation/effect recipes and cross-app composition (requires selected EffectCraft)";
    asrModel = lib.mkOption {
      type = lib.types.enum ["tiny.en" "small.en"];
      default = "tiny.en";
      description = "Immutable local CPU English Whisper weights from pi-nix. small.en is a quality/cost option; no runtime downloads or provider calls.";
    };
    effectAssetLimitMiB = lib.mkOption {
      type = lib.types.ints.between 16 4096;
      default = 1024;
      description = "Maximum size of one native generated/transparent effect media asset; originals and prior outputs are never pruned.";
    };
    readRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["${config.home.homeDirectory}/Videos/Raw"];
      description = "Explicit raw-media read roots; operations require authorized files and never auto-scan them. No symlinks/traversal/root directory or overlap with writeRoot.";
    };
    writeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Videos/BadwaterAI/Projects";
      description = "Persistent project directories containing index/jobs/frames/native revisions/exports. Created on activation; existing projects at a previous writeRoot are not moved or deleted.";
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
        applications.effectcraft.enable = lib.mkIf cfg.editorial.enable (lib.mkDefault true);
      };
      assertions = [
        {
          assertion = !cfg.editorial.enable || (craft.applications.effectcraft.enable && craft.applications.effectcraft.package != null);
          message = "Editorial captions/effect recipes require selected EffectCraft; explicit false is respected.";
        }
        {
          assertion = cfg.package != null && cfg.package ? models && builtins.hasAttr cfg.asrModel cfg.package.models;
          message = "Selected local ASR model requires a pi-nix editorial runtime with that immutable model output.";
        }
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
      home.activation.badwaterVideoDirectories = config.lib.dag.entryAfter ["writeBoundary"] ''
        run ${pkgs.coreutils}/bin/mkdir -m 700 -p -- ${lib.escapeShellArgs (cfg.readRoots ++ [cfg.writeRoot])}
      '';
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
