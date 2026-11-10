# Shared pkgs construction for the system flake and the home-config flakes. A plain function, not a flake: every
# flake keeps its own inputs and lock, and passes them in. kokoro/ is standalone and deliberately does not use it.
{ inputs }:
rec {
  # Base nixpkgs config of the repo. cudaSupport is NOT here: it belongs to one host's main package set only,
  # otherwise pkgs.stable would build CUDA packages that no cache has.
  config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };

  channelsOverlay =
    _final: prev:
    let
      system = prev.stdenv.hostPlatform.system;
    in
    {
      stable = import inputs.nixpkgs-stable { inherit system config; };
    };

  riderOverlay = import ../overlays/rider.nix;

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
