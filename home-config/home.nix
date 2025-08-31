{ pkgs, ... }: {
  imports = [
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
  ];

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
      hyprpaper
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
