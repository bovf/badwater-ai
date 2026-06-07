{nixpkgs}: {
  mkUpdateApp = system: let
    pkgs = nixpkgs.legacyPackages.${system};
    update = pkgs.writeShellApplication {
      name = "update";
      runtimeInputs = with pkgs; [nix git];
      text = ''
        nix flake update
        nix run .#fmt
        nix flake show --allow-import-from-derivation >/dev/null
      '';
    };
  in {
    type = "app";
    program = nixpkgs.lib.getExe update;
  };
}
