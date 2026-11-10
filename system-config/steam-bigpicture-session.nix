{ config, pkgs, ... }:
let
  gamescope = config.programs.gamescope.package;
  steam = config.programs.steam.package;
  # Output size of the headless gamescope = what Remote Play streams. Keep the aspect ratio of the client screen
  # (1680x1050 = 16:10), otherwise the client letterboxes the picture.
  width = 1680;
  height = 1050;
  refresh = 60;
  # The Home Manager cursor theme (rose-pine-hyprcursor, size 30) has no X11 cursors, so gamescope falls back to a
  # huge default one. Use a real XCursor theme at a normal size; exported after hm-session-vars to override it.
  cursorTheme = "Adwaita";
  cursorSize = 12;
in
{
  # gamescope with the headless backend: no DRM, no monitor, no tty and no Hyprland. Steam runs with -pipewire-dmabuf,
  # so Remote Play captures through gamescope's PipeWire stream and encodes with NVENC.
  security.pam.services.steam-bigpicture-mathew.startSession = true;

  systemd.services.steam-bigpicture-mathew = {
    description = "Steam Big Picture (headless gamescope) for mathew, started on demand";
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    # Both start a Steam client for the same user.
    conflicts = [ "hyprland-mathew.service" ];
    serviceConfig = {
      # zsh -c reads ~/.zshenv, where Home Manager sources hm-session-vars.sh (NVIDIA env), as in the UWSM session.
      ExecStart = ''
        ${pkgs.zsh}/bin/zsh -c 'export XCURSOR_THEME=${cursorTheme} XCURSOR_SIZE=${toString cursorSize} \
          XCURSOR_PATH=${pkgs.adwaita-icon-theme}/share/icons; \
          exec ${gamescope}/bin/gamescope --backend headless --steam \
          -W ${toString width} -H ${toString height} -r ${toString refresh} \
          -- ${steam}/bin/steam -tenfoot -pipewire-dmabuf'
      '';
      User = "mathew";
      PAMName = "steam-bigpicture-mathew";
      Restart = "no";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
