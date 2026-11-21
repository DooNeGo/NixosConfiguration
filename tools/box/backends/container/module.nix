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
  };
}
