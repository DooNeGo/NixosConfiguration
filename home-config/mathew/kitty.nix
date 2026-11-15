{ config, lib, ... }: {
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    settings = lib.mkAfter {
      font_family = "JetBrainsMono Nerd Font";
      background_opacity = 0.65;
      window_padding_width = 5;
      confirm_os_window_close = 0;
    };

    # Colours of the wallpaper palette (wallpaper/); SIGUSR1 reloads running windows.
    extraConfig = "include ${config.home.homeDirectory}/.local/state/wallpaper-palette/kitty.conf";
  };
}
