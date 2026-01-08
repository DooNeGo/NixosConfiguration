{ pkgs ? import <nixpkgs> {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  }
}:

let
 # dotnet = pkgs.dotnet-sdk_10.overrideAttrs (finalAttrs: previousAttrs: {
 #   postBuild = (previousAttrs.postBuild or "") + ''
 #     for sdkVersion in $out/sdk/*; do
 #       featureBand=$(basename "$sdkVersion")
 #       mkdir -p $out/metadata/workloads/$featureBand
 #       touch $out/metadata/workloads/$featureBand/userlocal
 #     done
 #   '';
 # });

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "33" "36" ];
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
    includeEmulator = "if-supported";
    includeCmake = false;
    includeSources = true;
    includeSystemImages = true;
    extraLicenses = [ "android-sdk-license" ];
  };

#  dotnetFHS = pkgs.buildFHSEnv {
#    name = "dotnet-fhs";
#    targetPackages = with pkgs; [
#      dotnet
#    ];
#  };
in
  pkgs.mkShell {
    packages = with pkgs; [
      javaPackages.compiler.openjdk21
      jetbrains.rider
      dotnet-sdk_10
      androidComposition.androidsdk
    ];
    
    RIDER_USE_SYSTEM_ENV = true;
    JAVA_HOME = "${pkgs.javaPackages.compiler.openjdk21.home}";
    DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
    PATH="${pkgs.dotnet-sdk_10}/bin:$PATH";
    ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";

    shellHook = ''
      if ! dotnet workload list | grep -q "maui-android"; then
        echo "Installing maui workloads..."
        dotnet workload install maui-android android
      fi
      
      rider
    '';
  }
