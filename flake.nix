{
  description = "A simple development environent for the Fisht Fighting game";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forEachSystem (system: let 
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = import ./shell.nix { inherit pkgs; };
      });
    };
}
