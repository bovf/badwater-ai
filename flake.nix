{
  description = "Home Manager module for Badwater AI agent integrations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

    appsLib = import ./nix/apps {inherit nixpkgs;};
    shellsLib = import ./nix/shells;
  in {
    homeManagerModules = {
      default = self.homeManagerModules.ai;
      ai = import ./modules/home-manager/ai.nix;
    };

    apps = forAllSystems (system: appsLib.mkApps system);

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      pi-openai-context =
        pkgs.runCommand "badwater-pi-openai-context-tests" {
          nativeBuildInputs = [pkgs.python3];
        } ''
          export PYTHONDONTWRITEBYTECODE=1 HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          python3 ${self}/tests/test_pi_openai_context.py
          touch "$out"
        '';
      pi-mcp-merge =
        pkgs.runCommand "badwater-pi-mcp-merge-tests" {
          nativeBuildInputs = [pkgs.python3];
        } ''
          export PYTHONDONTWRITEBYTECODE=1 HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          python3 ${self}/tests/test_pi_mcp_merge.py
          printf 'PASS additive Pi MCP ownership tests\\n' > "$out"
        '';
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      apps = appsLib.mkApps system;
    in
      shellsLib {
        inherit pkgs;
        fmtApp = apps.fmt;
      });
  };
}
