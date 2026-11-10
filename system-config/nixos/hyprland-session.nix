{ config, pkgs, ... }:
let
  uwsm = config.programs.uwsm.package;
  systemctl = "${config.systemd.package}/bin/systemctl";
  loginctl = "${config.systemd.package}/bin/loginctl";

  # Two graphical sessions of one user share one user manager (graphical-session.target, Sunshine, Steam, PipeWire),
  # so a seat session and the stream session exclude each other: refuse instead of evicting.
  refuseIfSeatSession = pkgs.writeShellScript "refuse-if-seat-session" ''
    ${loginctl} list-sessions --no-legend | ${pkgs.gawk}/bin/awk '$3 == "mathew" && $4 != "-" && $6 == "user" { f = 1 } END { exit !f }' || exit 0
    echo "mathew has a session on a seat; log it out first" >&2
    exit 1
  '';
  refuseLoginWhileStreaming = pkgs.writeShellScript "refuse-login-while-streaming" ''
    [ "$PAM_USER" = mathew ] || exit 0
    ! ${systemctl} is-active --quiet hyprland-headless-mathew.service
  '';
in
{
  # Modelled on nixpkgs services/wayland/cage.nix: a logind session on tty1 is needed for DRM master (DP-2); the UWSM
  # unit that Hyprland creates is a user unit and cannot create one. Same command as hyprland-uwsm.desktop, so
  # ~/.config/uwsm/env (NVIDIA env from Home Manager) is applied.
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

  # Hyprland without tty1 and without a seat: aquamarine has no headless-only mode and fails with "CBackend::create()
  # failed" unless its DRM backend starts. LIBSEAT_BACKEND=noop lets that backend open card0 directly; the video group
  # replaces the ACL that logind gives only to the active seat0 session. SDDM keeps tty1 and its DRM master, so there
  # is no modeset on DP-2 and only HEADLESS-1 is usable.
  users.users.mathew.extraGroups = [ "video" ];

  security.pam.services = {
    hyprland-headless-mathew.startSession = true;
    # Ahead of `account include login` (order 10100).
    sddm.rules.account.refuse-while-streaming = {
      order = 10000;
      control = "requisite";
      modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
      args = [
        "quiet"
        "${refuseLoginWhileStreaming}"
      ];
    };
  };

  systemd.services.hyprland-headless-mathew = {
    description = "Hyprland (UWSM, headless backend) session for mathew, started on demand";
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
      "display-manager.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    # SDDM must hold DRM master on DP-2 before this Hyprland opens card0.
    requires = [ "display-manager.service" ];
    # One Hyprland and one Steam client per user.
    conflicts = [
      "hyprland-mathew.service"
      "steam-bigpicture-mathew.service"
    ];
    environment = {
      LIBSEAT_BACKEND = "noop";
      AQ_DRM_DEVICES = "/dev/dri/card0";
      AQ_NO_KMS_REQUIREMENT = "1";
      HYPRLAND_START_LOCKED = "1";
    };
    serviceConfig = {
      # The session has no seat and no VT, so uwsm's prepare-env cannot find it by the foreground VT and fails
      # ("Could not determine session on foreground VT"). It skips that lookup when XDG_SEAT and XDG_SESSION_ID are
      # in the login environment. XDG_SEAT is passed to uwsm only: in the unit environment pam_systemd reads it, asks
      # logind for a session on seat0, fails and leaves XDG_RUNTIME_DIR unset.
      ExecStart = "${pkgs.coreutils}/bin/env XDG_SEAT=seat0 ${uwsm}/bin/uwsm start -e -D Hyprland hyprland.desktop";
      ExecStartPre = "${refuseIfSeatSession}";
      User = "mathew";
      Restart = "no";
      StandardOutput = "journal";
      StandardError = "journal";
      PAMName = "hyprland-headless-mathew";
    };
  };
}
