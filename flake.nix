{
  description = "My system configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    nix-flatpak = {
      url = "github:gmodena/nix-flatpak/latest";
      #inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #nix-vscode-extensions = {
    #  url = "github:nix-community/nix-vscode-extensions";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-stable,
      home-manager,
      agenix,
      ...
    }:
    let
      system = "x86_64-linux";

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      pkgs-stable = import nixpkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            _module.args = {
              inherit pkgs-unstable pkgs-stable;
            };
          }
          ./system-config/configuration.nix
          ({ pkgs, ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                stable = import nixpkgs-stable {
                  system = pkgs.stdenv.hostPlatform.system;
                  config.allowUnfree = true;
                };
                unstable = import nixpkgs-unstable {
                  system = pkgs.stdenv.hostPlatform.system;
                  config.allowUnfree = true;
                };
                agenix = agenix.packages."${system}".default;
              })
            ];
          })
          inputs.stylix.nixosModules.stylix
          agenix.nixosModules.age
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.mathew = ./home-config/mathew/home.nix;
            };
          }
        ];
      };
    };
}
