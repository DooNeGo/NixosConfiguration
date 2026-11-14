{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

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
in
{
  programs.jetbrains-remote = lib.mkIf isLinux {
    enable = true;
    ides = [ pkgs.jetbrains.rider ];
  };

  home.packages =
    if isLinux then
      [
        riderDesktop
        riderFHS
      ]
    else
      [ pkgs.jetbrains.gateway ];
}
