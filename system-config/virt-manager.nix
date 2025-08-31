{ pkgs, ... }:

{
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "mathew" ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      runAsRoot = false;
      package = pkgs.qemu_kvm;
    };
  };

  virtualisation.spiceUSBRedirection.enable = true;
}
