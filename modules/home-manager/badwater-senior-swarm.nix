{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai.pi;
  seniorSwarm = cfg.seniorSwarm;
  linux = pkgs.stdenv.hostPlatform.isLinux;
  subagents = pkgs.piPackages.pi-subagents or null;
in {
  options.badwater.ai.pi.seniorSwarm = {
    enable = lib.mkEnableOption "the approval-gated Badwater Senior Swarm package (does not authorize model, browser or network calls)";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if seniorSwarm.enable
        then pkgs.badwater-senior-swarm or null
        else null;
      description = "Nix-owned badwater-senior-swarm Pi package; no runtime installer or private Pi/subagent copy.";
    };
    maxConcurrent = lib.mkOption {
      type = lib.types.ints.between 1 6;
      default = 6;
      description = "Maximum concurrent swarm children (1..6).";
    };
    maxAgents = lib.mkOption {
      type = lib.types.ints.between 1 64;
      default = 32;
      description = "Logical agent admission budget (1..64), not a concurrency setting.";
    };
    maxRepairCycles = lib.mkOption {
      type = lib.types.ints.between 0 2;
      default = 2;
      description = "Maximum integrated QA/security repair cycles (0..2).";
    };
    roleModels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Optional namespaced role-to-model choices; absent roles inherit the parent model/provider.";
    };
    browser = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = linux;
        description = "Supply the packaged swarm browser on Linux. Installation is not permission to launch it; unsupported platforms fail closed.";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default =
          if seniorSwarm.enable && seniorSwarm.browser.enable && linux
          then pkgs.badwater-senior-swarm-browser or null
          else null;
        description = "Nix-owned package supplying bin/badwater-senior-swarm-browser, currently Linux only.";
      };
    };
    context7.enable = lib.mkOption {
      type = lib.types.bool;
      default = seniorSwarm.enable;
      description = "Declare Context7 HTTPS/codemode through the sole builtin MCP owner. OAuth is runtime-only; no credentials enter the store and no connection is made by activation.";
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !seniorSwarm.enable || cfg.enable;
          message = "badwater.ai.pi.seniorSwarm.enable requires badwater.ai.pi.enable.";
        }
        {
          assertion = !seniorSwarm.enable || seniorSwarm.package != null;
          message = "badwater.ai.pi.seniorSwarm.enable requires pkgs.badwater-senior-swarm or an explicit seniorSwarm.package.";
        }
        {
          assertion = !seniorSwarm.enable || builtins.any (p: p.name == "pi-subagents") cfg.packages;
          message = "badwater.ai.pi.seniorSwarm.enable requires a selected pi-subagents package.";
        }
        {
          assertion = !(seniorSwarm.enable && seniorSwarm.browser.enable) || (linux && seniorSwarm.browser.package != null);
          message = "Swarm browser integration requires Linux and pkgs.badwater-senior-swarm-browser or an explicit browser.package; disable browser on other platforms.";
        }
        {
          assertion = !seniorSwarm.context7.enable || cfg.enable;
          message = "Swarm Context7 integration requires badwater.ai.pi.enable.";
        }
      ];
    }
    (lib.mkIf seniorSwarm.enable {
      # Keep the consumer's existing extension load order; dedup its subagent first.
      badwater.ai.pi.packages = lib.mkAfter (
        lib.optional (seniorSwarm.package != null) {
          name = "badwater-senior-swarm";
          package = seniorSwarm.package;
        }
        ++ lib.optional (subagents != null) subagents
      );
      home.packages = lib.optional (seniorSwarm.browser.enable && linux && seniorSwarm.browser.package != null) seniorSwarm.browser.package;
    })
    (lib.mkIf seniorSwarm.context7.enable {
      badwater.ai.pi.mcpServers.context7 = {
        url = "https://mcp.context7.com/mcp";
        exposure = "codemode";
      };
    })
  ];
}
