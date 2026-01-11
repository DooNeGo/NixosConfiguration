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

  riderFHS = pkgs.buildFHSEnv {
    name = "rider-fhs";
    targetPkgs = pkgs: with pkgs; [
      jetbrains.rider
      gtk3
      dbus
      openssl
      libglvnd
    ];
   # extraBuildCommands = ''
   #   echo "-Dawt.toolkit.name=WLToolkit" >> ${pkgs.jetbrains.rider}/bin/rider64.vmoptions
   # '';
    profile = ''
      export _JAVA_OPTIONS="-Dawt.toolkit.name=WLToolkit $_JAVA_OPTIONS"
    '';
    runScript = "rider";
  };
in
  pkgs.mkShell {
    packages = with pkgs; [
      javaPackages.compiler.temurin-bin.jdk-21
      dotnet-sdk_10
      androidComposition.androidsdk
      kitty
      riderFHS
      gnome-keyring
      e2fsprogs
    ];
    
    JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21.home}";
    DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
    PATH="${pkgs.dotnet-sdk_10}/bin:$PATH";
    ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";

    shellHook = ''
      open_terminal() {
        local cmd="$1"
        local title="$2"
        
        kitty --title "$title" sh -c "$cmd; read -p 'Press Enter to close...'"
      }

      if dotnet workload list 2>/dev/null | grep -q "maui-android"; then
        echo "✅ MAUI workloads installed. Checking for updates..."
        if dotnet workload update --check-only 2>&1 | grep -q "Updates are available"; then
          echo "🎉 Updates available! Opening terminal for update..."
          open_terminal "dotnet workload update" "MAUI Workload Update"
        else
          echo "✅ Workloads are up to date."
        fi
      else
        echo "MAUI workloads not found. Opening terminal for installation..."
        open_terminal "dotnet workload install maui-android android" "MAUI Workload Installation"
      fi

      echo "Starting Rider..."
      rider-fhs
    '';
  }
