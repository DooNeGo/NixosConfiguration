# The first lock of a remotely started session: after the desktop has drawn, before Sunshine (system-config/nixos/
# remote-access.nix) starts capturing. How and why: docs/remote-access.md.
{ lib, pkgs, ... }:
let
  shell = [
    "hyprpaper.service"
    "random-wallpaper.service"
    "waybar.service"
  ];
  # The compositor's own build: a hyprctl from another nixpkgs can disagree with the running Hyprland.
  hyprctl = "/run/current-system/sw/bin/hyprctl";

  waitDesktop = lib.getExe (
    pkgs.writeShellApplication {
      name = "wait-desktop-drawn";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
        pkgs.systemd
      ];
      runtimeEnv.HYPRCTL = hyprctl;
      text = ''
        # random-wallpaper runs Before= waybar, so an active waybar means the wallpaper is already set.
        ready() {
          systemctl --user is-active --quiet waybar.service &&
            "$HYPRCTL" layers -j | jq -e '[.[] | .levels[][]?.namespace] | index("hyprpaper") and index("waybar")' >/dev/null
        }
        for _ in $(seq 300); do
          ready && break
          sleep 0.1
        done
        # After 30 s lock anyway: the session must not stay open because the desktop did not come up.
      '';
    }
  );

  hyprlockReady = pkgs.hyprlock.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.systemd ];
    postPatch = (old.postPatch or "") + ''
            substituteInPlace src/core/hyprlock.cpp \
              --replace-fail '#include "hyprlock.hpp"' '#include "hyprlock.hpp"
      #include <systemd/sd-daemon.h>' \
              --replace-fail 'm_sLockState.locked = true;' 'm_sLockState.locked = true; sd_notify(0, "READY=1");'
            substituteInPlace CMakeLists.txt \
              --replace-fail 'target_link_libraries(hyprlock PRIVATE ' 'target_link_libraries(hyprlock PRIVATE systemd '
    '';
  });

in
{
  systemd.user.services.hyprlock-initial = {
    Unit = {
      Description = "Lock the remotely started session once the desktop has drawn";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ] ++ shell;
      Wants = shell;
      # A login at SDDM does not set it and gets no lock.
      ConditionEnvironment = "HYPRLAND_START_LOCKED";
      # A restart on switch would kill hyprlock under the lock.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      ExecStartPre = waitDesktop;
      Type = "notify";
      NotifyAccess = "main";
      TimeoutStartSec = 45;
      ExecStart = "${hyprlockReady}/bin/hyprlock";
      # Exit 0 after an unlock does not restart it; a crash does, and the new hyprlock takes over the lock.
      Restart = "on-failure";
      RestartMode = "direct";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
