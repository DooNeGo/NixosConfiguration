{ pkgs, ... }: {
  xdg = {
    enable = true;
    userDirs.enable = true;
    mimeApps.enable = true;

    configFile."mimeapps.list".force = true;

    portal.enable = true;

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
