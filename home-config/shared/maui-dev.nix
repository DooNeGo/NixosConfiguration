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

  androidHome = "${androidComposition.androidsdk}/libexec/android-sdk";
  jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-21;

  devEnvironment = {
    JAVA_HOME = "${config.home.homeDirectory}/.android/jdk";
    ANDROID_HOME = "${config.home.homeDirectory}/.android/sdk";
    ANDROID_SDK_ROOT = "${config.home.homeDirectory}/.android/sdk";
    ANDROID_AVD_HOME = "${config.home.homeDirectory}/.android/avd";
  };
in
{
  imports = [
    ./dotnet.nix
    ./rider.nix
  ];

  systemd.user.sessionVariables = devEnvironment;

  systemd.user.tmpfiles.rules = [
    "d /var/lib/nocow/${config.home.username} 0755 - - -"
    "d /var/lib/nocow/${config.home.username}/android-avds 0755 - - -"
  ];

  home = {
    packages = [
      androidComposition.androidsdk
      jdk
    ];

    sessionVariables = devEnvironment;

    file = {
      ".android/avd".source =
        config.lib.file.mkOutOfStoreSymlink "/var/lib/nocow/${config.home.username}/android-avds";
      ".android/sdk".source = config.lib.file.mkOutOfStoreSymlink androidHome;
      ".android/jdk".source = config.lib.file.mkOutOfStoreSymlink jdk.home;
    };
  };
}
