{
  xdg = {
    enable = true;
    userDirs.enable = true;
    mimeApps.enable = true;

    configFile."mimeapps.list".force = true;

    portal = {
      enable = true;
      xdgOpenUsePortal = true;
    };

    mimeApps.defaultApplications = {
      "image/png" = [ "org.kde.gwenview.desktop" ];
      "image/jpg" = [ "org.kde.gwenview.desktop" ];

      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
    };
  };
}
