{ lib, pkgs, ... }:
{
  boot.isContainer = true;
  networking.useDHCP = false;

  # nix is for the activation of a Home Manager configuration inside.
  environment.systemPackages = [ pkgs.nix ];

  # Rootless podman cannot mount or reach what these need: the nix store and daemon come from the host.
  nix = {
    enable = false;
    gc.automatic = lib.mkForce false;
    optimise.automatic = lib.mkForce false;
  };
  services.nscd.enable = false;
  system.nssModules = lib.mkForce [ ];
  # dbus-broker needs a kernel feature the container lacks (ENOPKG).
  services.dbus.implementation = lib.mkForce "dbus";

  systemd = {
    mounts = lib.mkForce [ ];
    oomd.enable = false;

    # The session runs as the container root, which is the host user that started the container: a container user
    # cannot open /dev/dri/card0 (the host group `video` is unmapped for it). user@0 keeps the groups of that root.
    units."user@0.service" = {
      text = "[Service]\nUser=\nPAMName=\nEnvironment=XDG_RUNTIME_DIR=/run/user/0\n";
      overrideStrategy = "asDropin";
    };
  };
  # Keeps user@0 (and the bus that exec and the home activation use) alive while the session unit is stopped.
  users.users.root.linger = true;
}
