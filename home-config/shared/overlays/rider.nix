# Pinned Rider version, shared by every home-config flake.
# Update: version + buildNumber from data.services.jetbrains.com/products/releases?code=RD,
# hash from the .tar.gz.sha256 file next to the download.
final: prev: {
  jetbrains = prev.jetbrains // {
    rider = prev.jetbrains.rider.overrideAttrs (old: {
      version = "2026.2.4.1";
      passthru = old.passthru // { buildNumber = "262.11879.119"; };
      src = final.fetchurl {
        url = "https://download.jetbrains.com/rider/JetBrains.Rider-2026.2.4.1.tar.gz";
        hash = "sha256-kQ8nUDtAP5Ki+pq4bOMCbB8LqS43ygNYq6++Ht/fIa4=";
      };
    });
  };
}
