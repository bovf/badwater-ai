{
  lib,
  pkgs,
  ...
}: {
  options.badwater.ai = {
    claudeCode = {
      enable = lib.mkEnableOption "Anthropic Claude Code CLI";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.claude-code or null;
        description = "Claude Code package. Set to null only when claudeCode.enable is false.";
      };

      noFlicker = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Export CLAUDE_CODE_NO_FLICKER=1 so the TUI doesn't flash on every keystroke under tmux/zellij.";
      };

      graphify = {
        enable = lib.mkEnableOption "register graphify as a Claude Code skill";
        mcp.enable = lib.mkEnableOption "register graphify --mcp as an MCP server in Claude Code";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {
          permissions.defaultMode = "auto";
          skipAutoPermissionPrompt = true;
          model = "claude-fable-5";
          effortLevel = "xhigh";
        };
        description = "Base content of ~/.claude/settings.json. Re-applied on every switch; runtime tweaks (e.g. /model) get clobbered.";
      };

      keybindings = lib.mkOption {
        type = lib.types.attrs;
        default = {
          "$schema" = "https://www.schemastore.org/claude-code-keybindings.json";
          "$docs" = "https://code.claude.com/docs/en/keybindings";
          bindings = [
            {
              context = "Chat";
              bindings = {
                "ctrl+g" = null;
                "ctrl+e" = "chat:externalEditor";
              };
            }
          ];
        };
        description = "Content of ~/.claude/keybindings.json.";
      };
    };

    pi = {
      enable = lib.mkEnableOption "pi coding agent (pi.dev)";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.pi-coding-agent or null;
        description = "pi-coding-agent package. Usually provided by the pi-nix overlay.";
      };

      theme = lib.mkOption {
        type = lib.types.str;
        default = "dark";
        description = "pi TUI theme. Built-in: \"dark\", \"light\". Custom themes live at ~/.pi/agent/themes/<name>.json.";
      };

      defaultProvider = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["anthropic" "openai"]);
        default = null;
        description = "settings.json defaultProvider. \"openai\" routes through the ChatGPT subscription OAuth (pi /login).";
      };

      defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "settings.json defaultModel (provider-specific id).";
      };

      extraSettings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Extra keys merged into ~/.pi/agent/settings.json. Schema: https://pi.dev/docs/latest/settings.";
        example = lib.literalExpression ''
          {
            defaultThinkingLevel = "medium";
            quietStartup = true;
            enabledModels = [ "claude-*" "gpt-5*" ];
          }
        '';
      };

      settings.commitRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install a pi extension that enforces concise conventional commit instructions.";
      };

      packages = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "^[A-Za-z0-9._-]+$";
              description = "Stable local pi package name under ~/.pi/agent/nix-packages/.";
            };

            package = lib.mkOption {
              type = lib.types.package;
              description = "Nix-built pi package directory.";
            };
          };
        });
        default = [];
        description = "Nix-managed pi packages exposed through stable local paths in ~/.pi/agent/nix-packages/.";
        example = lib.literalExpression ''
          [
            { name = "hunk-review"; package = pkgs.piPackages.hunk-review.package; }
            { name = "pi-archimedes"; package = pkgs.pi-archimedes; }
          ]
        '';
      };

      graphify = {
        enable = lib.mkEnableOption "register graphify as a pi skill";
        mcp.enable = lib.mkEnableOption "write ~/.pi/agent/mcp.json declaring graphify --mcp (best-effort; pi MCP docs are incomplete)";
      };

      vim.modal = {
        enable = lib.mkEnableOption "pi-vim modal editor (https://pi.dev/packages/pi-vim)";

        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.pi-vim or null;
          description = "pi-vim package. Usually provided by the pi-nix overlay.";
        };

        settings = lib.mkOption {
          type = lib.types.attrs;
          default = {
            clipboardMirror = "all";
            modeColors = {
              insert = "borderMuted";
              normal = "borderAccent";
              ex = "warning";
            };
            syncBorderColorWithMode = false;
          };
          description = "piVim block in ~/.pi/agent/settings.json. Default mirrors upstream pi-vim's recommended config.";
        };
      };

      webSearch = {
        # DuckDuckGo via ddgr; no API key, no quota. MCP wires into
        # ~/.pi/agent/mcp.json; CLI ships `pi-search` + a skill manifest so
        # the agent can fall back via bash if pi's MCP loading doesn't
        # surface the tool. See badwater.ai.pi.graphify.mcp.enable for the
        # same best-effort caveat about pi's MCP support.
        enable = lib.mkEnableOption "DuckDuckGo web search for pi (MCP + CLI fallback)";

        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.pi-search or null;
          description = "pi-search CLI package. Usually provided by the pi-nix overlay.";
        };

        mcpPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.pi-search-mcp or null;
          description = "pi-search MCP package. Usually provided by the pi-nix overlay.";
        };
      };
    };

    graphify = {
      enable = lib.mkEnableOption "graphify CLI (github:safishamsi/graphify)";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.graphify or null;
        description = "graphify package. Usually provided by the graphify-nix overlay.";
      };

      extras = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "mcp"
          "neo4j"
          "pdf"
          "watch"
          "svg"
          "leiden"
          "office"
          "google"
          "video"
          "kimi"
          "ollama"
          "bedrock"
          "gemini"
          "openai"
          "chinese"
          "terraform"
        ]);
        default = ["mcp" "pdf" "svg" "terraform"];
        description = "Optional extras compiled into graphify. \"video\" pulls faster-whisper+yt-dlp; \"leiden\" pulls graspologic (Python <3.13).";
      };

      openaiKey = {
        # Scoped to graphify only — pi prefers OPENAI_API_KEY over its OAuth
        # subscription, so a global export silently bills the API account
        # instead of the ChatGPT subscription.
        enable = lib.mkEnableOption "inject OPENAI_API_KEY from sops into graphify invocations only (zsh wrapper)";

        secretName = lib.mkOption {
          type = lib.types.str;
          default = "graphify_openai_api_key";
          description = "sops secret name. Must match a key in secrets/secrets.yaml.";
        };
      };
    };

    opencode = {
      enable = lib.mkEnableOption "opencode AI coding agent";

      theme = lib.mkOption {
        type = lib.types.str;
        default = "catppuccin";
        description = "opencode TUI theme. Available: opencode, catppuccin, catppuccin-macchiato, tokyonight, everforest, ayu, gruvbox, kanagawa, nord, matrix, one-dark, system.";
      };

      graphify = {
        enable = lib.mkEnableOption "register graphify as an opencode skill";
        mcp.enable = lib.mkEnableOption "register graphify --mcp as an MCP server in opencode";
      };

      ollama = {
        enable = lib.mkEnableOption "Ollama local provider in opencode";

        host = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:11434";
          description = "Base URL of the local Ollama server.";
        };

        models = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Display name in the opencode model picker.";
              };
              contextWindow = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Max context tokens.";
              };
              maxOutput = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Max output tokens. Required together with contextWindow.";
              };
            };
          });
          default = {};
          description = "Ollama models keyed by their ollama model id.";
          example = lib.literalExpression ''
            {
              "qwen3.5:9b" = { name = "Qwen 3.5 9B (local)"; contextWindow = 32768; };
            }
          '';
        };
      };
    };
  };
}
