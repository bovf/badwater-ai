# badwater-ai

Home Manager module for Badwater AI agent integrations.

This flake owns integration policy only. It does **not** package Pi or graphify.
Consumers provide packages through nixpkgs overlays, usually from:

```text
pi-nix       -> pi-coding-agent, pi-vim, pi-search, Pi packages
graphify-nix -> graphifyy + local .nix extractor
```

## Remote

```text
git@gitlab.dobryops.com:nix/badwater-ai.git
```

## Outputs

```nix
homeManagerModules.default
homeManagerModules.ai

apps.${system}.fmt
apps.${system}.update
devShells.${system}.default
```

## Consumer example

```nix
inputs.badwater-ai = {
  url = "git+ssh://git@gitlab.dobryops.com/nix/badwater-ai.git";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In Home Manager modules:
inputs.badwater-ai.homeManagerModules.default
```

## Pi integration

```nix
badwater.ai.pi = {
  enable = true;
  vim.modal.enable = false; # Archimedes Core provides the editor UI
  webSearch.enable = true;
  settings.commitRules = true;

  packages = with pkgs.piPackages; [
    hunk-review
    pi-archimedes
    pi-subagents
    remote-pi
    plannotator-pi-extension
    ponytail
    pi-wait-what
    pi-lsp
    pi-chrome-devtools
    pi-btw
    pi-goal
  ];
};
```

Pi packages are exposed to Pi through stable Home Manager symlinks:

```text
~/.pi/agent/nix-packages/<name>
```

The generated Pi settings use those stable paths, not raw `/nix/store/...` paths
and not runtime `npm:` installs.

`settings.commitRules = true` installs a Pi `before_agent_start` extension that
appends concise-commit/no-trailer instructions to the system prompt. It is agent
guidance, not a Git hook enforcing commit contents.

Settings and keybindings are writable copies re-applied on each Home Manager
switch; runtime edits can be overwritten. The external-editor binding remains
`ctrl+e`; enabling pi-vim reserves Escape for normal mode and uses `ctrl+c` to
interrupt. Pi `0.99.2`'s CLI loads `~/.pi/agent/mcp.json` through its built-in
MCP extension; SDK sessions must explicitly load the built-in extensions.
When the stable `pi-archimedes` package is selected, generated settings force
`"archimedes.mcp": { "enabled": false }`, preserving other keys in that
namespace. Pi's built-in MCP owns `/mcp` and the server connections; all other
Archimedes components and packaged image/delegation exclusions are unchanged.
This avoids older Archimedes' lazy `/mcp` registration bypassing Pi's load-time
replacement check. Archimedes `2.9` removes its MCP component; the setting remains
as a compatibility guard for older packages. Do not re-enable that component
alongside the builtin.
Web search also has a CLI and skill fallback; default MCP exposure uses codemode.

## Graphify integration

```nix
badwater.ai.graphify = {
  enable = true;
  package = pkgs.graphify;
  extras = [ "mcp" "pdf" "svg" "openai" "terraform" ];
  openaiKey.enable = true;
};
```

Enable each host's `graphify.enable` and `graphify.mcp.enable` separately, e.g.
`badwater.ai.pi.graphify.enable = true`. The module installs the corresponding
skills and `references/` sidecars for Pi, Claude Code, and opencode, plus MCP
wiring when requested.

The skill preamble bypasses upstream imperative installation and records the
Nix `graphify-python` wrapper for subsequent Python steps. The supplied package
must support `.override { extras = ...; }`, provide `bin/graphify` and
`bin/graphify-python`, and ship `graphify/skill{,-pi,-opencode}.md` and
`graphify/skills/{claude,pi,opencode}/references/` under the consumer's
`pkgs.python3.sitePackages`. The MCP wrapper calls `python -m graphify.serve`
with a graph path and uses the default stdio transport.

