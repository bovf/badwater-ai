{
  inputs,
  system ? "x86_64-linux",
}: let
  lib = import (inputs.nixpkgs + "/lib");
  fixtures = final: _: let
    package = name: final.runCommand name {} ''mkdir -p "$out"'';
  in {
    pi-coding-agent = package "pi-fixture";
    badwater-screenshot = (package "badwater-screenshot-fixture").overrideAttrs (_: {passthru.cliPackage = package "badwater-screenshot-cli-fixture";});
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
            home.homeDirectory = "/tmp/screenshot-policy-home";
            home.stateVersion = "25.11";
          }
          extra
        ];
    };
  enabled = {
    badwater.ai.pi = {
      enable = true;
      screenshot.enable = true;
    };
  };
  cases = {
    defaultOff = {};
    baseline = {badwater.ai.pi.enable = true;};
    disabledPoison = {nixpkgs.overlays = lib.mkAfter [(_: _: {badwater-screenshot = throw "disabled screenshot forced";})];};
    enabled = enabled;
    missingPackage = {
      imports = [enabled];
      badwater.ai.pi.screenshot.package = null;
    };
    missingCli = {
      imports = [enabled];
      badwater.ai.pi.screenshot.package = pkgs.pi-coding-agent;
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
          name = "badwater-screenshot";
          package = pkgs.badwater-screenshot;
        }
      ];
    };
    collision = {
      imports = [enabled];
      badwater.ai.pi.mcpServers.badwater_screenshot = {command = "/fixture/other";};
    };
  };
  summarize = extra: let
    c = (evaluate extra).config;
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  in
    if failed != []
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
      servers = c.badwater.ai.pi.mcpServers;
      enabled = c.badwater.ai.pi.screenshot.enable;
      activationNames = builtins.attrNames c.home.activation;
    };
in
  lib.mapAttrs (_: summarize) cases
