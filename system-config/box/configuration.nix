{ lib, pkgs, ... }:
{
  boot.isContainer = true;
  system.stateVersion = "26.05";
  networking.useDHCP = false;

  programs = {
    hyprland.enable = true;
    hyprlock.enable = true;
    uwsm.enable = true;
  };
  environment.systemPackages = with pkgs; [
    grim
    imagemagick
    jq
    nix
  ];

  # Rootless podman cannot mount or reach what these need: the nix store and daemon come from the host.
  nix.enable = false;
  services.nscd.enable = false;
  system.nssModules = lib.mkForce [ ];
  # polkit and rtkit fail in a rootless container, which left systemd `degraded`; the session needs neither.
  security = {
    polkit.enable = lib.mkForce false;
    rtkit.enable = lib.mkForce false;
    pam.services.hyprland-headless-root.startSession = true;
  };
  # dbus-broker needs a kernel feature the container lacks (ENOPKG).
  services.dbus.implementation = lib.mkForce "dbus";

  # The session runs as the container's root, which is the host user that started the container: a user of the
  # container cannot open /dev/dri/card0 (the host group `video` is unmapped for it).
  # Linger keeps user@0 (and the bus that exec and switch use) alive while the session unit is stopped.
  users.users.root.linger = true;

  systemd = {
    mounts = lib.mkForce [ ];
    oomd.enable = false;

    # user@0 keeps the supplementary groups of the container root, the kept host group `video` among them.
    units."user@0.service" = {
      text = "[Service]\nUser=\nPAMName=\nEnvironment=XDG_RUNTIME_DIR=/run/user/0\n";
      overrideStrategy = "asDropin";
    };

    services.hyprland-headless-root = {
      description = "Hyprland (UWSM, headless backend) session for the container root";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
      ];
      wants = [ "systemd-logind.service" ];
      environment = {
        LIBSEAT_BACKEND = "noop";
        AQ_NO_KMS_REQUIREMENT = "1";
        HYPRLAND_START_LOCKED = "1";
        XDG_SESSION_CLASS = "user";
        XDG_RUNTIME_DIR = "/run/user/0";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
      };
      serviceConfig = {
        # Hyprland refuses root without the flag.
        ExecStart = "${pkgs.coreutils}/bin/env XDG_SEAT=seat0 ${pkgs.uwsm}/bin/uwsm start -e -D Hyprland -- ${pkgs.writeShellScript "hyprland-root" "exec ${pkgs.hyprland}/bin/Hyprland --i-am-really-stupid"}";
        PAMName = "hyprland-headless-root";
      };
    };
  };
}
