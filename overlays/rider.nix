# Pinned Rider and JetBrains Gateway versions, shared by every flake through lib/pkgs.nix.
# Update: version + buildNumber from data.services.jetbrains.com/products/releases?code=RD (Gateway: code=GW),
# each hash from the .sha256 file next to the download (`nix hash convert --hash-algo sha256 --to sri <hex>`).
final: prev:
let
  riderVersion = "2026.2.4.1";
  riderBuildNumber = "262.11879.119";
  riderBase = "https://download.jetbrains.com/rider/JetBrains.Rider-${riderVersion}";
  riderSources = {
    x86_64-linux = {
      url = "${riderBase}.tar.gz";
      hash = "sha256-kQ8nUDtAP5Ki+pq4bOMCbB8LqS43ygNYq6++Ht/fIa4=";
    };
    aarch64-darwin = {
      url = "${riderBase}-aarch64.dmg";
      hash = "sha256-Emd888W3Jl/ya+nh7clz3rJijgR5PldZuMnqVd6AIOI=";
    };
  };

  gatewayVersion = "2026.2.4";
  gatewayBuildNumber = "262.11879.99";
  gatewayBase = "https://download.jetbrains.com/idea/gateway/JetBrainsGateway-${gatewayVersion}";
  gatewaySources = {
    x86_64-linux = {
      url = "${gatewayBase}.tar.gz";
      hash = "sha256-1yA0qzvMK52dBWi29X8qxy/IYy1110qm+JmV6KPzbc8=";
    };
    aarch64-darwin = {
      url = "${gatewayBase}-aarch64.dmg";
      hash = "sha256-tY9DqwG+k9CDU8QZhKtOSfe8bRifxFViSetrPtqQ09A=";
    };
  };

  inherit (final.stdenv.hostPlatform) system;
in
{
  jetbrains = prev.jetbrains // {
    rider = prev.jetbrains.rider.overrideAttrs (old: {
      version = riderVersion;
      passthru = old.passthru // {
        buildNumber = riderBuildNumber;
      };
      src = final.fetchurl (
        riderSources.${system} or (throw "overlays/rider.nix: no pinned Rider source for ${system}")
      );
    });

    gateway = prev.jetbrains.gateway.overrideAttrs (old: {
      version = gatewayVersion;
      passthru = old.passthru // {
        buildNumber = gatewayBuildNumber;
      };
      src = final.fetchurl (
        gatewaySources.${system} or (throw "overlays/rider.nix: no pinned Gateway source for ${system}")
      );
    });
  };
}
