{
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./journald.nix
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
    ./awg-exit-node.nix
    ./sshd.nix
    ./nvidia.nix
    ./razer.nix
    ../shared/nh.nix
    ../shared/tmux.nix
    ../shared/vim.nix
    ./xdg.nix
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
