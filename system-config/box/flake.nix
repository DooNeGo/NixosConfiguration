{
  description = "NixOS system that scripts/box.sh runs in rootless podman as the test target";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      nixosConfigurations.box = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };

      # The podman that scripts/box.sh runs: the host needs no podman of its own.
      packages.${system}.podman = pkgs.podman.out;
    };
}
