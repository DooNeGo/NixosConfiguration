{ config, lib, ... }:
let
  style = import ./style lib;
in
{
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    settings = lib.mkAfter {
      font_family = style.fontFamily;
      font_size = 13;
      window_padding_width = style.gapInner;
      confirm_os_window_close = 0;
    };

    # Colours and background opacity of the wallpaper palette (wallpaper/); SIGUSR1 reloads running windows.
    extraConfig = "include ${config.home.homeDirectory}/.local/state/wallpaper-palette/kitty.conf";
  };
}
