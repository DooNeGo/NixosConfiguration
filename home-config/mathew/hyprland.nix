_: {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = false;
    # Loaded in name order.
    extraLuaFiles = {
      "hyprland/session".content = ./hyprland/session.lua;
      "hyprland/monitors".content = ./hyprland/monitors.lua;
      "hyprland/settings".content = ./hyprland/settings.lua;
      "hyprland/animations".content = ./hyprland/animations.lua;
      "hyprland/rules".content = ./hyprland/rules.lua;
      "hyprland/binds".content = ./hyprland/binds.lua;
    };
  };
}
