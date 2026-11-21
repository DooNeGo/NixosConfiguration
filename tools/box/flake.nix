{
  description = "Test box: applies the layers of tools/box to any system and home configuration and runs them in a rootless podman container or a QEMU VM";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      # The podman that tools/box/box runs: the host needs no podman of its own.
      packages.${system}.podman = pkgs.podman.out;

      lib = {
        mkSystem = { configuration, modules }: configuration.extendModules { inherit modules; };

        mkHome =
          { configuration, modules }:
          assert
            configuration.pkgs.stdenv.hostPlatform.isLinux || throw "the home configuration is not a Linux one";
          configuration.extendModules { inherit modules; };
      };
    };
}
