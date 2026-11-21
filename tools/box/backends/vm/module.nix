{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  tmpfs = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
in
{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  virtualisation = {
    memorySize = 3072;
    cores = 4;
    # The root is a tmpfs: a start is a fresh system, like the rootfs of a container.
    diskImage = null;
    # The graphics (virtio GPU, display) and the serial console come from box at the start.
    graphics = false;
    # The user-mode network of QEMU stays, without a way out to the host network: the container has none either.
    restrictNetwork = true;
  };

  # qemu-vm.nix replaces the file systems of the real machine; what the real configuration still reads from them
  # (the btrfs units name /backup and /mnt/btrfs-top) gets a stub.
  fileSystems = lib.mkVMOverride {
    "/backup" = tmpfs;
    "/mnt/btrfs-top" = tmpfs;
  };

  # The host reaches the guest with ssh over vsock (no network): the key comes in as a systemd credential.
  boot.kernelModules = [ "vmw_vsock_virtio_transport" ];
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkForce "prohibit-password";
  };
  systemd.services.box-authorized-keys = {
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ImportCredential = "ssh.authorized_keys.root";
    };
    script = ''
      install -d -m 700 /root/.ssh
      install -m 600 "$CREDENTIALS_DIRECTORY/ssh.authorized_keys.root" /root/.ssh/authorized_keys
    '';
    path = [ pkgs.coreutils ];
  };
}
