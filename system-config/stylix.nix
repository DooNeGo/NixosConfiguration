{ pkgs, ... }: {
  stylix = {
    enable = true;
    image = builtins.path { path = ../Wallpapers/default.jpg; };
    polarity = "light";

    fonts.sizes.terminal = 13;
    opacity.terminal = 0.65;

    icons = {
      enable = true;
      package = pkgs.paper-icon-theme;
      light = "Paper-Mono-Dark";
      dark = "Paper-Mono-Dark";
    };

    cursor = {
      package = pkgs.rose-pine-hyprcursor;
      name = "rose-pine-hyprcursor";
      size = 30;
    };
  };
}
