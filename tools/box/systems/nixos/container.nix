{ lib, pkgs, ... }:
let
  # The container user cannot open /dev/dri/card0: the host group video is unmapped for it, and User= drops the groups
  # the container kept. So the user manager starts as the container root and changes its uid with the groups kept.
  userManager = pkgs.writeShellScript "box-user-manager" ''
    set -eu
    uid=$1
    gid=$(${pkgs.coreutils}/bin/id -g "$uid")
    ${pkgs.coreutils}/bin/chown -R "$uid:$gid" "/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service"
    exec ${pkgs.util-linux}/bin/setpriv --reuid="$uid" --regid="$gid" --keep-groups ${pkgs.systemd}/lib/systemd/systemd --user
  '';
in
{
  # A user unit that needs a razer device.
  hardware.openrazer.enable = lib.mkForce false;

  # Its capabilities (SYS_NICE, DAC_READ_SEARCH) are outside those of the container.
  security.rtkit.enable = lib.mkForce false;

  networking = {
    firewall.enable = lib.mkForce false;
    nftables.enable = lib.mkForce false;
  };

  services = {
    # The container uses the host resolver, which resolved cannot run with.
    resolved.enable = lib.mkForce false;
    displayManager.sddm.package = lib.mkForce (import ../../stubs/sddm.nix { inherit pkgs; });
  };

  systemd.services."user@" = {
    overrideStrategy = "asDropin";
    environment.XDG_RUNTIME_DIR = "/run/user/%i";
    serviceConfig = {
      User = "";
      PAMName = "";
      DelegateSubgroup = "";
      ExecStart = [
        ""
        "${userManager} %i"
      ];
    };
  };
}
