{ pkgs, pkgs-unstable, config, ... }:
let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "33" "35" "36" ];
    buildToolsVersions = [ "36.0.0" ];
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
    targetPkgs = pkgs: with pkgs-unstable; [
      jetbrains.rider
    ] ++ (with pkgs; [
      gtk3
      gtk4
      dbus
      libglvnd

      libGL
      libGLU
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXtst
      gtk3
      alsa-lib
      freetype
      fontconfig

      openssl
    ]);
    profile = ''
      export _JAVA_OPTIONS="-Dawt.toolkit.name=WLToolkit -Dij.load.shell.env=true $_JAVA_OPTIONS"
      export XDG_OPEN_USE_PORTAL=1
    '';
    extraBinds = [
      "/run/dbus"
      "/run/user/${toString config.home.homeDirectory}"
    ];
    runScript = "rider";
  };

  riderDesktop = pkgs.makeDesktopItem {
      name = "rider";
      desktopName = "Rider";
      exec = "rider-fhs";
      terminal = false;
      mimeTypes = [ "text/plain" ];
    };

  androidHome = "${androidComposition.androidsdk}/libexec/android-sdk";
in { 
  home = {
    packages = with pkgs; [
      dotnet-sdk_10
      mono
      androidComposition.androidsdk
      riderDesktop
      riderFHS
      javaPackages.compiler.temurin-bin.jdk-21
    ];

    sessionVariables = {
      JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21.home}";
      DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
      PATH="${pkgs.dotnet-sdk_10}/bin:$PATH";
      ANDROID_HOME = androidHome;
      ANDROID_AVD_HOME = "$HOME/.android/avd";
    };

    file.".android/avd".source = config.lib.file.mkOutOfStoreSymlink "/var/lib/nocow/android-avds";
    file.".android/sdk".source = config.lib.file.mkOutOfStoreSymlink androidHome;
  };
}
