_: {
  services = {
    sunshine = {
      enable = true;
      autoStart = true;
      openFirewall = true;
      settings = {
        capture = "wlr";
        encoder = "nvenc";
        nvenc_preset = 4;
        min_log_level = 3;
        lan_encryption_mode = 0;
        wan_encryption_mode = 1;
        csrf_allowed_origins = "https://nixos,https://100.113.78.93";
      };
    };
  };

  # The logind ACL on /dev/uinput goes to the active seat0 session, which is the SDDM greeter next to the headless
  # session, so Sunshine's virtual keyboard and mouse need the group.
  users.users.mathew.extraGroups = [ "uinput" ];

  networking.nftables.enable = true;

  systemd = {
    # The SDDM greeter session also reaches graphical-session.target; a Sunshine started as sddm holds the ports.
    user.services.sunshine = {
      unitConfig.ConditionUser = "mathew";
      # Capture starts after the lock (hyprlock-initial.service, Home Manager) in a remote session. Ordering only: a failed
      # or skipped unit does not hold Sunshine back.
      after = [ "hyprlock-initial.service" ];
    };
  };
}
