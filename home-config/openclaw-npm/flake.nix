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

      pkgs = ((mkPkgs nixpkgs).extend (import ../shared/overlays/rider.nix)).extend (final: prev: {
        unstable = mkPkgs inputs.nixpkgs-unstable;
        stable = mkPkgs inputs.nixpkgs-stable;
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
