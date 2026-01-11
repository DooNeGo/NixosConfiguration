{ config, ... }:
let scriptPath = ".local/bin/set-random-wallpaper.sh";
in {
  home.file."${scriptPath}" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      WALL_DIR="$HOME/Wallpapers"
      RANDOM_WALL=$(find "$WALL_DIR" -type f | shuf -n 1)
      exec hyprctl hyprpaper reload ,"$RANDOM_WALL"
    '';
  };

  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Set random wallpaper on login";
     # Requires = [ "hyprpaper.service" "graphical-session.target" ];
      After = [ "hyprpaper.service" "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${config.home.homeDirectory}/${scriptPath}";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" "hyprpaper.service" ];
    };
  };
}
