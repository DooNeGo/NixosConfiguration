{ pkgs ? import <nixpkgs> {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  }
}:

let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "33" "36" ];
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "arm64-v8a" "x86_64" ];
    includeEmulator = "if-supported";
    includeCmake = false;
    extraLicenses = [ "android-sdk-license" ];
  };
in
pkgs.mkShell rec {
  buildInputs = [
    pkgs.dotnet-sdk_9
    pkgs.openjdk21
    androidComposition.androidsdk
  ];

  ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";
  DOTNET_ROOT = "${pkgs.dotnet-sdk_9}";

  shellHook = ''
    export DOTNET_WORKLOAD_INSTALL_DIR="$HOME/.dotnet"

    if ! dotnet workload list | grep -q "maui-android"; then
      echo "Устанавливаю workload maui-android..."
      dotnet workload install maui-android
    fi

    code &
  '';
}
