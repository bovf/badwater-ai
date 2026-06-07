{
  description = "Home Manager module for Badwater AI agent integrations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: {
    homeManagerModules = {
      default = self.homeManagerModules.ai;
      ai = import ./modules/home-manager/ai.nix;
    };
  };
}
