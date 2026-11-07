{
  description = "My system configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      system = "x86_64-linux";
      pkgsLib = import ./lib/pkgs.nix { inherit inputs; };
    in
    {
      formatter.${system} = inputs.nixpkgs.legacyPackages.${system}.nixfmt-tree;

      nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./system-config/configuration.nix
          {
            nixpkgs.overlays = [
              pkgsLib.channelsOverlay
              (_final: _prev: { agenix = inputs.agenix.packages."${system}".default; })
            ];
          }
          inputs.agenix.nixosModules.age
        ];
      };
    };
}
