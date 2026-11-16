{ config, lib, ... }:
let
  style = import ./style lib;
in
{
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
          blur_passes = style.blurPasses;
          blur_size = 6;
        }
      ];

      label = [
        {
          text = "$TIME";
          font_size = 72;
          font_family = style.fontFamily;
          color = "$text";
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
          rounding = style.radius;
          outline_thickness = style.borderWidth;
          outer_color = "$glass_border";
          inner_color = "$glass_fill";
          font_color = "$text";
          font_family = style.fontFamily;
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
