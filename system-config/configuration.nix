{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
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
  ];

  boot = {
    loader.systemd-boot.enable = true;

    loader.efi.canTouchEfiVariables = true;

    supportedFilesystems = [ "btrfs" ];

    kernelModules = [ "ntsync" ];

    kernelPackages = pkgs.linuxPackages_latest;

    tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
      tmpfsHugeMemoryPages = "within_size";
    };

    kernel.sysctl."vm.admin_reserve_kbytes" = 131072;
  };

  networking.hostName = "nixos";

  time.timeZone = "Europe/Minsk";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocales = [ "ru_RU.UTF-8/UTF-8" ];
  };

  powerManagement.cpuFreqGovernor = "performance";

  nixpkgs.config.allowUnfree = true;

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

  hardware = {
    xone.enable = true;
    opentabletdriver.enable = true;
  };

  programs = {
    zsh.enable = true;
    gpu-screen-recorder.enable = true;
    wireshark.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    # On a timer instead of auto-optimise-store, which deduplicates on every build.
    optimise.automatic = true;
  };

  systemd.services.nix-daemon.environment = {
    HTTP_PROXY = "http://127.0.0.1:2080";
    HTTPS_PROXY = "http://127.0.0.1:2080";
  };

  networking.firewall = {
    allowedTCPPorts = [
      57621
      8080
      18789
    ];
    allowedUDPPorts = [ 5353 ];
  };

  system.stateVersion = "26.05";
}