`openaiKey.enable` requires the consumer's sops module and secret declaration.
It reads the key only when the zsh `graphify` function runs, passing it to that
command rather than exporting it globally (which could change Pi OAuth billing).
This does not inject the key into MCP or direct `graphify-python` invocations.

## Apps / development

```bash
export NIX_CONFIG="${NIX_CONFIG-}"$'\nmax-jobs = 2\ncores = 4' # preserve existing settings
nix run .#fmt           # auto-format Nix files with Alejandra
nix run .#fmt -- --check
nix run .#update        # update all flake inputs, format, evaluate output tree
nix flake check --all-systems --allow-import-from-derivation
nix build --no-link .#devShells.x86_64-linux.default
nix shell --inputs-from . nixpkgs#python3 --command python3 tests/test_graphify_skill.py
# Optional: pass built directories containing SKILL.md and references/ to also
# check composed frontmatter, sidecars, reference targets and the real wrapper:
# ... tests/test_graphify_skill.py "$builtPiSkillDir" "$builtClaudeSkillDir" "$builtOpencodeSkillDir"
# Integration-only: tests/test_pi_mcp.mjs accepts a temporary HM manifest with
# homeDir, pi.path and packages.<name>.path; run Node 24 in that generated HOME
# under env -i PI_OFFLINE=1 in a private filesystem AND network namespace,
# exposing only /nix/store, the tests and that fixture, never live settings.
# Also run pi-nix/tests/bundled-cli.mjs <pi-output> --existing-settings in
# the fixture HOME/cwd: it retains generated policy and temporarily adds a probe.
nix develop            # installs staged-file Alejandra pre-commit hook
```

### Update coverage and ownership

`nix run .#update` runs `nix flake update`, the formatter, and `nix flake show`.
Currently `nixpkgs` is the only input; there are no additional owned source hashes,
package manifests, or dependency lockfiles. Tool dependencies (Nix, Git,
Alejandra, etc.) come from that input. The updater does **not** update Pi,
pi-vim, Pi extensions/search helpers, or Graphify source/dependency pins: those
belong to `pi-nix` and `graphify-nix`. Nor does it change model/policy defaults,
consumer locks, Home Manager, sops, or activated user configuration. Consumers
using `nixpkgs.follows` use their own nixpkgs revision instead of this lock.

`flake show` and `flake check` validate the local output tree, not a configured
Home Manager integration; this flake has no standalone Home Manager deployment.
After package-owner updates, the consumer must evaluate/build the combined Home
Manager configuration **without activation**, check stable Pi package links and
extension loading, and build all three composed Graphify skills (frontmatter,
references, Python site-packages alignment, wrapper and parser availability).
Smoke-test Graphify's CLI/Python/MCP paths and Pi's built-in MCP route in an
isolated environment without credentials. Load the CLI's actual built-in
factories, verify exactly one `/mcp` owner after Archimedes' actual lazy handler,
and exercise local initialize/list/get_node in cwd and `CLAUDE_PROJECT_DIR` modes.
Pi `0.99.2` sanitizes hyphens in tool names: the unchanged `web-search` server
exports `mcp__web_search__web_search`. A successful local flake check alone is not
evidence that those external packages work together.

