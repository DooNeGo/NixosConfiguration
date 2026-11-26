{
  imports = [ ../shared/nix-settings.nix ];

  # On a timer instead of auto-optimise-store, which deduplicates on every build.
  nix.optimise.automatic = true;

  systemd.services.nix-daemon.environment = {
    # /tmp is a tmpfs here (boot.nix); CUDA and other large builds belong on the disk.
    TMPDIR = "/var/tmp";
  };
}
