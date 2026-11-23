{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;

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
}
