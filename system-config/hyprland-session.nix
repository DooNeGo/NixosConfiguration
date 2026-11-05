{ config, pkgs, ... }:
let
  uwsm = config.programs.uwsm.package;
  systemctl = "${config.systemd.package}/bin/systemctl";
in
{
  # Without autologin the session is started on demand (ssh in, `sudo systemctl start hyprland-mathew`).
  # Modelled on nixpkgs services/wayland/cage.nix: a logind session on tty1 is needed for DRM master (DP-2);
  # the UWSM unit that Hyprland creates is a user unit and cannot create one. Same command as hyprland-uwsm.desktop,
  # so ~/.config/uwsm/env (NVIDIA env from Home Manager) is applied.
  security.pam.services.hyprland-mathew.startSession = true;

  systemd.services.hyprland-mathew = {
    description = "Hyprland (UWSM) session for mathew, started on demand";
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
      "display-manager.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    # tty1 is taken by the display manager (physical login) while this runs.
    conflicts = [
      "getty@tty1.service"
      "display-manager.service"
    ];
    unitConfig.ConditionPathExists = "/dev/tty1";
    # hyprland.lua starts hyprlock when this is set: a remotely started session must not show an unlocked desktop.
    environment.HYPRLAND_START_LOCKED = "1";
    serviceConfig = {
      ExecStart = "${uwsm}/bin/uwsm start -e -D Hyprland hyprland.desktop";
      # Give tty1 back to the display manager for physical login.
      ExecStopPost = "-${systemctl} --no-block start display-manager.service";
      User = "mathew";
      IgnoreSIGPIPE = "no";
      UtmpIdentifier = "%n";
      UtmpMode = "user";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
      TTYVTDisallocate = "yes";
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      PAMName = "hyprland-mathew";
    };
  };
}
