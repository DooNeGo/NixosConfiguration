{ lib, pkgs, ... }:
let
  # Not tested yet, and they need what the box lacks (a btrfs mount, a disk, the network, secrets). Each comes back
  # with the environment it needs when a change asks for it.
  disabledUnits = [
    "awg-exit-node"
    "btrbk-home"
    "btrbk-system"
    "sing-box-credits-fetch"
    "sing-box-main-awg-prepare"
  ];
in
{
  # What lib.sh and the checks of this layer use.
  environment.systemPackages = with pkgs; [
    grim
    imagemagick
    jq
  ];

  # The sysfs entries of the real machine name its devices.
  boot.kernel.sysfs = lib.mkForce { };

  # Not tested; the document portal also needs a FUSE mount that a rootless container cannot make.
  xdg.portal.enable = lib.mkForce false;

  services = {
    btrbk.instances = lib.mkForce { };
    murmur.enable = lib.mkForce false;
    smartd.enable = lib.mkForce false;
    tailscale = {
      enable = lib.mkForce false;
      serve.enable = lib.mkForce false;
    };
    # Not tested, and in a container cupsd spins after SIGTERM (its notifier is owned by nobody) and holds up the stop.
    printing.enable = lib.mkForce false;
  };

  systemd.services = lib.genAttrs disabledUnits (_: {
    enable = lib.mkForce false;
  });
}
