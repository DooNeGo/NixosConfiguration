{ config, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mathew = {
    isNormalUser = true;
    description = "mathew";
    extraGroups = [ "wheel" "openrazer" "input" ];
    packages = with pkgs; [
      waybar
      hyprpaper
      hyprpicker
      hyprsunset
      hyprshot
      nwg-dock-hyprland
      wofi
      mako
      telegram-desktop
      #jetbrains.rider
      dotnet-sdk_9
      jdk17
      remmina
      freerdp
      notes
    ];
  };

  users.users.games = {
    isNormalUser = true;
    description = "User for gaming";
    extraGroups = [ "games" "openrazer" "input" ];
    packages = with pkgs; [
      mangohud
    ];
  };

  #users.users.work = {
  #  isNormalUser = true;
  #  description = "User for work";
  #  extraGroups = [ "networkmanager" ];
  #};
}
