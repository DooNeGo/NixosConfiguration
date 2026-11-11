# Pinned Rider version, shared by every flake through lib/pkgs.nix.
# Update: version + buildNumber from data.services.jetbrains.com/products/releases?code=RD,
# each hash from the .sha256 file next to the download (`nix hash convert --hash-algo sha256 --to sri <hex>`).
final: prev:
let
  version = "2026.2.4.1";
  buildNumber = "262.11879.119";
  base = "https://download.jetbrains.com/rider/JetBrains.Rider-${version}";
  sources = {
    x86_64-linux = {
      url = "${base}.tar.gz";
      hash = "sha256-kQ8nUDtAP5Ki+pq4bOMCbB8LqS43ygNYq6++Ht/fIa4=";
    };
    aarch64-darwin = {
      url = "${base}-aarch64.dmg";
      hash = "sha256-Emd888W3Jl/ya+nh7clz3rJijgR5PldZuMnqVd6AIOI=";
    };
  };
  inherit (final.stdenv.hostPlatform) system;
in
{
  jetbrains = prev.jetbrains // {
    rider = prev.jetbrains.rider.overrideAttrs (old: {
      inherit version;
      passthru = old.passthru // {
        inherit buildNumber;
      };
      src = final.fetchurl (
        sources.${system} or (throw "overlays/rider.nix: no pinned Rider source for ${system}")
      );
    });
  };
}
