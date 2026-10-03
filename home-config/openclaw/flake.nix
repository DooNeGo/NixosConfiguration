{
  inputs = {
    nix-openclaw.url = "github:openclaw/nix-openclaw/v2026.9.5";
    nixpkgs.follows = "nix-openclaw/nixpkgs";
    home-manager.follows = "nix-openclaw/home-manager";
    # Стенд-элон kokoro-flake (корень репо: ../../ относительно этого
    # flake.nix → NixosConfiguration/kokoro). Свой закреплённый nixpkgs
    # (c59305bab) — пакет оттуда, поэтому store-путь детерминирован.
    kokoro.url = "path:../../kokoro";
  };

  outputs =
    inputs@
    {
      nixpkgs,
      home-manager,
      nix-openclaw,
      kokoro,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
        overlays = [
          nix-openclaw.overlays.default
          (final: prev: {
            # Re-export пакета kokoro-flake: сборка идёт его собственным
            # закреплённым nixpkgs, здесь — только передача в pkgs/openclaw.nix.
            kokoro-ru = kokoro.packages.${system}.kokoro-ru;
            openclawRuntimePlugins =
              (prev.openclawRuntimePlugins or { })
              // {
                "lossless-claw" = import ./lossless-claw.nix { pkgs = final; };
              };
          })
        ];
      };

      mkUser =
        name:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            username = name;
          };
        };
    in
    {
      homeConfigurations = lib.genAttrs [ "openclaw" ] mkUser;

      # nix build .#kokoro-ru — тот же store-путъ, что и в kokoro-flake.
      packages.${system}.kokoro-ru = pkgs.kokoro-ru;
    };
}
