# Caller supplies the consumer's pinned nixpkgs/Home Manager. No live GitLab.
{
  inputs,
  system ? "x86_64-linux",
}: let
  lib = import (inputs.nixpkgs + "/lib");
  fixtures = final: _: let
    package = name: final.runCommand name {} ''mkdir -p "$out"'';
  in {
    pi-coding-agent = package "pi-gitlab-fixture";
    badwater-gitlab = package "badwater-gitlab-fixture";
  };
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [fixtures];
  };
  hmLib = import (inputs.home-manager + "/modules/lib/stdlib-extended.nix") lib;
  evaluate = extra:
    hmLib.evalModules {
      class = "homeManager";
      specialArgs.modulesPath = toString (inputs.home-manager + "/modules");
      modules =
        (import (inputs.home-manager + "/modules/modules.nix") {
          inherit pkgs;
          lib = hmLib;
        })
        ++ [
          ../modules/home-manager/ai.nix
          {
            options.sops.secrets = lib.mkOption {
              type = lib.types.attrs;
              default = {};
            };
          }
          {
            nixpkgs.overlays = [fixtures];
            home.username = "fixture";
            home.homeDirectory = "/tmp/gitlab-policy-home";
            home.stateVersion = "25.11";
          }
          extra
        ];
    };
  enabled = {
    badwater.ai.pi = {
      enable = true;
      gitlab = {
        enable = true;
        host = "gitlab.example.test";
      };
    };
  };
  cases = {
    defaultOff = {};
    baseline = {badwater.ai.pi.enable = true;};
    disabledPoison = {nixpkgs.overlays = lib.mkAfter [(_: _: {badwater-gitlab = throw "disabled GitLab package forced";})];};
    enabled = enabled;
    explicitConnect = {
      imports = [enabled];
      badwater.ai.pi.gitlab.mcp.connect = true;
    };
    missingHost = {
      imports = [enabled];
      badwater.ai.pi.gitlab.host = lib.mkForce null;
    };
    invalidHost = {
      imports = [enabled];
      badwater.ai.pi.gitlab.host = lib.mkForce "https://example.test/path";
    };
    missingPackage = {
      imports = [enabled];
      badwater.ai.pi.gitlab.package = null;
    };
    piOff = {
      imports = [enabled];
      badwater.ai.pi.enable = lib.mkForce false;
    };
    excludeCodemode = {
      imports = [enabled];
      badwater.ai.pi.extraSettings.defaultTools = ["read"];
    };
    duplicate = {
      imports = [enabled];
      badwater.ai.pi.packages = [
        {
          name = "badwater-gitlab";
          package = pkgs.badwater-gitlab;
        }
      ];
    };
    conflictingPackage = {
      imports = [enabled];
      badwater.ai.pi.packages = [
        {
          name = "badwater-gitlab";
          package = pkgs.pi-coding-agent;
        }
      ];
    };
    namespaceCollision = {
      imports = [enabled];
      badwater.ai.pi.mcpServers.badwater_gitlab = {url = "https://other.example/mcp";};
    };
    badEnabled = {
      badwater.ai.pi = {
        enable = true;
        mcpServers.fixture = {
          url = "https://fixture.example/mcp";
          enabled = "false";
        };
      };
    };
    badExposure = {
      badwater.ai.pi = {
        enable = true;
        mcpServers.fixture = {
          url = "https://fixture.example/mcp";
          toolExposure = {get_project = "unknown";};
        };
      };
    };
    preserved = {
      imports = [enabled];
      badwater.ai.pi = {
        defaultModel = "existing-model";
        defaultProvider = "anthropic";
        extraSettings.compaction.keepRecentTokens = 9876;
        mcpServers.existing = {
          url = "https://existing.example/mcp";
          exposure = "hidden";
        };
      };
    };
  };
  summarize = extra: let
    c = (evaluate extra).config;
    typed = builtins.tryEval (builtins.deepSeq (map (p: toString p.package) c.badwater.ai.pi.packages) true);
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  in
    if !typed.success
    then {evaluationFailed = true;}
    else if failed != []
    then {inherit failed;}
    else {
      inherit failed;
      selected =
        map (p: {
          inherit (p) name;
          output = toString p.package;
        })
        c.badwater.ai.pi.packages;
      packages = map toString c.home.packages;
      files = lib.mapAttrs (_: f: toString f.source) (lib.filterAttrs (name: _: lib.hasPrefix ".pi/agent/nix-packages/" name) c.home.file);
      servers = c.badwater.ai.pi.mcpServers;
      enabled = c.badwater.ai.pi.gitlab.enable;
      activationNames = builtins.attrNames c.home.activation;
      preferences = {inherit (c.badwater.ai.pi) defaultModel defaultProvider extraSettings;};
    };
in
  lib.mapAttrs (_: summarize) cases
