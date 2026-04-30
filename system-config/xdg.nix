{
  xdg.portal = {
    enable = true;

    config = {
      common = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
      hyprland = {
        default = [ "hyprland" "gtk" ];
        #"org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        #"org.freedesktop.impl.portal.OpenURI" = [ "hyprland" ];  # ← Явно указываем бэкенд для OpenURI [[1]]
      };
    };
  };

  #environment.pathsToLink = [ "/share/xdg-desktop-portal" "/share/applications" ];
}
