{
  config,
  lib,
  pkgs,
  ...
}: let
  pi = config.badwater.ai.pi;
  cfg = pi.screenshot;
  linux = pkgs.stdenv.hostPlatform.isLinux;
in {
  options.badwater.ai.pi.screenshot = {
    enable = lib.mkEnableOption "the badwater-screenshot skill and passive local MCP (not capture/focus/clipboard/image-sharing permission)";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if cfg.enable && linux
        then pkgs.badwater-screenshot or null
        else null;
      description = "Managed Linux screenshot package with bin/badwater-screenshot, Pi skill and cliPackage passthru; no runtime installer.";
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || pi.enable;
          message = "badwater.ai.pi.screenshot.enable requires badwater.ai.pi.enable.";
        }
        {
          assertion = !cfg.enable || linux;
          message = "badwater-screenshot GUI/headless package currently requires Linux.";
        }
        {
          assertion = !cfg.enable || (cfg.package != null && cfg.package ? cliPackage);
          message = "badwater-screenshot requires a package with cliPackage passthru (keep manifest roots out of PATH).";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      badwater.ai.pi.packages = lib.mkAfter (lib.optional (cfg.package != null) {
        name = "badwater-screenshot";
        package = cfg.package;
      });
      home.packages = lib.optional (cfg.package != null && cfg.package ? cliPackage) cfg.package.cliPackage;
      badwater.ai.pi.mcpServers.badwater-screenshot = lib.mkIf (cfg.package != null) {
        command = "${cfg.package}/bin/badwater-screenshot";
        args = ["mcp"];
        exposure = "codemode";
        description = "Operator-authorized screenshots: headless web/code first, explicit GUI targets, opt-in focus/clipboard changes; private metadata by default and separate image-sharing consent.";
      };
    })
  ];
}
