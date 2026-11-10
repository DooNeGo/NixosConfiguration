{
  pkgs,
  config,
  ...
}:
let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [
      "29"
      "33"
      "36"
      "37.2"
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
    name = "rider";
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
    exec = "rider";
    terminal = false;
    mimeTypes = [ "text/plain" ];
  };

  androidHome = "${androidComposition.androidsdk}/libexec/android-sdk";
  jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-21;

  devEnvironment = {
    JAVA_HOME = "${config.home.homeDirectory}/.android/jdk";
    DOTNET_ROOT = "${dotnet}/share/dotnet";
    ANDROID_HOME = "${config.home.homeDirectory}/.android/sdk";
    ANDROID_SDK_ROOT = "${config.home.homeDirectory}/.android/sdk";
    ANDROID_AVD_HOME = "${config.home.homeDirectory}/.android/avd";
  };
in
{
  systemd.user.sessionVariables = devEnvironment;

  systemd.user.tmpfiles.rules = [
    "d /var/lib/nocow/${config.home.username} 0755 - - -"
    "d /var/lib/nocow/${config.home.username}/android-avds 0755 - - -"
  ];

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

    sessionVariables = devEnvironment // {
      PATH = "${dotnet}/bin:$PATH";
    };

    file = {
      ".android/avd".source =
        config.lib.file.mkOutOfStoreSymlink "/var/lib/nocow/${config.home.username}/android-avds";
      ".android/sdk".source = config.lib.file.mkOutOfStoreSymlink androidHome;
      ".android/jdk".source = config.lib.file.mkOutOfStoreSymlink jdk.home;
    };
  };
}
