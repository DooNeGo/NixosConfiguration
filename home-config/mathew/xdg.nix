{ config, pkgs, ... }: {
  xdg = {
    enable = true;
    mimeApps.enable = true;

    userDirs = {
      enable = true;
      createDirectories = true;
    };

    configFile."mimeapps.list".force = true;

    # UWSM sources this file at login; it is the only path that carries HM session variables into the compositor session.
    configFile."uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";

    mimeApps.defaultApplications =
      let
        browser = "firefox.desktop";
      in
      {
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
