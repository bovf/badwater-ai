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
    plannotator-pi-extension
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

`settings.commitRules = true` installs a Pi extension that keeps generated commit
messages short and avoids co-author/signature trailers.

## Graphify integration

```nix
badwater.ai.graphify = {
  enable = true;
  package = pkgs.graphify;
  extras = [ "mcp" "pdf" "svg" "openai" "terraform" ];
  openaiKey.enable = true;
};
```

The module installs graphify skills for Pi, Claude Code, and opencode, plus MCP
wiring when enabled.

## Apps / development

```bash
nix run .#fmt           # auto-format Nix files with Alejandra
nix run .#fmt -- --check
nix run .#update        # update flake, format, and evaluate outputs
nix develop             # installs staged-file Alejandra pre-commit hook
```
