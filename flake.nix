{
  description = "A simple development environent for the mangle engine";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    zig-flake = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-flake.follows = "zig-flake";
      };
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
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
      devShells = forEachSystem (
        system:
        let
          zig-override = final: prev: {
            zls = inputs.zls.packages.${system}.default;
            zig = inputs.zig-flake.packages.${system}.default;
          };
          pkgs = nixpkgs.legacyPackages.${system}.extend zig-override;
        in
        {
          default = pkgs.callPackage ./shell.nix {}; 
        }
      );
    };
}
