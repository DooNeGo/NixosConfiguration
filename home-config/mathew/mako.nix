{
  services.mako = {
    enable = true;
    settings = {
      border-radius = 10;
      default-timeout = 5000;
      margin = 5;
      padding = "10,5";
      #background-color = "#${palette.base00}";
      #text-color = "#${palette.base05}";
      #border-color = "#${palette.base03}";

      # System failures relayed by systembus-notify (system-config/failure-notify.nix) stay until dismissed.
      "app-name=system-notify" = {
        default-timeout = 0;
        border-color = "#ff5555";
      };
    };
  };
}
