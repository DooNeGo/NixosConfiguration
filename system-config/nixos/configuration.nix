{
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./locale.nix
    ./nix.nix
    ./programs.nix
    ./peripherals.nix
    ./zram.nix
    ./hyprland.nix
    ./users.nix
    ./steam.nix
    ./sddm.nix
    ./hyprland-session.nix
    ./steam-bigpicture-session.nix
    ./audio.nix
    ./murmur.nix
    ./printing.nix
    ./network.nix
    ./sing-box.nix
    ./sshd.nix
    #./virt-manager.nix
    #./docker.nix
    #./podman.nix
    ./nvidia.nix
    ./razer.nix
    ./tmux.nix
    ./xdg.nix
    #./gtk-theme.nix
    ./file-systems.nix
    #./bees.nix
    ./backup.nix
    ./failure-notify.nix
    ./smartd.nix
    ./throne.nix
    ./android.nix
    ./usbmux.nix
    ./remote-access.nix
    ./searx.nix
    ./whisper-cpp.nix
    ./shared-repo-acl.nix
  ];

  networking.hostName = "nixos";

  system.stateVersion = "26.05";
}
