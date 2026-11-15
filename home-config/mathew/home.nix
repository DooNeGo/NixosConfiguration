{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./hyprland.nix
    ./theme.nix
    ./env.nix
    ./mako.nix
    ./mangohud.nix
    ./kitty.nix
    ./waybar.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./wlsunset.nix
    ./fastfetch.nix
    ./wallpaper
    ./hyprpaper.nix
    ../shared/zsh.nix
    ./zsh-theme.nix
    ../shared/auto-expire.nix
    ../shared/git.nix
    ../shared/git-identity.nix
    ../shared/maui-dev.nix
    ../shared/ssh.nix
    ./rofi.nix
    ./xdg.nix
    ./obs-studio.nix
    ./podman.nix
  ];

  home = {
    username = "mathew";
    homeDirectory = "/home/mathew";
    stateVersion = "26.05";
    packages = with pkgs; [
      telegram-desktop
      freerdp
      obsidian
      compsize
      osu-lazer-bin
      hyprpicker
      wl-clipboard
      hyprpwcenter
      discord
      spotify
      google-chrome
      nemo
      kdePackages.gwenview
      gpu-screen-recorder-gtk
      polychromatic
      mumble
      teams-for-linux
      libreoffice
      crosspipe
      pwvucontrol
      audacious
      smartmontools
      flatpak
      qbittorrent
      postman
    ];
  };

  services = {
    remmina = {
      enable = true;
      systemdService.enable = false;
    };

    flatpak.packages = [
      "ru.linux_gaming.PortProton"
    ];

    hyprpolkitagent.enable = true;
    cliphist.enable = true;
  };

  programs = {
    vscode = {
      enable = false;
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

    btop = {
      enable = true;
    };
  };
}
