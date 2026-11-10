{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    htop
    kdiskmark
    nixfmt
    nixfmt-tree
    deadnix
    statix
    sshpass
    home-manager
    agenix
    iotop
    iftop
    unzip
    zip
    pv
    ntfs3g
  ];

  programs = {
    zsh.enable = true;
    gpu-screen-recorder.enable = true;
    wireshark.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;
}
