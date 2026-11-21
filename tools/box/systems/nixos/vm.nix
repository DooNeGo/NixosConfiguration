{ lib, pkgs, ... }:
{
  # The guest has no NVIDIA GPU, no btrfs /backup and no secrets: what needs them stays off, as in the container.
  hardware.nvidia-container-toolkit.enable = lib.mkForce false;
  systemd.services = {
    nvidia-target-temperature.enable = lib.mkForce false;
    btrfs-reclaim-backup.enable = lib.mkForce false;

    # The real system installs the NVIDIA EGL vendor, which finds no device in the guest and leaves Hyprland without
    # a renderer; the virtual GPU is Mesa's.
    hyprland-headless-mathew.environment.__EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
  };
}
