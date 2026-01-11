{ pkgs, ... }:
let
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
      libglvnd

      openssl
      #dotnet-sdk_10
    ];
    profile = ''
      export _JAVA_OPTIONS="-Dawt.toolkit.name=WLToolkit $_JAVA_OPTIONS"
    '';
    runScript = "rider";
  };
in { 
  home = {
    packages = with pkgs; [
      javaPackages.compiler.temurin-bin.jdk-21
      #dotnet-sdk_10
      androidComposition.androidsdk
      #kitty
      riderFHS
      gnome-keyring
      #e2fsprogs
    ];
    sessionVariables = {
      JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21.home}";
      #DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
      #PATH="${pkgs.dotnet-sdk_10}/bin:$PATH";
      ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";
    };
  };
}