Dependency audit (2026-10-01, independent policy stage): the existing updater
completed; the sole input, `nixpkgs`, remains at
`b6c8664de9b6cc07fe5666a29f91884ba81197c4`, matching the authoritative
[`nixpkgs-unstable` branch](https://api.github.com/repos/NixOS/nixpkgs/commits/nixpkgs-unstable)
at audit time. There are no owned npm/PyPI pins or nested dependency locks.
All-system flake evaluation and the source-side skill regression passed; the
x86_64-linux development shell and both apps were realized with temporary roots,
without entering the shell or activating Home Manager.

Pre-publication package-contract check (2026-10-01): a temporary Home Manager
fixture with completed local package overrides evaluated on all three supported
platforms. Native generated settings, keybindings, package links, MCP wrapper and
all three Graphify `0.9.73` skills/references were built and tested. Pi `0.99.2`
loaded the composed resources with zero errors, diagnostics or host-peer package
warnings, including repaired remote-pi and rpiv-todo. The actual Archimedes `2.9`
lazy handler passed; installed source/component inventory confirms MCP is absent,
not that the historical MCP disabled gate executed. Image/delegation exclusions
and the older-package settings guard remain intact.

An in-memory SDK session initialized/listed both generated MCP servers and
discovered 11 unique tools. It exercised Graphify `graph_stats`/`get_node` (label
and node_id) and empty web search in both root modes. The installed bundled CLI
regression separately loaded the generated policy/resources, asserted sole
builtin `/mcp` ownership and RPC startup/shutdown, restored unchanged settings,
and emitted no warnings.
Both used private filesystem/network namespaces with no live home, host sockets,
credentials or prompts. This establishes bundled loader/startup coverage, not full
TUI/user workflows, model, browser/LSP, remote service or hardware behavior.
These are local pre-publication checks; published consumer refs/follows still
require downstream validation.

Dependency refresh (2026-09-30): the complete local input graph (`nixpkgs` only)
was updated from `0a3468a402c449992505b6a9fc5b06580141b750` to
`b6c8664de9b6cc07fe5666a29f91884ba81197c4`, matching the upstream
[`nixpkgs-unstable` branch](https://api.github.com/repos/NixOS/nixpkgs/commits/nixpkgs-unstable)
at audit time. The sidecar regression and all-system flake evaluation passed;
the x86_64-linux development shell and both apps were realized without entering
the shell or activating Home Manager.

Pre-publication package-contract check (2026-09-30): a temporary Home Manager
configuration with local package overrides evaluated on all three supported
platforms. On x86_64-linux it built all three composed Graphify `0.9.72` skills,
references, writable-copy sources, stable Pi package links and MCP wrapper.
The skill regression passed against these actual composed files. Pi `0.99.1`
and Archimedes `2.8.0` exposed a lazy-registration collision with builtin MCP;
the owner explicitly selected Pi's builtin route and disabled only Archimedes'
MCP component. The new `tests/test_pi_mcp.mjs` loads the CLI's real builtin
factories, exercises Archimedes' actual lazy gate and checks a single `/mcp`
owner. A real in-memory SDK session starts only the MCP/discovery lifecycle;
local initialize/list, 11 unique tools, Graphify `graph_stats` and
`get_node` (label and node_id), and empty web-search passed in both root modes.
The real `pi mcp list` diagnostic also passed. No prompts, credentials,
activation or live settings were used; unrelated extension lifecycles were
not started.

Historical only (fixed and rejected by the October 1 regression): the September
30 check retained two package metadata warnings: `remote-pi`
declares Pi core/TUI/typebox as dependencies, and `rpiv-todo` declares typebox
likewise. Local copies exist; Pi's extension loader supplies host aliases,
but native imports could bypass them. That run allowed these exact warnings;
the current regression requires zero warnings and zero loader errors. Standalone loading
also retains pi-subagents' host-detection/eager-tool warning.
This is **local pre-publication validation**, not published-ref consumer
validation or a non-native build. Effective consumer follows and final
published revisions still require the downstream checks described above.

Previous integration source audit (2026-09-05): published Pi `0.85.1`
([official docs/examples](https://github.com/earendil-works/pi/tree/d981de1229ef899957bbe968bc8dcda02a21f477/packages/coding-agent))
retains local package paths, settings, keybinding IDs and the commit-rule event
API. Graphifyy `0.9.54` ([PyPI source](https://pypi.org/project/graphifyy/0.9.54/))
retains the skill/reference layout and MCP entry point; its Python steps read
the sidecar initialized by our preamble. These are audit versions, not new pins
or claims about the consumer's installed versions. Newly offered upstream
extras/parsers are not automatically enabled or added to this module's options.
