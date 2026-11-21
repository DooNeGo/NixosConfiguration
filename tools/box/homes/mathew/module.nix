{ lib, ... }:
{
  # Not tested: the headless session has no logind session for the agent, and the container has no polkit daemon.
  services.hyprpolkitagent.enable = lib.mkForce false;
}
