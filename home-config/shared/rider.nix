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
    # Waybar finds the entry of a window by file name, so it is named after the window class; a search by
    # Name or Exec would not match "jetbrains-rider". A PNG, because Waybar loads an icon path with gdk-pixbuf.
    name = "jetbrains-rider";
    desktopName = "Rider";
    exec = "rider";
    icon = "${pkgs.jetbrains.rider}/share/icons/hicolor/128x128/apps/rider.png";
    startupWMClass = "jetbrains-rider";
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
