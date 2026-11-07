# Shared pkgs construction for the root flake and the home-config flakes. A plain function, not a flake: every
# flake keeps its own inputs and lock, and passes them in. kokoro/ is standalone and deliberately does not use it.
#
#   pkgsLib = import ../../lib/pkgs.nix { inherit inputs; };   # inputs needs nixpkgs, nixpkgs-stable, nixpkgs-unstable
#   pkgs = pkgsLib.mkPkgs { inherit system; };                 # Home Manager flakes
#   nixpkgs.overlays = [ pkgsLib.channelsOverlay ];            # NixOS: its pkgs is built by nixosSystem
{ inputs }:
rec {
  # Base nixpkgs config of the repo. cudaSupport is NOT here: it belongs to one host's main package set only,
  # otherwise pkgs.stable/pkgs.unstable would build CUDA packages that no cache has.
  config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };

  # pkgs.stable (the release channel) and pkgs.unstable, built with the base config.
  channelsOverlay =
    _final: prev:
    let
      system = prev.stdenv.hostPlatform.system;
    in
    {
      stable = import inputs.nixpkgs-stable { inherit system config; };
      unstable = import inputs.nixpkgs-unstable { inherit system config; };
    };

  # Pinned Rider, shared by every Home Manager flake (see the file for how to update it).
  riderOverlay = import ../home-config/shared/overlays/rider.nix;

  # The main package set of a Home Manager flake: base config (+ extraConfig), rider and the channels.
  mkPkgs =
    {
      system,
      extraConfig ? { },
      extraOverlays ? [ ],
    }:
    import inputs.nixpkgs {
      inherit system;
      config = config // extraConfig;
      overlays = [
        riderOverlay
        channelsOverlay
      ]
      ++ extraOverlays;
    };
}
