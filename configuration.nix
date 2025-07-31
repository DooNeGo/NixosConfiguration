# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.devices = [ "/dev/vda" ];

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Minsk";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mathew = {
    isNormalUser = true;
    description = "mathew";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      steam
      firefox
      google-chrome
      waybar
      hyprpaper
      hyprpicker
      hypridle
      hyprlock
      hyprsunset
      hyprshot
      wofi
      mako
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    kitty
    weston
    polkit
    xdg-desktop-portal-hyprland
    hyprpolkitagent
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    font-awesome
  ];

  services.dbus.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  systemd.user.services.hyprland = {
    description = "Hyprland Wayland Compositor";
    wants = [ "dbus.socket" ];
    after = [ "dbus.socket" ];

    serviceConfig = {
      ExecStart = "${pkgs.hyprland}/bin/Hyprland";
      Type = "notify";
      Restart = "on-failure";
      KillMode = "process";
    };

    wantedBy = [ "default.target" ];
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  zramSwap = {
    enable = true;
    priority = 100;
    memoryPercent = 100;
  };

  services.zram-generator = {
    enable = true;
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;
  };


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
