{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.badwater.ai;

  buildModel = _id: m:
    {name = m.name;}
    // lib.optionalAttrs (m.contextWindow != null && m.maxOutput != null) {
      limit = {
        context = m.contextWindow;
        output = m.maxOutput;
      };
    };

  ollamaProvider = lib.optionalAttrs cfg.opencode.ollama.enable {
    ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama (local)";
      options = {
        baseURL = "${cfg.opencode.ollama.host}/v1";
        # @ai-sdk/openai-compatible requires a non-empty apiKey even when
        # the upstream doesn't use one.
        apiKey = "ollama";
      };
      models = lib.mapAttrs buildModel cfg.opencode.ollama.models;
    };
  };

  piExtensions = lib.optionals cfg.pi.vim.modal.enable ["${cfg.pi.vim.modal.package}"];

  piPackagePaths = map (pkg: "${config.home.homeDirectory}/.pi/agent/nix-packages/${pkg.name}") cfg.pi.packages;
  piUsesArchimedes = lib.any (pkg: pkg.name == "pi-archimedes") cfg.pi.packages;

  piPackageFiles = builtins.listToAttrs (map (pkg: {
      name = ".pi/agent/nix-packages/${pkg.name}";
      value.source = pkg.package;
    })
    cfg.pi.packages);

  piSettings = lib.filterAttrs (_: v: v != null) (
    {
      theme = cfg.pi.theme;
      defaultProvider = cfg.pi.defaultProvider;
      defaultModel = cfg.pi.defaultModel;
    }
    // lib.optionalAttrs (piExtensions != []) {
      extensions = piExtensions;
    }
    // lib.optionalAttrs (piPackagePaths != []) {
      packages = piPackagePaths;
    }
    // lib.optionalAttrs cfg.pi.vim.modal.enable {
      piVim = cfg.pi.vim.modal.settings;
    }
    // cfg.pi.extraSettings
  );

  piKeybindings =
    lib.optionalAttrs cfg.pi.vim.modal.enable {
      # Free Esc for normal-mode entry under pi-vim; ctrl+c stays as interrupt.
      "app.interrupt" = ["ctrl+c"];
    }
    // lib.optionalAttrs cfg.pi.enable {
      # ctrl+g (pi's default) collides with zellij's lock-toggle; alt+e is a
      # macOS dead key. ctrl+e is free in pi/zellij/ghostty/macOS.
      "app.editor.external" = ["ctrl+e"];
    }
    // lib.optionalAttrs piUsesArchimedes {
      # Archimedes image-paste owns ctrl+v; disable Pi's built-in handler.
      "app.clipboard.pasteImage" = [];
    };

  graphifyPkg = cfg.graphify.package.override {extras = cfg.graphify.extras;};

  # The upstream skill.md tries to bootstrap graphify via uv/pip/venv if the
  # graphify binary's shebang isn't a Python interpreter — which fails on our
  # bash-launcher Nix wrapper. This preamble tells the agent the install is
  # already done and which imperative paths must not be taken.
  graphifySkillPreamble = pkgs.writeText "graphify-skill-preamble.md" ''
    # ⚠ Read this BEFORE running anything from the rest of this skill

    **System context (added by the graphify-nix flake):**

    - source: graphify-nix flake (declarative package/module)
    - system: ${pkgs.stdenv.hostPlatform.system}
    - user: ${config.home.username}
    - graphify_install: graphify-nix overlay (overlays/graphify/) — NOT pip, uv, or pipx
    - graphify_version: ${graphifyPkg.version} + local nix-support.patch
    - graphify_binary: ${graphifyPkg}/bin/graphify
    - graphify_python: ${graphifyPkg}/bin/graphify-python (Python interpreter with graphify importable — use for `python -c ...` steps)
    - extras: ${builtins.concatStringsSep ", " cfg.graphify.extras}

    Graphify is **already installed** on this machine via the `graphify-nix`
    Nix overlay. The binary is on PATH at `graphify`; verify with
    `command -v graphify` → `${graphifyPkg}/bin/graphify`.

    ## DO NOT run any of these — they would create a parallel imperative install that bypasses the Nix closure

    - `uv tool install graphifyy` (any variant)
    - `pip install graphifyy` (with or without `--user`, `--break-system-packages`, `--upgrade`)
    - `python -m venv graphify-out/.venv && … pip install …` ← the upstream Step 1 fallback lands here
    - `pipx install graphifyy`
    - `npm install`, `brew install`, etc.

    ## Why the upstream Step 1 bootstrap fails here

    Upstream skill.md tries to detect a Python interpreter via the graphify
    binary's shebang. Our Nix wrapper's shebang is
    `#! /nix/store/.../bash -e` (a bash launcher, not a Python one), and the
    bootstrap's regex (`*[!a-zA-Z0-9/_.-]*`) rejects on the literal space
    before `-e`. It then falls through to imperative installers. **Skip the
    entire Step 1 block.**

    ## What to do instead

    **For CLI work** — most of the skill's actions — call `graphify`
    directly. It's a real binary on PATH:

    ```bash
    graphify --version
    graphify extract <path>
    graphify query "<question>"
    graphify path "A" "B"
    graphify update <path>
    ```

    **If a step requires the Python API** (e.g. `python -c "from graphify.detect import detect; …"`),
    use this exact line in place of the bootstrap's `$PYTHON`:

    ```bash
    PYTHON="${graphifyPkg}/bin/graphify-python"
    ```

    `graphify-python` is a regular Python interpreter (`python3 -c "…"`, `-m`,
    interactive REPL — all work normally) with graphify and every tree-sitter
    parser in its closure preloaded onto `sys.path`. Skill steps that do
    `$PYTHON -c "from graphify.detect import detect; detect(Path('.'))"` will
    work as-is once you point `$PYTHON` at this binary.

    Do NOT use `${graphifyPkg}/bin/.graphify-wrapped` for Python-API
    invocations — that wrapper unconditionally calls
    `graphify.__main__.main()` regardless of args.

    ## If `graphify` is missing from PATH

    **STOP.**

    ## If graphify reports "no LLM API key found"

    The AST/structural extraction has already run. Options, in order:

    1. `--backend ollama` if a local Ollama is reachable (heavy has one; mbair doesn't).
    2. Export `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` first.
    3. Stop and ask. **Do NOT fabricate a `manual_semantic.py`** — that
       produced fake semantic edges in a previous session. Use a real
       backend or `--no-cluster` to skip the semantic step.

    ## What's actually in the Nix closure

    - graphifyy ${graphifyPkg.version} (PyPI sdist + `overlays/graphify/nix-support.patch`
      which adds `extract_nix` for `.nix` files; Terraform/HCL support is upstream)
    - datasketch 1.10.0 (packaged inline; not in nixpkgs)
    - Tree-sitter Python bindings for: python, javascript, typescript, java,
      groovy, c, cpp, ruby, c-sharp, kotlin, scala, php, lua, swift, json,
      rust, **nix**, **hcl** (terraform/opentofu/terragrunt)
    - Extras: ${builtins.concatStringsSep ", " cfg.graphify.extras}

    ## What's NOT in the closure

    Tree-sitter parsers listed in graphify's pyproject but unused by
    `extract.py`: go, zig, powershell, elixir, objc, julia, verilog, fortran,
    bash, dm. Files in those languages fall back to text-mode community
    detection — no AST.

    ---

    # Upstream graphify skill manifest follows — Step 1 is OBSOLETE on this system, skip directly to Step 2
  '';

  graphifyComposedSkill = upstreamRelPath:
    pkgs.runCommand
    "graphify-skill-${builtins.replaceStrings ["."] ["-"] upstreamRelPath}.md"
    {}
    ''
      upstream=${graphifyPkg}/${pkgs.python3.sitePackages}/graphify/${upstreamRelPath}
      # Inject the preamble after the upstream YAML frontmatter (between
      # the two `---` lines) so the parser still sees name/description first.
      second=$(grep -n '^---$' "$upstream" | sed -n '2p' | cut -d: -f1)
      if [ -z "$second" ]; then
        cat ${graphifySkillPreamble} "$upstream" > $out
      else
        head -n "$second" "$upstream" > $out
        printf '\n' >> $out
        cat ${graphifySkillPreamble} >> $out
        printf '\n' >> $out
        tail -n "+$((second + 1))" "$upstream" >> $out
      fi
    '';

  graphifyMcpEntry = {
    command = "${graphifyPkg}/bin/graphify";
    args = ["--mcp"];
  };

  webSearchMcpEntry = {
    command = "${cfg.pi.webSearch.mcpPackage}/bin/pi-search-mcp";
    args = [];
  };

  claudeSettings =
    cfg.claudeCode.settings
    // lib.optionalAttrs cfg.claudeCode.graphify.mcp.enable {
      mcpServers =
        (cfg.claudeCode.settings.mcpServers or {})
        // {
          graphify = graphifyMcpEntry;
        };
    };

  piMcpServers = {
    mcpServers =
      lib.optionalAttrs cfg.pi.graphify.mcp.enable {
        graphify = graphifyMcpEntry;
      }
      // lib.optionalAttrs cfg.pi.webSearch.enable {
        web-search = webSearchMcpEntry;
      };
  };

  piCommitRulesExtension = pkgs.writeText "badwater-commit-rules.ts" ''
    import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

    export default function (pi: ExtensionAPI) {
      pi.on("before_agent_start", async (event) => ({
        systemPrompt: event.systemPrompt + `

    Commit rules:
    - Use concise conventional commit subjects when creating commits.
    - Keep commit messages to one subject line or at most 1-2 sentences.
    - Do not add Co-authored-by, Signed-off-by, or other co-author/signature trailers.
    `,
      }));
    }
  '';

  piWebSearchSkill = pkgs.writeText "pi-search-skill.md" ''
    ---
    name: web-search
    description: "Search the web via DuckDuckGo. Use when the user asks a factual question whose answer might be outside the agent's training data — release notes, current versions, recent events, API docs that may have changed."
    ---

    # web-search (DuckDuckGo)

    Two equivalent invocations — pick whichever your runtime supports:

    ## MCP tool (preferred)

    `web_search(query="<query>", max_results=10)` — if the `web-search` MCP server
    is loaded (registered in ~/.pi/agent/mcp.json), pi exposes the tool directly.

    ## CLI fallback

    ```bash
    pi-search "<query>"            # 10 results, JSON
    pi-search --max 20 "<query>"
    ```

    JSON shape: a list of `{title, url, abstract}` objects. Parse with `jq` if
    needed:

    ```bash
    pi-search "nix flake check usage" | jq -r '.[] | "\(.title)\n  \(.url)\n  \(.abstract)\n"'
    ```

    ## Constraints

    - DuckDuckGo, not Google. Some technical queries land on different top
      results — try rephrasing if the first 10 aren't useful.
    - No API key, no quota, but also no SLA — if `pi-search` returns
      non-zero, retry once and then surface the failure to the user
      rather than fabricating results.
    - Do NOT use this to fetch full page contents; it returns search
      result metadata only. Use `bash` + `curl` if you need a specific URL.
  '';
