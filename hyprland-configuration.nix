{ config, pkgs, ... }:

{
  fonts.packages = with pkgs; [
    noto-fonts
    font-awesome
  ];

  environment.systemPackages = with pkgs; [
    hyprpolkitagent
    kitty
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
  ];

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
    };

    hyprlock.enable = true;
  };
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
  ];
}
