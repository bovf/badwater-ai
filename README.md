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
interrupt. Pi core does **not** load `~/.pi/agent/mcp.json`: the generated MCP
configuration needs an installed adapter extension. Web search also has a CLI
and skill fallback.

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
python3 tests/test_graphify_skill.py
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
Smoke-test Graphify's CLI/Python/MCP paths and the chosen Pi MCP adapter in an
isolated environment without credentials. A successful local flake check alone
is not evidence that those external packages work together.

Integration source audit (2026-09-05): published Pi `0.85.1`
([official docs/examples](https://github.com/earendil-works/pi/tree/d981de1229ef899957bbe968bc8dcda02a21f477/packages/coding-agent))
retains local package paths, settings, keybinding IDs and the commit-rule event
API. Graphifyy `0.9.54` ([PyPI source](https://pypi.org/project/graphifyy/0.9.54/))
retains the skill/reference layout and MCP entry point; its Python steps read
the sidecar initialized by our preamble. These are audit versions, not new pins
or claims about the consumer's installed versions. Newly offered upstream
extras/parsers are not automatically enabled or added to this module's options.
