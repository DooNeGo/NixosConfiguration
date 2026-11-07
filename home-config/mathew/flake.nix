{
  description = "Home Manager configuration for user mathew";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    nix-flatpak.url = "github:gmodena/nix-flatpak/latest";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";

      pkgs = (import ../../lib/pkgs.nix { inherit inputs; }).mkPkgs {
        inherit system;
        extraConfig.cudaSupport = true;
      };
    in
    {
      homeConfigurations.mathew = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
}
