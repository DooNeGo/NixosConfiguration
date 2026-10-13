{
  inputs = {
    nix-openclaw.url = "github:openclaw/nix-openclaw/v2026.9.5";
    nixpkgs.follows = "nix-openclaw/nixpkgs";
    home-manager.follows = "nix-openclaw/home-manager";
    kokoro.url = "path:../../kokoro";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    inputs@{
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
            kokoro-ru = kokoro.packages.${system}.kokoro-ru;
            unstable = import inputs.nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
            stable = import inputs.nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
            openclawRuntimePlugins = (prev.openclawRuntimePlugins or { }) // {
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
      packages.${system}.kokoro-ru = pkgs.kokoro-ru;
    };
}
