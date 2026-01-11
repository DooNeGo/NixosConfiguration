{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./zram.nix
    ./hyprland.nix
    ./users.nix
    ./steam.nix
    ./sddm.nix
    ./audio.nix
    #./printing.nix
    ./network.nix
    ./sshd.nix
    #./virt-manager.nix
    ./docker.nix
    ./nvidia.nix
    #./home-manager.nix
    ./razer.nix
    ./tmux.nix
    ./xdg.nix
    ./gtk-theme.nix
    ./file-systems.nix
    ./stylix.nix
    ./throne.nix
    ./android.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.supportedFilesystems = [ "btrfs" ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.tmp = {
    useTmpfs = true;
    tmpfsHugeMemoryPages = "within_size";
  };

  networking.hostName = "nixos";

  time.timeZone = "Europe/Minsk";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocales = [ "ru_RU.UTF-8/UTF-8" ];
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  powerManagement.cpuFreqGovernor = "performance";

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    #egl-wayland
    #cacert
  ];

  hardware = {
    xone.enable = true;
    opentabletdriver.enable = true;
  };

  programs = {
    zsh.enable = true;
    gpu-screen-recorder.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 5d";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.firewall = {
    allowedTCPPorts = [ 57621 ];
    allowedUDPPorts = [ 5353 ];
  };

  system.stateVersion = "25.11";
}
