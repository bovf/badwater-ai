{
  config,
  lib,
  pkgs,
  ...
}: let
  pi = config.badwater.ai.pi;
  cfg = pi.gitlab;
  host =
    if cfg.host == null
    then "gitlab.invalid"
    else cfg.host;
  # Exact names from GitLab's native MCP tool reference. New tools stay hidden.
  readTools = [
    "get_mcp_server_version"
    "get_project"
    "get_issue"
    "get_work_item"
    "get_merge_request"
    "list_merge_requests"
    "get_merge_request_commits"
    "get_merge_request_diffs"
    "get_merge_request_pipelines"
    "get_merge_request_notes"
    "get_repository_file"
    "list_repository_tree"
    "get_commit"
    "get_pipeline"
    "get_pipeline_jobs"
    "get_job"
    "list_pipelines"
  ];
in {
  options.badwater.ai.pi.gitlab = {
    enable = lib.mkEnableOption "the explicit GitLab skill/managed CLI and disabled-by-default native MCP entry (not network/auth permission)";
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Explicit GitLab DNS hostname, without scheme/path/credentials. Required when enabled; no implicit GitLab.com fallback.";
    };
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if cfg.enable
        then pkgs.badwater-gitlab or null
        else null;
      description = "Nix-owned skill package supplying bin/glab and the Pi manifest; no runtime installer.";
    };
    mcp.connect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicitly allow Pi to connect on startup. False keeps the entry disabled until human enablement; neither state grants OAuth or action approval. Managed switches reapply this value; trusted project overrides are separate.";
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || pi.enable;
          message = "badwater.ai.pi.gitlab.enable requires badwater.ai.pi.enable.";
        }
        {
          assertion = !cfg.enable || cfg.package != null;
          message = "badwater.ai.pi.gitlab.enable requires pkgs.badwater-gitlab or an explicit skill package.";
        }
        {
          assertion = !cfg.enable || (cfg.host != null && builtins.match "[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?" host != null);
          message = "GitLab requires an explicit DNS hostname without scheme/path/credentials.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      badwater.ai.pi.packages = lib.mkAfter (lib.optional (cfg.package != null) {
        name = "badwater-gitlab";
        package = cfg.package;
      });
      # Only the CLI enters PATH; skill package roots contain colliding manifests.
      home.packages = lib.optional (cfg.package != null) (cfg.package.cliPackage or pkgs.glab);
      badwater.ai.pi.mcpServers.badwater-gitlab = {
        url = "https://${host}/api/v4/mcp";
        enabled = cfg.mcp.connect;
        exposure = "hidden";
        toolExposure = lib.genAttrs readTools (_: "codemode");
        description = "Permission-first GitLab reads for an explicitly authorized host/project; writes and unknown tools are hidden.";
      };
    })
  ];
}
