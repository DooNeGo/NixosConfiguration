{
  pkgs,
  config,
  ...
}:
let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [
      "33"
      "36.1"
      "37.0"
    ];
    buildToolsVersions = [ "latest" ];
    abiVersions = [ "x86_64" ];
    includeEmulator = "if-supported";
    includeCmake = false;
    includeSources = true;
    includeSystemImages = true;
    useGoogleAPIs = true;
    extraLicenses = [ "android-sdk-license" ];
  };

  dotnet = pkgs.dotnet-sdk_10;

  riderFHS = pkgs.buildFHSEnv {
    name = "rider-fhs";
    targetPkgs =
      pkgs: with pkgs; [
        jetbrains.rider
        openssl
      ];
    profile = ''
      export _JAVA_OPTIONS="-Dij.load.shell.env=true $_JAVA_OPTIONS"
    '';
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
  jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-21;
  #jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-17;
in
{
  programs.jetbrains-remote = {
    enable = true;
    ides = [ pkgs.jetbrains.rider ];
  };

  home = {
    packages = with pkgs; [
      dotnet
      androidComposition.androidsdk
      riderDesktop
      riderFHS
      jdk
    ];

    sessionVariables = {
      JAVA_HOME = "$HOME/.android/jdk";
      DOTNET_ROOT = "${dotnet}/share/dotnet";
      PATH = "${dotnet}/bin:$PATH";
      ANDROID_HOME = "$HOME/.android/sdk";
      ANDROID_SDK_ROOT = "$HOME/.android/sdk";
      ANDROID_AVD_HOME = "$HOME/.android/avd";
    };

    file = {
      ".android/avd".source = config.lib.file.mkOutOfStoreSymlink "/var/lib/nocow/android-avds";
      ".android/sdk".source = config.lib.file.mkOutOfStoreSymlink androidHome;
      ".android/jdk".source = config.lib.file.mkOutOfStoreSymlink jdk.home;
      #".android/jdk17".source = config.lib.file.mkOutOfStoreSymlink jdk17.home;
    };
  };
}
