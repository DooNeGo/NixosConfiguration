# Pinned Rider and JetBrains Gateway versions, shared by every flake through lib/pkgs.nix.
# Update: version + buildNumber from data.services.jetbrains.com/products/releases?code=RD (Gateway: code=GW),
# each hash from the .sha256 file next to the download (`nix hash convert --hash-algo sha256 --to sri <hex>`).
final: prev:
let
  riderVersion = "2026.3";
  riderBuildNumber = "263.7307.258";
  riderBase = "https://download.jetbrains.com/rider/JetBrains.Rider-${riderVersion}";
  riderSources = {
    x86_64-linux = {
      url = "${riderBase}.tar.gz";
      hash = "sha256-Hvx0/9CuHt8UN7NWKezwhi65dGQwxDE+bu9AhXUWXCE=";
    };
    aarch64-darwin = {
      url = "${riderBase}-aarch64.dmg";
      hash = "sha256-NxllC7K/Dw+S5UcgyfEgn96dG7MFQZNXgnYh9J1UN7s=";
    };
  };

  gatewayVersion = "2026.3";
  gatewayBuildNumber = "263.7307.184";
  gatewayBase = "https://download.jetbrains.com/idea/gateway/JetBrainsGateway-${gatewayVersion}";
  gatewaySources = {
    x86_64-linux = {
      url = "${gatewayBase}.tar.gz";
      hash = "sha256-RAs5Yd3/hbNlWJXjEKaRIAlhpGu2vC1xHZAxdzvforY=";
    };
    aarch64-darwin = {
      url = "${gatewayBase}-aarch64.dmg";
      hash = "sha256-hhPTakmE7/MtKvtWt45iL6fW3LjtEzMk47D+eIzsQWs=";
    };
  };

  inherit (final) lib;
  inherit (final.stdenv.hostPlatform) system;
in
{
  jetbrains = prev.jetbrains // {
    rider = prev.jetbrains.rider.overrideAttrs (old: {
      version = riderVersion;
      passthru = old.passthru // {
        buildNumber = riderBuildNumber;
      };
      # Since 2026.3: the MSAL sign-in library wants webkit2gtk-4.0 and libsoup-2.4, which nixpkgs no longer has,
      # and the Android debugger agent wants the bionic liblog.so.
      autoPatchelfIgnoreMissingDeps = lib.optionals final.stdenv.hostPlatform.isLinux [
        "libcurl.so.4"
        "libwebkit2gtk-4.0.so.37"
        "libjavascriptcoregtk-4.0.so.18"
        "libsoup-2.4.so.1"
        "libsecret-1.so.0"
        "liblog.so"
      ];
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
