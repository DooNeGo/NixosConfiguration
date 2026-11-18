{ lib, pkgs, ... }:
{
  services.hyprpaper.enable = true;

  # Type=simple is active before hyprpaper creates its socket; the unit stays activating until ExecStartPost sees
  # it, so units ordered After= hyprpaper can use the socket.
  systemd.user.services.hyprpaper.Service = {
    # A socket left by a crashed hyprpaper must not satisfy the wait below.
    ExecStartPre = lib.getExe (
      pkgs.writeShellApplication {
        name = "remove-stale-hyprpaper-socket";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          rm -f "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprpaper.sock"
        '';
      }
    );
    ExecStartPost = lib.getExe (
      pkgs.writeShellApplication {
        name = "wait-hyprpaper-socket";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprpaper.sock"
          for _ in $(seq 100); do
            [ -S "$sock" ] && exit 0
            sleep 0.1
          done
          echo "hyprpaper socket $sock did not appear in 10 s (renamed after an update?)" >&2
          exit 1
        '';
      }
    );
    TimeoutStartSec = 15;
  };
}
