{ config, lib, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    extraLuaFiles."default".content = ./hyprland.lua;
  };
}
