# Caller supplies pinned nixpkgs/home-manager paths; no producer package required.
# .matrix is evaluation-only; .sources builds generated files, never a home generation.
{
  inputs,
  system ? "x86_64-linux",
}: let
  lib = import (toString inputs.nixpkgs + "/lib");
  fixtures = final: _: let
    package = name: final.runCommand name {} ''mkdir -p "$out"'';
  in {
    pi-coding-agent = (package "pi-fixture").overrideAttrs (_: {passthru.openaiCodexContextWindows."gpt-6.1-sol" = 1050000;});
    badwater-senior-swarm = package "badwater-senior-swarm-fixture";
    badwater-senior-swarm-browser = package "badwater-senior-swarm-browser-fixture";
    piPackages.pi-subagents = {
      name = "pi-subagents";
      package = package "pi-subagents-fixture";
    };
    pi-search = package "pi-search-fixture";
    pi-search-mcp = package "pi-search-mcp-fixture";
    graphify = lib.makeOverridable (_: final.runCommand "graphify-fixture" {version = "fixture";} ''mkdir -p "$out"'') {};
    rea = (package "rea-fixture").overrideAttrs (_: {
      passthru = {
        mcpArgs = ["mcp"];
        skillRelativePath = "share/rea/skills/reverse-engineer-anything";
      };
    });
  };
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [fixtures];
  };
  enabled = {
    badwater.ai.pi = {
      enable = true;
      seniorSwarm.enable = true;
    };
  };
  baseline = {
    badwater.ai = {
      graphify.enable = true;
      rea.enable = system == "x86_64-linux";
      pi = {
        enable = true;
        webSearch.enable = true;
        graphify.mcp.enable = true;
        rea.mcp.enable = system == "x86_64-linux";
        openai.maxContext = true;
        defaultProvider = "openai";
        defaultModel = "explicit-model";
        extraSettings = {
          defaultTools = ["read" "+codemode"];
          compaction = {
            reserveTokens = 32000;
            keepRecentTokens = 60000;
            modelOverrides."openai/gpt-6.1-sol".reserveTokens = 123456;
          };
        };
      };
    };
  };
  http = {
    url = "https://fixture.example/mcp";
    exposure = "deferred";
  };
  cases = {
    defaultOff = {};
    disabledPoison = {
      nixpkgs.overlays = lib.mkAfter [
        (_: _: {
          badwater-senior-swarm = throw "disabled swarm forced";
          badwater-senior-swarm-browser = throw "disabled browser forced";
          piPackages = throw "disabled subagents forced";
        })
      ];
    };
    opted = enabled;
    duplicate = {
      imports = [enabled];
      badwater.ai.pi.packages = [
        pkgs.piPackages.pi-subagents
        {
          name = "badwater-senior-swarm";
          package = pkgs.badwater-senior-swarm;
        }
      ];
    };
    conflictingPackages = {
      imports = [enabled];
      badwater.ai.pi.packages = [
        {
          name = "badwater-senior-swarm";
          package = pkgs.pi-search;
        }
      ];
    };
    baseline = baseline;
    combined = {imports = [enabled baseline];};
    explicitSettings = {
      imports = [enabled];
      badwater.ai.pi = {
        defaultProvider = "anthropic";
        defaultModel = "explicit-parent";
        seniorSwarm.roleModels."badwater-senior-swarm.qa" = "qa-option";
        extraSettings = {
          defaultModel = "settings-parent";
          badwaterSeniorSwarm = {
            maxAgents = 7;
            roleModels."badwater-senior-swarm.developer" = "developer-explicit";
            browserCommand = "/fixture/custom-browser";
            opaque = {keep = true;};
          };
        };
      };
    };
    browserOff = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.browser.enable = false;
    };
    contextOff = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.context7.enable = false;
    };
    contextOnly = {
      badwater.ai.pi = {
        enable = true;
        seniorSwarm.context7.enable = true;
      };
    };
    contextOnlyPiOff = {badwater.ai.pi.seniorSwarm.context7.enable = true;};
    seniorSwarmPiOff = {
      imports = [enabled];
      badwater.ai.pi.enable = lib.mkForce false;
    };
    piOff = {badwater.ai.pi.enable = false;};
    missingPackage = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.package = null;
    };
    missingSubagents = {
      imports = [enabled];
      nixpkgs.overlays = lib.mkAfter [(_: _: {piPackages = {};})];
    };
    explicitSubagents = {
      imports = [enabled];
      nixpkgs.overlays = lib.mkAfter [(_: _: {piPackages = {};})];
      badwater.ai.pi.packages = [pkgs.piPackages.pi-subagents];
    };
    missingBrowser = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.browser = {
        enable = true;
        package = null;
      };
    };
    browserOn = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.browser.enable = true;
    };
    concurrentLow = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxConcurrent = 0;
    };
    concurrentHigh = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxConcurrent = 7;
    };
    agentsLow = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxAgents = 0;
    };
    agentsHigh = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxAgents = 65;
    };
    repairsLow = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxRepairCycles = -1;
    };
    repairsHigh = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm.maxRepairCycles = 3;
    };
    bounds = {
      imports = [enabled];
      badwater.ai.pi.seniorSwarm = {
        maxConcurrent = 1;
        maxAgents = 64;
        maxRepairCycles = 0;
      };
    };
    missingCodemode = {
      imports = [enabled];
      badwater.ai.pi.extraSettings.defaultTools = ["read"];
    };
    normalizedNames = {
      badwater.ai.pi.mcpServers = {
        context-7 = http;
        context_7 = http;
      };
    };
    validHTTP = {badwater.ai.pi.mcpServers.fixture = http;};
    validStreamable = {badwater.ai.pi.mcpServers.fixture = http // {type = "streamable-http";};};
    validLoopback = {badwater.ai.pi.mcpServers.fixture = http // {url = "http://[::1]:1234/mcp";};};
    mixed = {badwater.ai.pi.mcpServers.fixture = http // {command = "/fixture/server";};};
    mixedArgs = {badwater.ai.pi.mcpServers.fixture = http // {args = [];};};
    mixedEnv = {badwater.ai.pi.mcpServers.fixture = http // {env = {};};};
    mixedType = {badwater.ai.pi.mcpServers.fixture = http // {type = "stdio";};};
    plainHTTP = {badwater.ai.pi.mcpServers.fixture = http // {url = "http://example.com/mcp";};};
    userinfo = {badwater.ai.pi.mcpServers.fixture = http // {url = "https://synthetic@example.com/mcp";};};
    query = {badwater.ai.pi.mcpServers.fixture = http // {url = "https://example.com/mcp?synthetic";};};
    fragment = {badwater.ai.pi.mcpServers.fixture = http // {url = "https://example.com/mcp#synthetic";};};
    headers = {badwater.ai.pi.mcpServers.fixture = http // {headers = {};};};
    auth = {badwater.ai.pi.mcpServers.fixture = http // {auth = {};};};
    oauth = {badwater.ai.pi.mcpServers.fixture = http // {oauth = {};};};
    port = {badwater.ai.pi.mcpServers.fixture = http // {url = "https://example.com:65536/mcp";};};
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
            home.homeDirectory = "/tmp/policy-home";
            home.stateVersion = "25.11";
          }
          extra
        ];
    };
  summarize = extra: let
    c = (evaluate extra).config;
    typed = builtins.tryEval (builtins.deepSeq {
        inherit (c.badwater.ai.pi.seniorSwarm) maxConcurrent maxAgents maxRepairCycles;
        selected = map (p: toString p.package) c.badwater.ai.pi.packages;
      }
      true);
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  in
    if !typed.success
    then {evaluationFailed = true;}
    else if failed != []
    then {inherit failed;}
    else {
      inherit failed;
      seniorSwarmEnabled = c.badwater.ai.pi.seniorSwarm.enable;
      browserEnabled = c.badwater.ai.pi.seniorSwarm.browser.enable;
      selected =
        map (p: {
          inherit (p) name;
          package = toString p.package;
        })
        c.badwater.ai.pi.packages;
      packages = map toString c.home.packages;
      files = lib.mapAttrs (_: f: toString f.source) (lib.filterAttrs (name: _: lib.hasPrefix ".pi/agent/nix-packages/" name) c.home.file);
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
  matrix = lib.mapAttrs (_: summarize) cases;
  # Pull only generated file arguments from snippets. No activation is executed.
  storePaths = text: lib.filter (s: lib.hasPrefix "/nix/store/" s) (lib.splitString " " (builtins.replaceStrings ["\n" "\\"] [" " " "] text));
  sources = lib.unique (lib.concatMap (name: let
    c = matrix.${name};
  in
    lib.filter (s: lib.hasSuffix ".json" s || lib.hasSuffix ".py" s) (storePaths (c.mcp
      + (
        if c.settings == null
        then ""
        else c.settings
      )
      + (
        if c.keybindings == null
        then ""
        else c.keybindings
      )))) ["defaultOff" "opted" "duplicate" "baseline" "combined" "explicitSettings" "browserOff" "contextOff" "contextOnly" "piOff" "explicitSubagents" "bounds"]);
in
  assert (evaluate {}).options.badwater.ai.pi ? seniorSwarm;
  assert !((evaluate {}).options.badwater.ai.pi ? swarm); {
    inherit matrix;
    sources = pkgs.linkFarm "badwater-senior-swarm-policy-generated-sources" (lib.imap0 (i: path: {
        name = toString i;
        inherit path;
      })
      sources);
  }
