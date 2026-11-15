{ config, ... }: {
  programs.hyprlock = {
    enable = true;
    sourceFirst = true;
    settings = {
      # Defines $glass_fill, $glass_border and the palette colours (wallpaper/).
      source = "${config.home.homeDirectory}/.local/state/wallpaper-palette/hyprlock.conf";

      general.hide_cursor = true;

      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 6;
        }
      ];

      label = [
        {
          text = "$TIME";
          font_size = 72;
          font_family = "JetBrainsMono Nerd Font";
          color = "$on_surface";
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          size = "300, 50";
          position = "0, -40";
          halign = "center";
          valign = "center";
          rounding = 20;
          outline_thickness = 1;
          outer_color = "$glass_border";
          inner_color = "$glass_fill";
          font_color = "$on_surface";
          font_family = "JetBrainsMono Nerd Font";
          check_color = "$glass_border";
          fail_color = "$error";
          fade_on_empty = false;
          placeholder_text = "Пароль";
          dots_center = true;
        }
      ];
    };
  };
}
