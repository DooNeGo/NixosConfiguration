{ config, lib, ... }:
let
  style = import ./style lib;
in
{
  programs.hyprlock = {
    enable = true;
    # The system module installs it together with its PAM service.
    package = null;
    sourceFirst = true;
    settings = {
      # Defines every colour of the wallpaper palette as $<matugen name> (wallpaper/).
      source = "${config.home.homeDirectory}/.local/state/wallpaper-palette/hyprlock.conf";

      general.hide_cursor = true;

      animations = {
        enabled = true;
        bezier = [ "easeOut, 0.25, 0.1, 0.25, 1" ];
        animation = [
          "fadeIn, 1, 3, easeOut"
          "fadeOut, 1, 3, easeOut"
        ];
      };

      background = [
        {
          path = "${config.home.homeDirectory}/.local/state/wallpaper-palette/lock-background";
          blur_passes = style.blurPasses;
          blur_size = 6;
        }
      ];

      label = [
        {
          text = "$TIME";
          font_size = 72;
          font_family = style.fontFamily;
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
          rounding = style.radius;
          outline_thickness = style.borderWidth;
          outer_color = "$glass_border";
          inner_color = "$surface_container_high_panel";
          font_color = "$on_surface";
          font_family = style.fontFamily;
          check_color = "$outline_variant";
          fail_color = "$error";
          fade_on_empty = false;
          placeholder_text = "Пароль";
          dots_center = true;
        }
      ];
    };
  };
}
