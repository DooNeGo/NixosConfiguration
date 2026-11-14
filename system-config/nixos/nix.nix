{ config, ... }:
{
  imports = [ ../shared/nix-settings.nix ];

  # On a timer instead of auto-optimise-store, which deduplicates on every build.
  nix.optimise.automatic = true;

  systemd.services.nix-daemon.environment = {
    # /tmp is a tmpfs here (boot.nix); CUDA and other large builds belong on the disk.
    TMPDIR = "/var/tmp";
    # The proxy address comes from sing-box.nix.
    inherit (config.environment.variables) HTTP_PROXY HTTPS_PROXY;
  };
}
