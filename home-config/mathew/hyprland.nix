{ lib, ... }:
let
  style = import ./style lib;
  layouts = import ./layouts.nix;
  lua = file: {
    content = style.subst (
      builtins.replaceStrings [ "@kb_layout@" ] [ (lib.concatMapStringsSep "," (l: l.code) layouts) ] (
        builtins.readFile file
      )
    );
  };
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = false;
    # Loaded in name order.
    extraLuaFiles = {
      "hyprland/session" = lua ./hyprland/session.lua;
      "hyprland/monitors" = lua ./hyprland/monitors.lua;
      "hyprland/settings" = lua ./hyprland/settings.lua;
      "hyprland/animations" = lua ./hyprland/animations.lua;
      "hyprland/rules" = lua ./hyprland/rules.lua;
      "hyprland/binds" = lua ./hyprland/binds.lua;
    };
  };
}
