{ pkgs, ... }:  {
  home.pointerCursor = {
    enable = true;
    x11.enable = true;
    gtk.enable = true;

    hyprcursor = {
      enable = true;
      size = 30;
    };

    package = pkgs.rose-pine-hyprcursor;
    name = "rose-pine-hyprcursor";
    size = 30;
  };

  gtk = {
    enable = true;

    theme = {
      package = pkgs.paper-gtk-theme;
      name = "Paper";
    };

    iconTheme = {
      package = pkgs.paper-icon-theme;
      name = "Paper-Mono-Dark";
    };

    font = {
      name = "Sans";
      size = 11;
    };
  };
}
