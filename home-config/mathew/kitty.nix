{ config, lib, ... }:
let
  style = import ./style lib;
in
{
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    settings = lib.mkAfter {
      env = "MATHEW_KITTY_PALETTE=1";
      font_family = style.fontFamily;
      font_size = 13;
      window_padding_width = style.gapInner;
      confirm_os_window_close = 0;
      background_opacity = style.windowAlpha;
    };

    # Colours of the wallpaper palette (wallpaper/); SIGUSR1 reloads running windows.
    extraConfig = "include ${config.home.homeDirectory}/.local/state/wallpaper-palette/kitty.conf";
  };
}
