let wallpaperPath = "~/Wallpapers/default.jpg";
in {
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = wallpaperPath;
      wallpaper = ",${wallpaperPath}";
    };
  };
}
