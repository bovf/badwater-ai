{
  inputs,
  system ? "x86_64-linux",
  case ? null,
}: let
  lib = inputs.nixpkgs.lib;
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [inputs.pi-nix.overlays.default inputs.graphify-nix.overlays.default];
  };
  packages = builtins.removeAttrs inputs.artcraft-nix.packages.${system} ["default"];
  make = extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        inputs.sops-nix.homeManagerModules.sops
        ../modules/home-manager/ai.nix
        {
          home.username = "fixture";
          home.homeDirectory = "/fixture/home";
          home.stateVersion = "25.11";
          badwater.ai.artcraft.packages = packages;
        }
        extra
      ];
    };
  workflow = {
    badwater.ai.pi = {
      enable = true;
      videoEditing.enable = true;
    };
  };
  gridMcp = {
    badwater.ai = {
      pi.enable = true;
      artcraft = {
        enable = true;
        applications.gridcraft.enable = true;
        mcp.enable = true;
      };
    };
  };
  cases = {
    disabled = {};
    elsewhere = {home.packages = [packages.filmcraft];};
    individual = {
      badwater.ai.artcraft = {
        enable = true;
        applications.filmcraft.enable = true;
      };
    };
    all = {
      badwater.ai.artcraft = {
        enable = true;
        applications.all = true;
      };
    };
    allExceptArt = {
      badwater.ai.artcraft = {
        enable = true;
        applications.all = true;
        applications.artcraft.enable = false;
      };
    };
    video = workflow;
    videoEditorial = {
      imports = [workflow];
      badwater.ai.pi.videoEditing = {
        editorial.enable = true;
        asrModel = "small.en";
      };
    };
    videoExcludedEffect = {
      imports = [workflow];
      badwater.ai.pi.videoEditing.editorial.enable = true;
      badwater.ai.artcraft.applications.effectcraft.enable = false;
    };
    workflowMcpOff = {
      imports = [workflow];
      badwater.ai.pi.videoEditing.mcp.enable = false;
    };
    videoCustomDirectories = {
      imports = [workflow];
      badwater.ai.pi.videoEditing = {
        readRoots = ["/fixture/home/Raw media; $(touch INJECTED)"];
        writeRoot = "/fixture/home/Custom projects' directory";
      };
    };
    onlyCraftMcp = gridMcp;
    onlyNew = {
      badwater.ai.pi = {
        enable = true;
        mcpServers.fixture = {
          command = "/nix/store/fixture/bin/server";
          args = [];
          exposure = "codemode";
        };
      };
    };
    piOff = {badwater.ai.pi.enable = false;};
    preserveBuiltins = {
      imports = [workflow];
      badwater.ai = {
        graphify = {
          enable = true;
          package = pkgs.graphify;
        };
        pi = {
          graphify.mcp.enable = true;
          webSearch.enable = true;
          defaultProvider = "openai";
          defaultModel = "gpt-5.6-sol";
          theme = "dark";
          extraSettings = {
            compaction = {
              enabled = true;
              reserveTokens = 32000;
              keepRecentTokens = 60000;
            };
          };
        };
      };
    };
    identicalPackages = {
      badwater.ai.pi = {
        enable = true;
        packages = [
          {
            name = "identical";
            package = pkgs.hello;
          }
          {
            name = "identical";
            package = pkgs.hello;
          }
        ];
      };
    };
    conflictingBuiltin = {
      imports = [cases.preserveBuiltins];
      badwater.ai.pi.mcpServers.graphify.command = "/fixture/conflict";
    };
    conflictingPackages = {
      badwater.ai.pi = {
        enable = true;
        packages = [
          {
            name = "conflict";
            package = pkgs.hello;
          }
          {
            name = "conflict";
            package = pkgs.coreutils;
          }
        ];
      };
    };
    normalizedNames = {
      badwater.ai.pi = {
        enable = true;
        mcpServers = {
          a-b = {command = "/fixture/one";};
          a_b = {command = "/fixture/two";};
        };
      };
    };
    explicitTools = {
      imports = [workflow];
      badwater.ai.pi.extraSettings.defaultTools = ["read"];
    };
    implicitExposureTools = {
      badwater.ai.pi = {
        enable = true;
        mcpServers.fixture = {command = "/fixture/server";};
        extraSettings.defaultTools = ["read"];
      };
    };
    deferredExplicitTools = {
      imports = [workflow];
      badwater.ai.pi = {
        videoEditing.mcp.exposure = "deferred";
        extraSettings.defaultTools = ["read" "+tool_search"];
      };
    };
    directExplicitTools = {
      imports = [workflow];
      badwater.ai.pi = {
        videoEditing.mcp.exposure = "direct";
        extraSettings.defaultTools = ["read"];
      };
    };
    hiddenExplicitTools = {
      imports = [workflow];
      badwater.ai.pi = {
        videoEditing.mcp.exposure = "hidden";
        extraSettings.defaultTools = ["read"];
      };
    };
    both = {
      badwater.ai = {
        pi = {
          enable = true;
          videoEditing.enable = true;
        };
        artcraft = {
          enable = true;
          applications.all = true;
          mcp.enable = true;
        };
      };
    };
    unsupportedArtMcp = {
      badwater.ai = {
        pi.enable = true;
        artcraft = {
          enable = true;
          applications.artcraft.enable = true;
          mcp = {
            enable = true;
            applications = ["artcraft"];
          };
        };
      };
    };
    videoExcludedSound = {
      imports = [workflow];
      badwater.ai.artcraft.applications.soundcraft.enable = false;
    };
    videoPiOff = {badwater.ai.pi.videoEditing.enable = true;};
    missingRuntime = {
      imports = [workflow];
      badwater.ai.pi.videoEditing.package = null;
    };
  };
  summarize = h: let
    c = h.config;
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  in
    if failed != []
    then {inherit failed;}
    else {
      inherit failed;
      applications = builtins.filter (n: n != "all" && c.badwater.ai.artcraft.applications.${n}.enable) (builtins.attrNames c.badwater.ai.artcraft.applications);
      packages = map toString c.home.packages;
      piPackages =
        map (p: {
          inherit (p) name;
          package = toString p.package;
        })
        c.badwater.ai.pi.packages;
      servers = c.badwater.ai.pi.mcpServers;
      mcp = c.home.activation.badwaterPiMcp.data;
      mcpContext = builtins.getContext c.home.activation.badwaterPiMcp.data;
      videoDirectories = {
        inherit (c.badwater.ai.pi.videoEditing) readRoots writeRoot;
        script =
          if c.home.activation ? badwaterVideoDirectories
          then c.home.activation.badwaterVideoDirectories.data
          else null;
        context =
          if c.home.activation ? badwaterVideoDirectories
          then builtins.getContext c.home.activation.badwaterVideoDirectories.data
          else {};
        activationLibrary = "${inputs.home-manager}/lib/bash/home-manager.sh";
      };
      settings =
        if c.badwater.ai.pi.enable
        then c.home.activation.badwaterPiSettings.data
        else null;
      keybindings =
        if c.badwater.ai.pi.enable
        then c.home.activation.badwaterPiKeybindings.data
        else null;
    };
  run = extra: let
    result = builtins.tryEval (builtins.deepSeq (summarize (make extra)) (summarize (make extra)));
  in
    if result.success
    then result.value
    else {evaluationFailed = true;};
  individualCases = lib.genAttrs (builtins.attrNames packages) (name: {
    badwater.ai.artcraft = {
      enable = true;
      applications.${name}.enable = true;
    };
  });
in
  if case != null
  then summarize (make cases.${case})
  else {
    cases = builtins.mapAttrs (_: run) cases;
    individuals = builtins.mapAttrs (_: run) individualCases;
  }
