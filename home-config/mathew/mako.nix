{ config, lib, ... }:
let
  style = import ./style lib;
in
{
  services.mako = {
    enable = true;
    settings = {
      border-radius = style.radius;
      default-timeout = 5000;
      margin = style.gapInner;
      padding = "10,5";
      border-size = style.borderWidth;
      # Colours of the wallpaper palette (wallpaper/).
      include = "${config.home.homeDirectory}/.local/state/wallpaper-palette/mako";

      # Critical notifications (system failures from system-config/nixos/failure-notify.nix) stay until dismissed.
      "urgency=critical" = {
        default-timeout = 0;
        border-color = "#ff5555";
      };
    };
  };
}
