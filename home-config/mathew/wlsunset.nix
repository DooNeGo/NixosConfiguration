{
  # Sunrise and sunset come from the coordinates (location.nix); the theme follows the same sun (wallpaper/).
  services.wlsunset = {
    enable = true;
    inherit (import ./location.nix) latitude longitude;
    temperature = {
      day = 6500;
      night = 4500;
    };
  };
}
