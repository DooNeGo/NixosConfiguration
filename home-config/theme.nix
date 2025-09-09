{ pkgs, config, nix-colors, ... }:
let
  scheme = config.colorScheme;
  contrib = nix-colors.lib.contrib { inherit pkgs; };
in {
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
      package = contrib.gtkThemeFromScheme { inherit scheme; };
      name = scheme.slug;
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

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "gtk2";
  };
}
