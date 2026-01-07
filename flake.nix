{
  description = "My system configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    #nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    stylix = {
      url = "github:nix-community/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, stylix, ... }:
  let
    system = "x86_64-linux";
    #pkgs-unstable = import nixpkgs-unstable {
    #  inherit system;
    #  config.allowUnfree = true;
    #};
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {
          #_module.args = {
          #  inherit pkgs-unstable;
          #};
        }
        ./system-config/configuration.nix
        inputs.stylix.nixosModules.stylix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
            users.mathew = ./home-config/home.nix;
          };
        }
      ];
    };
  };
}
