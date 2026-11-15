{ config, ... }: {
  services.mako = {
    enable = true;
    settings = {
      border-radius = 10;
      default-timeout = 5000;
      margin = 5;
      padding = "10,5";
      border-size = 1;
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
