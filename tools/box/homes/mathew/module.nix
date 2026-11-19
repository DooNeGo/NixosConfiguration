{ lib, ... }:
{
  # No polkit daemon runs in the container, so its agent has nothing to talk to.
  services.hyprpolkitagent.enable = lib.mkForce false;
}
