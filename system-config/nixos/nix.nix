{
  imports = [ ../shared/nix-settings.nix ];

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # On a timer instead of auto-optimise-store, which deduplicates on every build.
    optimise.automatic = true;
  };

  systemd.services.nix-daemon.environment = {
    HTTP_PROXY = "http://127.0.0.1:2080";
    HTTPS_PROXY = "http://127.0.0.1:2080";
  };
}
