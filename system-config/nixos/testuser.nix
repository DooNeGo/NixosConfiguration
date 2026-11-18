# Test account and its headless Hyprland session: the agent applies any Home Manager configuration here without touching mathew's stream.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.testuser;

  # Conflicts= would stop the owner's stream before this check runs, so the session refuses instead.
  refuseWhileOwnerSession = pkgs.writeShellScript "refuse-while-owner-session" ''
    if ${config.systemd.package}/bin/systemctl is-active --quiet hyprland-headless-mathew.service steam-bigpicture-mathew.service; then
      echo "mathew's stream or Steam session is running; stop it first" >&2
      exit 1
    fi
  '';
in
{
  options.testuser.enable = lib.mkEnableOption "the testuser user and its headless session";

  config = lib.mkIf cfg.enable {
    users.users.testuser = {
      isNormalUser = true;
      shell = pkgs.zsh;
      # No password: ssh by key only; the agent unlocks hyprlock with SIGUSR1.
      extraGroups = [ "video" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdCqusk57b17VBbMOBjj3KXm4pzcnc0mmp8XwDwlG8H openclaw-npm@nixos"
      ];
    };

    # openclaw-npm may start and stop the test session, and only it.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "hyprland-headless-testuser.service" &&
            ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
            subject.user == "openclaw-npm") {
          return polkit.Result.YES;
        }
      });
    '';

    security.pam.services.hyprland-headless-testuser.startSession = true;

    systemd.services.hyprland-headless-testuser = {
      description = "Hyprland (UWSM, headless backend) session for testuser, started on demand";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
        "display-manager.service"
      ];
      wants = [
        "dbus.socket"
        "systemd-logind.service"
      ];
      requires = [ "display-manager.service" ];
      environment = {
        LIBSEAT_BACKEND = "noop";
        AQ_NO_KMS_REQUIREMENT = "1";
        HYPRLAND_START_LOCKED = "1";
      };
      serviceConfig = {
        ExecStart = "${pkgs.coreutils}/bin/env XDG_SEAT=seat0 ${config.programs.uwsm.package}/bin/uwsm start -e -D Hyprland hyprland.desktop";
        ExecStartPre = refuseWhileOwnerSession;
        User = "testuser";
        Restart = "no";
        StandardOutput = "journal";
        StandardError = "journal";
        PAMName = "hyprland-headless-testuser";
      };
    };

    # Starting the owner's stream stops the test session, not the other way round.
    systemd.services = {
      hyprland-headless-mathew.conflicts = [ "hyprland-headless-testuser.service" ];
      steam-bigpicture-mathew.conflicts = [ "hyprland-headless-testuser.service" ];
    };
  };
}
