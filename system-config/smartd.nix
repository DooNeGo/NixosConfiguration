{
  config,
  lib,
  pkgs,
  ...
}:
let
  checkIntervalSec = 1800; # smartd's own default, stated here because the record lifetime is derived from it
  repeatSec = 86400; # -M daily

  # smartd repeats a warning daily while the problem lasts and never reports a recovery, so the record expires when
  # one repeat (plus one check of slack) was missed.
  handler = pkgs.writeShellScript "smartd-failure-notify" ''
    exec ${lib.getExe config.services.failure-notify.package} report --ttl ${toString (repeatSec + 2 * checkIntervalSec)} \
      "smartd-''${SMARTD_DEVICE##*/}-$SMARTD_FAILTYPE" "$SMARTD_MESSAGE"
  '';
in
{
  services.smartd = {
    enable = true;
    extraOptions = [ "--interval=${toString checkIntervalSec}" ];
    # The module's own channels are off (wall never reaches the desktop terminals and interrupts ssh sessions); its
    # systembus-notify switch alone installs no handler in this nixpkgs, so the handler is set here.
    notifications = {
      wall.enable = false;
      x11.enable = false;
    };
    defaults.monitored = "-a -m <nomailer> -M exec ${handler} -M daily";
  };
}
