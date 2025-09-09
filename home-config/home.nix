{ pkgs, nix-colors, ... }: {
  imports = [
    nix-colors.homeManagerModules.default
    ./hyprland.nix
    ./theme.nix
    ./env.nix
    ./mako.nix
    ./mangohud.nix
    ./kitty.nix
    ./waybar.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprsunset.nix
    ./wofi.nix
    ./git.nix
    ./fastfetch.nix
    ./bash.nix
    ./random-wallpaper.nix
    ./hyprpaper.nix
  ];

  colorScheme = nix-colors.colorSchemes.tokyo-city-dark;

  home = {
    username = "mathew";
    homeDirectory = "/home/mathew";
    stateVersion = "25.05";
    packages = with pkgs; [
      telegram-desktop
      freerdp
      notes
      kdiskmark
      osu-lazer
      hyprpicker
      hyprshot
      discord
      spotify
      google-chrome
      hiddify-app
      nemo
      kdePackages.gwenview
      gpu-screen-recorder-gtk
      polychromatic
      qemu_kvm
      iotop
    ];
  };

  services = {
    remmina = {
      enable = true;
      systemdService.enable = false;
    };

    hyprpolkitagent.enable = true;
  };

  programs = {
    vscode.enable = true;
    firefox.enable = true;
  };
}
