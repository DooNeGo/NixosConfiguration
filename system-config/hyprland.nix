{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    noto-fonts
    font-awesome
  ];

  security.polkit.enable = true;

  environment.systemPackages = with pkgs; [
    hyprland-qt-support
  ];

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
    };
  };

  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
  ];

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };
}
