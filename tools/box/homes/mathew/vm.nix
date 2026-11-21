{ lib, ... }:
{
  # The home selects the NVIDIA drivers of the real machine; the virtual GPU of the guest is Mesa's.
  home.sessionVariables = {
    GBM_BACKEND = lib.mkForce "dri";
    "__GLX_VENDOR_LIBRARY_NAME" = lib.mkForce "mesa";
    LIBVA_DRIVER_NAME = lib.mkForce "virtio_gpu";
  };

  # SDDM holds DRM master of the only display (Virtual-1, the DP-2 of the real machine, which the home configures):
  # a modeset of it fails, and without a rule Hyprland aborts on that.
  wayland.windowManager.hyprland.extraLuaFiles."hyprland/monitors-vm".content = ''
    hl.monitor({ output = "Virtual-1", disabled = true })
  '';
}
