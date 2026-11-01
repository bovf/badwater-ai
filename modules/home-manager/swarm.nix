{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai.pi;
  swarm = cfg.swarm;
  linux = pkgs.stdenv.hostPlatform.isLinux;
  subagents = pkgs.piPackages.pi-subagents or null;
in {
  options.badwater.ai.pi.swarm = {
    enable = lib.mkEnableOption "the approval-gated Badwater swarm package (does not authorize model, browser or network calls)";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if swarm.enable
        then pkgs.badwater-swarm or null
        else null;
      description = "Nix-owned badwater-swarm Pi package; no runtime installer or private Pi/subagent copy.";
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
          if swarm.enable && swarm.browser.enable && linux
          then pkgs.badwater-swarm-browser or null
          else null;
        description = "Nix-owned package supplying bin/swarm-browser, currently Linux only.";
      };
    };
    context7.enable = lib.mkOption {
      type = lib.types.bool;
      default = swarm.enable;
      description = "Declare Context7 HTTPS/codemode through the sole builtin MCP owner. OAuth is runtime-only; no credentials enter the store and no connection is made by activation.";
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !swarm.enable || cfg.enable;
          message = "badwater.ai.pi.swarm.enable requires badwater.ai.pi.enable.";
        }
        {
          assertion = !swarm.enable || swarm.package != null;
          message = "badwater.ai.pi.swarm.enable requires pkgs.badwater-swarm or an explicit swarm.package.";
        }
        {
          assertion = !swarm.enable || builtins.any (p: p.name == "pi-subagents") cfg.packages;
          message = "badwater.ai.pi.swarm.enable requires a selected pi-subagents package.";
        }
        {
          assertion = !(swarm.enable && swarm.browser.enable) || (linux && swarm.browser.package != null);
          message = "Swarm browser integration requires Linux and pkgs.badwater-swarm-browser or an explicit browser.package; disable browser on other platforms.";
        }
        {
          assertion = !swarm.context7.enable || cfg.enable;
          message = "Swarm Context7 integration requires badwater.ai.pi.enable.";
        }
      ];
    }
    (lib.mkIf swarm.enable {
      # Keep the consumer's existing extension load order; dedup its subagent first.
      badwater.ai.pi.packages = lib.mkAfter (
        lib.optional (swarm.package != null) {
          name = "badwater-swarm";
          package = swarm.package;
        }
        ++ lib.optional (subagents != null) subagents
      );
      home.packages = lib.optional (swarm.browser.enable && linux && swarm.browser.package != null) swarm.browser.package;
    })
    (lib.mkIf swarm.context7.enable {
      badwater.ai.pi.mcpServers.context7 = {
        url = "https://mcp.context7.com/mcp";
        exposure = "codemode";
      };
    })
  ];
}
