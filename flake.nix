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

    # age-encrypted secrets (agenix). Pinned to the 0.18.0 release.
    agenix = {
      url = "github:ryantm/agenix/0.18.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
          inputs.stylix.nixosModules.stylix
          # age-encrypted secrets (agenix); secrets are declared per-module
          # via age.secrets.* and decrypted at activation.
          inputs.agenix.nixosModules.age
          # inputs.nix-vscode-extensions.hmModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs pkgs-unstable pkgs-stable; };
              users.mathew = ./home-config/mathew/home.nix;
            };
          }
        ];
      };
    };
}
