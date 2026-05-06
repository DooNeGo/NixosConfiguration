{ pkgs, ... }: {
  xdg = {
    enable = true;
    mimeApps.enable = true;

    portal = {
      enable = true;
      extraPortals = with pkgs; [ 
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
    };

    userDirs = {
      enable = true;
      createDirectories = true;
    };

    configFile."mimeapps.list".force = true;

    mimeApps.defaultApplications =
    let
      browser = "firefox.desktop";
    in {
      "image/png" = "org.kde.gwenview.desktop";
      "image/jpg" = "org.kde.gwenview.desktop";

      "text/html" = browser;
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;
    };
  };

  home.sessionVariables = {
    DEFAULT_BROWSER = "${pkgs.firefox}/bin/firefox";
  };
}
