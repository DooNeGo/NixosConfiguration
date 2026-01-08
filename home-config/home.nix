{ pkgs, inputs, pkgs-unstable, ... }: {
  imports = [
   # inputs.stylix.homeModules.stylix
    ./hyprland.nix
    #./theme.nix
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
    #./bash.nix
    ./random-wallpaper.nix
    ./hyprpaper.nix
    #./zsh.nix
   # ./stylix.nix
  ];

  home = {
    username = "mathew";
    homeDirectory = "/home/mathew";
    stateVersion = "25.11";
    packages = [
      pkgs.telegram-desktop
      pkgs.freerdp
      pkgs.notes
      pkgs.kdiskmark
      pkgs.compsize
      pkgs.pv
      #pkgs.osu-lazer
      pkgs.hyprpicker
      pkgs.hyprshot
      pkgs.discord
      pkgs.spotify
      pkgs.google-chrome
      pkgs.nemo
      pkgs.kdePackages.gwenview
      pkgs.gpu-screen-recorder-gtk
      pkgs.polychromatic
      pkgs.iotop
      pkgs.iftop
      #pkgs.dotnet-sdk_9
      #pkgs.jdk17
      #pkgs.jetbrains.rider
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
    vscode = {
      enable = true;
      package = pkgs.vscode-fhs;
    };

    firefox = {
      enable = true;
      profiles = {
        default = { };
      };
    };
  };
}
