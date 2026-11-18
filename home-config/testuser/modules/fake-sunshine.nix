# Stands in for Sunshine (which runs for mathew only) to check the start order after hyprlock-initial.
_: {
  systemd.user.services.fake-sunshine = {
    Unit.PartOf = [ "graphical-session.target" ];
    Unit.After = [
      "graphical-session.target"
      "hyprlock-initial.service"
    ];
    Service.ExecStart = "/run/current-system/sw/bin/sleep infinity";
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
