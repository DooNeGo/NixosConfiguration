{
  inputs = {
    nix-openclaw.url = "github:openclaw/nix-openclaw/v2026.9.5";
    nixpkgs.follows = "nix-openclaw/nixpkgs";
    home-manager.follows = "nix-openclaw/home-manager";
  };

  outputs =
    inputs@
    {
      nixpkgs,
      home-manager,
      nix-openclaw,
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
        overlays = [ nix-openclaw.overlays.default ];
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
    };
}
