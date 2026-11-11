{ config, ... }:
let
  scriptPath = ".local/bin/set-random-wallpaper.sh";
in
{
  home.file."${scriptPath}" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      WALL_DIR=${../../assets/wallpapers}
      RANDOM_WALL=$(find "$WALL_DIR" -type f | shuf -n 1)
      exec hyprctl hyprpaper wallpaper ,"$RANDOM_WALL"
    '';
  };

  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Set random wallpaper on login";
      After = [
        "hyprpaper.service"
        "graphical-session.target"
      ];
      # hyprctl needs a running Hyprland; skip quietly in any other session instead of failing.
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      # hyprpaper may not listen on its socket yet right after start: a few spaced retries, not a burst.
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/${scriptPath}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [
        "graphical-session.target"
        "hyprpaper.service"
      ];
    };
  };
}
