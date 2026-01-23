{ pkgs, inputs, ... }: {
  imports = [
   # inputs.stylix.homeModules.stylix
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
    #./bash.nix
    ./random-wallpaper.nix
    ./hyprpaper.nix
    ./zsh.nix
    #./stylix.nix
    ./maui-dev.nix
    #./hyprlauncher.nix
    ./xdg.nix
  ];

  home = {
    username = "mathew";
    homeDirectory = "/home/mathew";
    stateVersion = "25.11";
    packages = with pkgs; [
      telegram-desktop
      freerdp
      notes
      kdiskmark
      compsize
      pv
      #osu-lazer
      hyprpicker
      hyprlauncher
      hyprpwcenter
      discord
      spotify
      google-chrome
      nemo
      kdePackages.gwenview
      gpu-screen-recorder-gtk
      polychromatic
      iotop
      iftop
      mumble
    ];
  };

  services = {
    remmina = {
      enable = true;
      systemdService.enable = false;
    };

    #gnome-keyring.enable = true;
    hyprpolkitagent.enable = true;
  };

  programs = {
    vscode = {
      enable = true;
      package = pkgs.vscode-fhs;
    };
  
    hyprshot = {
      enable = true;
      saveLocation = "$HOME/Pictures/Screenshots";
    };

    firefox = {
      enable = true;
      profiles = {
        default = { };
      };
    };
  };
}
