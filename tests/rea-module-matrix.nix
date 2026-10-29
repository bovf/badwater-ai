# Evaluate with a temporary input set containing home-manager, nixpkgs, pi-nix and graphify-nix.
# Summarize assertions/resources only: never build a home or activation generation.
{
  inputs,
  system ? "x86_64-linux",
}: let
  lib = inputs.nixpkgs.lib;
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [inputs.pi-nix.overlays.default inputs.graphify-nix.overlays.default];
  };
  enabled = {
    badwater.ai = {
      rea.enable = true;
      pi = {
        enable = true;
        rea = {
          enable = true;
          mcp.enable = true;
        };
      };
    };
  };
  resources = {
    badwater.ai = {
      graphify.enable = true;
      claudeCode.graphify.enable = true;
      opencode.graphify.enable = true;
      pi = {
        enable = true;
        graphify = {
          enable = true;
          mcp.enable = true;
        };
        webSearch.enable = true;
        settings.commitRules = true;
        openai.maxContext = true;
        defaultProvider = "openai";
        defaultModel = "gpt-6.1-sol";
        theme = "dark";
        extraSettings = {
          compaction = {
            enabled = true;
            reserveTokens = 32000;
            keepRecentTokens = 60000;
            modelOverrides."openai/gpt-6.1-sol".reserveTokens = 123456;
          };
          "archimedes.mcp".keep = "synthetic";
        };
        packages = map (name: {
          inherit name;
          package = inputs.pi-nix.packages.${system}.${name};
        }) ["pi-archimedes" "pi-subagents" "remote-pi" "plannotator-pi-extension" "ponytail" "pi-wait-what" "pi-lsp" "pi-chrome-devtools" "pi-btw" "pi-goal" "rpiv-todo" "hunk-review"];
      };
    };
  };
  cases = {
    defaultOff = {};
    disabledPoisonPackage = {nixpkgs.overlays = [(_: _: {rea = throw "disabled REA forced an unsupported package";})];};
    cliOnly = {badwater.ai.rea.enable = true;};
    opted = enabled;
    preserveBaseline = resources;
    preserveOpted = {imports = [enabled resources];};
    piOff = {
      badwater.ai.rea.enable = true;
      badwater.ai.pi.enable = false;
    };
    integrationPiOff = {
      imports = [enabled];
      badwater.ai.pi.enable = lib.mkForce false;
    };
    integrationReaOff = {
      imports = [enabled];
      badwater.ai.rea.enable = lib.mkForce false;
    };
    missingPackage = {
      imports = [enabled];
      badwater.ai.rea.package = null;
    };
    invalidMetadata = {
      imports = [enabled];
      badwater.ai.rea.package = pkgs.hello;
    };
    invalidArgs = {
      badwater.ai.pi.mcpServers.invalid = {
        command = "/nix/store/synthetic/bin/server";
        args = [1];
      };
    };
    relativeCommand = {badwater.ai.pi.mcpServers.invalid.command = "server";};
    invalidExposure = {
      badwater.ai.pi.mcpServers.invalid = {
        command = "/nix/store/synthetic/bin/server";
        exposure = "unknown";
      };
    };
    normalizedNames = {
      badwater.ai.pi.mcpServers = {
        rea-one.command = "/synthetic/one";
        rea_one.command = "/synthetic/two";
      };
    };
    missingCodemode = {
      imports = [enabled];
      badwater.ai.pi.extraSettings.defaultTools = ["read"];
    };
    deferred = {
      imports = [enabled];
      badwater.ai.pi = {
        rea.mcp.exposure = "deferred";
        extraSettings.defaultTools = ["read" "+tool_search"];
      };
    };
  };
  # Inspect raw assertion values for negative cases, before HM's checked result throws.
  hmLib = import (inputs.home-manager + "/modules/lib/stdlib-extended.nix") lib;
  summarize = extra: let
    h = hmLib.evalModules {
      class = "homeManager";
      specialArgs.modulesPath = toString (inputs.home-manager + "/modules");
      modules =
        (import (inputs.home-manager + "/modules/modules.nix") {
          inherit pkgs;
          lib = hmLib;
        })
        ++ [
          ../modules/home-manager/ai.nix
          # Only declare the disabled credential seam; no secret module or live paths.
          {
            options.sops.secrets = lib.mkOption {
              type = lib.types.attrs;
              default = {};
            };
          }
          {
            nixpkgs.overlays = pkgs.overlays;
            nixpkgs.config = pkgs.config;
            home.username = "fixture";
            home.homeDirectory = "/tmp/policy-home";
            home.stateVersion = "25.11";
          }
          extra
        ];
    };
    c = h.config;
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  in
    if failed != []
    then {inherit failed;}
    else {
      inherit failed;
      reaEnabled = c.badwater.ai.rea.enable;
      piEnabled = c.badwater.ai.pi.enable;
      packages = map toString c.home.packages;
      files = lib.mapAttrs (_: f: toString f.source) (lib.filterAttrs (name: _: lib.hasInfix "skills/" name || lib.hasPrefix ".pi/agent/nix-packages/" name || lib.hasPrefix ".pi/agent/extensions/" name) c.home.file);
      mcpServers = c.badwater.ai.pi.mcpServers;
      mcp = c.home.activation.badwaterPiMcp.data;
      mcpAfter = c.home.activation.badwaterPiMcp.after;
      settings =
        if c.badwater.ai.pi.enable
        then c.home.activation.badwaterPiSettings.data
        else null;
      keybindings =
        if c.badwater.ai.pi.enable
        then c.home.activation.badwaterPiKeybindings.data
        else null;
      context = c.home.activation.badwaterPiOpenaiContext.data;
      activationNames = builtins.attrNames c.home.activation;
      activationLibrary = "${inputs.home-manager}/lib/bash/home-manager.sh";
    };
in
  lib.mapAttrs (_: summarize) cases
