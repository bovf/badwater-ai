# badwater-ai

Home Manager module for Badwater AI agent integrations.

This flake owns integration policy only. It does not package pi or graphify.
Consumers provide those packages through nixpkgs overlays and the module's
package options. Pi package integrations use stable Home Manager symlinks backed by Nix-built `pi-nix` packages, not runtime npm installs.

Example:

```nix
badwater.ai.pi.packages = with pkgs.piPackages; [
  rpiv-todo
  pi-subagents
];
```

## Outputs

```nix
homeManagerModules.default
homeManagerModules.ai
```

## Consumer example

```nix
inputs.badwater-ai = {
  url = "path:/Users/dobrynikolov/Documents/Develop/Nix/repos/badwater-ai";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In Home Manager modules:
inputs.badwater-ai.homeManagerModules.default
```
