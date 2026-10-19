{
  description = "Home Manager configuration for user openclaw-npm";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";

      mkPkgs =
        p:
        import p {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

      pkgs = (mkPkgs nixpkgs).extend (final: prev: {
        unstable = mkPkgs inputs.nixpkgs-unstable;
        stable = mkPkgs inputs.nixpkgs-stable;
        jetbrains = prev.jetbrains // {
          rider = prev.jetbrains.rider.overrideAttrs (old: {
            version = "2026.2.3.1";
            passthru = old.passthru // { buildNumber = "262.10968.170"; };
            src = final.fetchurl {
              url = "https://download.jetbrains.com/rider/JetBrains.Rider-2026.2.3.1.tar.gz";
              hash = "sha256-+ksJpffPS2Y1sJOtxzE5kXeKjcdPJWFKK4l2sE3uXU4=";
            };
          });
        };
      });
    in
    {
      homeConfigurations.openclaw-npm = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
}