in {
  imports = [
    ./options.nix
  ];

  config = lib.mkMerge [
    (lib.mkIf cfg.opencode.enable {
      programs.opencode = {
        enable = true;
        settings = {
          provider = ollamaProvider;
        };
        tui = {
          theme = cfg.opencode.theme;
        };
      };

      home.shellAliases = lib.mkIf cfg.opencode.ollama.enable {
        ollama-start = ''
          if systemctl is-active --quiet ollama.service; then
            echo "ollama is already running"
          else
            systemctl start ollama.service && echo "ollama started"
          fi
        '';
        ollama-stop = ''
          if systemctl is-active --quiet ollama.service; then
            systemctl stop ollama.service && echo "ollama stopped"
          else
            echo "ollama is not running"
          fi
        '';
        ollama-status = "systemctl status ollama.service --no-pager -l";
      };
    })

    (lib.mkIf cfg.claudeCode.enable {
      home.packages = [cfg.claudeCode.package];
      home.sessionVariables = lib.mkIf cfg.claudeCode.noFlicker {
        CLAUDE_CODE_NO_FLICKER = "1";
      };
    })

    (lib.mkIf cfg.pi.enable {
      home.packages = [cfg.pi.package];
      home.file = piPackageFiles;

      # Activation copy (not home.file symlink) — pi mutates settings.json at
      # runtime via /settings, and a read-only symlink would break it.
      # Re-applied each switch, so runtime tweaks get clobbered.
      home.activation.badwaterPiSettings = config.lib.dag.entryAfter ["writeBoundary"] ''
        install -Dm644 ${pkgs.writeText "pi-settings.json" (builtins.toJSON piSettings)} \
          "$HOME/.pi/agent/settings.json"
      '';
    })

    (lib.mkIf cfg.graphify.enable {
      home.packages = [graphifyPkg];
    })

    (lib.mkIf (cfg.graphify.enable && cfg.graphify.openaiKey.enable) {
      sops.secrets.${cfg.graphify.openaiKey.secretName} = {};
      programs.zsh.initContent = lib.mkAfter ''
        graphify() {
          local _kp=${lib.escapeShellArg config.sops.secrets.${cfg.graphify.openaiKey.secretName}.path}
          if [ -r "$_kp" ]; then
            OPENAI_API_KEY="$(cat "$_kp")" command graphify "$@"
          else
            command graphify "$@"
          fi
        }
      '';
    })

    (lib.mkIf cfg.claudeCode.graphify.enable {
      home.file.".claude/skills/graphify/SKILL.md".source =
        graphifyComposedSkill "skill.md";
    })

    (lib.mkIf cfg.opencode.graphify.enable {
      home.file.".config/opencode/skills/graphify/SKILL.md".source =
        graphifyComposedSkill "skill-opencode.md";
    })

    (lib.mkIf cfg.pi.graphify.enable {
      home.file.".pi/agent/skills/graphify/SKILL.md".source =
        graphifyComposedSkill "skill-pi.md";
    })

    (lib.mkIf (cfg.pi.enable && cfg.pi.webSearch.enable) {
      home.packages = [cfg.pi.webSearch.package cfg.pi.webSearch.mcpPackage];
      home.file.".pi/agent/skills/web-search/SKILL.md".source = piWebSearchSkill;
    })

    (lib.mkIf (cfg.pi.enable && cfg.pi.settings.commitRules) {
      home.file.".pi/agent/extensions/badwater-commit-rules.ts".source = piCommitRulesExtension;
    })

    (lib.mkIf (cfg.claudeCode.enable
      && (cfg.claudeCode.graphify.mcp.enable
        || cfg.claudeCode.settings != {})) {
      home.activation.badwaterClaudeSettings = config.lib.dag.entryAfter ["writeBoundary"] ''
        install -Dm644 ${pkgs.writeText "claude-settings.json" (builtins.toJSON claudeSettings)} \
          "$HOME/.claude/settings.json"
      '';
    })

    (lib.mkIf cfg.claudeCode.enable {
      home.activation.badwaterClaudeKeybindings = config.lib.dag.entryAfter ["writeBoundary"] ''
        install -Dm644 ${pkgs.writeText "claude-keybindings.json" (builtins.toJSON cfg.claudeCode.keybindings)} \
          "$HOME/.claude/keybindings.json"
      '';
    })

    (lib.mkIf (cfg.opencode.enable && cfg.opencode.graphify.mcp.enable) {
      programs.opencode.settings.mcp.graphify = {
        type = "local";
        command = ["${graphifyPkg}/bin/graphify" "--mcp"];
        enabled = true;
      };
    })

    (lib.mkIf (cfg.pi.enable && (cfg.pi.graphify.mcp.enable || cfg.pi.webSearch.enable)) {
      home.activation.badwaterPiMcp = config.lib.dag.entryAfter ["writeBoundary"] ''
        install -Dm644 ${pkgs.writeText "pi-mcp.json" (builtins.toJSON piMcpServers)} \
          "$HOME/.pi/agent/mcp.json"
      '';
    })

    (lib.mkIf cfg.pi.enable {
      home.activation.badwaterPiKeybindings = config.lib.dag.entryAfter ["writeBoundary"] ''
        install -Dm644 ${pkgs.writeText "pi-keybindings.json" (builtins.toJSON piKeybindings)} \
          "$HOME/.pi/agent/keybindings.json"
      '';
    })

    {
      assertions = [
        {
          assertion = !cfg.claudeCode.enable || cfg.claudeCode.package != null;
          message = "badwater.ai.claudeCode.enable requires badwater.ai.claudeCode.package to be set.";
        }
        {
          assertion = !cfg.pi.enable || cfg.pi.package != null;
          message = "badwater.ai.pi.enable requires badwater.ai.pi.package to be set.";
        }
        {
          assertion = !cfg.pi.vim.modal.enable || cfg.pi.vim.modal.package != null;
          message = "badwater.ai.pi.vim.modal.enable requires badwater.ai.pi.vim.modal.package to be set.";
        }
        {
          assertion = !cfg.pi.webSearch.enable || (cfg.pi.webSearch.package != null && cfg.pi.webSearch.mcpPackage != null);
          message = "badwater.ai.pi.webSearch.enable requires badwater.ai.pi.webSearch.package and badwater.ai.pi.webSearch.mcpPackage to be set.";
        }
        {
          assertion = !cfg.graphify.enable || cfg.graphify.package != null;
          message = "badwater.ai.graphify.enable requires badwater.ai.graphify.package to be set.";
        }
        {
          assertion = !cfg.claudeCode.graphify.enable || cfg.graphify.enable;
          message = "badwater.ai.claudeCode.graphify.enable requires badwater.ai.graphify.enable = true.";
        }
        {
          assertion = !cfg.opencode.graphify.enable || cfg.graphify.enable;
          message = "badwater.ai.opencode.graphify.enable requires badwater.ai.graphify.enable = true.";
        }
        {
          assertion = !cfg.pi.graphify.enable || cfg.graphify.enable;
          message = "badwater.ai.pi.graphify.enable requires badwater.ai.graphify.enable = true.";
        }
        {
          assertion =
            !cfg.claudeCode.graphify.mcp.enable
            || (cfg.graphify.enable && builtins.elem "mcp" cfg.graphify.extras);
          message = "badwater.ai.claudeCode.graphify.mcp.enable requires badwater.ai.graphify.enable and \"mcp\" in badwater.ai.graphify.extras.";
        }
        {
          assertion =
            !cfg.opencode.graphify.mcp.enable
            || (cfg.graphify.enable && builtins.elem "mcp" cfg.graphify.extras);
          message = "badwater.ai.opencode.graphify.mcp.enable requires badwater.ai.graphify.enable and \"mcp\" in badwater.ai.graphify.extras.";
        }
        {
          assertion =
            !cfg.pi.graphify.mcp.enable
            || (cfg.graphify.enable && builtins.elem "mcp" cfg.graphify.extras);
          message = "badwater.ai.pi.graphify.mcp.enable requires badwater.ai.graphify.enable and \"mcp\" in badwater.ai.graphify.extras.";
        }
      ];
    }
  ];
}
