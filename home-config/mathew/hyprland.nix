_: {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = false;
    extraLuaFiles."default".content = ./hyprland.lua;
  };
}
