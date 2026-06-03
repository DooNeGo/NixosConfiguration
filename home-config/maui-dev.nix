{ pkgs, pkgs-unstable, pkgs-stable, config, ... }:
let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "33" "35" "36" ];
    buildToolsVersions = [ "latest" "36.0.0" ];
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
    includeEmulator = "if-supported";
    includeCmake = false;
    includeSources = true;
    includeSystemImages = true;
    extraLicenses = [ "android-sdk-license" ];
  };

#  dotnet-combined = (with pkgs.dotnetCorePackages; combinePackages [
#      sdk_10_0
#      sdk_9_0
#    ]).overrideAttrs (finalAttrs: previousAttrs: {
#      # This is needed to install workload in $HOME
#      # https://discourse.nixos.org/t/dotnet-maui-workload/20370/2
#
#      postBuild = (previousAttrs.postBuild or '''') + ''
#        for i in $out/sdk/*
#        do
#          i=$(basename $i)
#          mkdir -p $out/metadata/workloads/''${i/-*}
#          touch $out/metadata/workloads/''${i/-*}/userlocal
#        done
#      '';
#    });

  dotnet = pkgs.dotnet-sdk_10;

  riderFHS = pkgs.buildFHSEnv {
    name = "rider-fhs";
    targetPkgs = pkgs: with pkgs; [
      jetbrains.rider
    ] ++ (with pkgs; [
#      gtk3
#      gtk4
#      dbus
#      libglvnd
#
#      libGL
#      libGLU
#      xorg.libX11
#      xorg.libXext
#      xorg.libXrandr
#      xorg.libXtst
#      gtk3
#      alsa-lib
#      freetype
#      fontconfig

      openssl
      #wayland
    ]);
    profile = ''
      export _JAVA_OPTIONS="-Dawt.toolkit.name=WLToolkit -Dij.load.shell.env=true $_JAVA_OPTIONS"
    '';
#    extraBinds = [
#      "/run/dbus"
#      "/run/user/${toString config.home.homeDirectory}"
#    ];
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
      dotnet
      androidComposition.androidsdk
      riderDesktop
      riderFHS
      javaPackages.compiler.temurin-bin.jdk-21
    ];

    sessionVariables = {
      JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21.home}";
      DOTNET_ROOT = "${dotnet}/share/dotnet";
      PATH="${dotnet}/bin:$PATH";
      ANDROID_HOME = androidHome;
      ANDROID_AVD_HOME = "$HOME/.android/avd";
    };

    file.".android/avd".source = config.lib.file.mkOutOfStoreSymlink "/var/lib/nocow/android-avds";
    file.".android/sdk".source = config.lib.file.mkOutOfStoreSymlink androidHome;
  };
}
