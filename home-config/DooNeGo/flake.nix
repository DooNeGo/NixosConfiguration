{
  description = "Home Manager configuration for user DooNeGo (macbook-air-m1)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      pkgs = (import ../../lib/pkgs.nix { inherit inputs; }).mkPkgs { system = "aarch64-darwin"; };
    in
    {
      homeConfigurations.DooNeGo = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
