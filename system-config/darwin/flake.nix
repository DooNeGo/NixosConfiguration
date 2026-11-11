{
  description = "nix-darwin configuration for macbook-air-m1";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      user = "DooNeGo";
    in
    {
      darwinConfigurations."macbook-air-m1" = inputs.nix-darwin.lib.darwinSystem {
        modules = [
          ./configuration.nix
          ./homebrew.nix
        ];
        specialArgs = { inherit inputs user; };
      };
    };
}
