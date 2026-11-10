{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.failure-notify;
  stateDir = "/var/lib/failure-notify";

  command = pkgs.writeShellApplication {
    name = "failure-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    runtimeEnv = {
      FAILURE_NOTIFY_STATE_DIR = stateDir;
      FAILURE_NOTIFY_RENOTIFY_SEC = toString cfg.renotifySec;
      FAILURE_NOTIFY_SINKS = lib.concatStringsSep "\n" (map toString cfg.sinks);
    };
    text = builtins.readFile ./failure-notify/failure-notify.sh;
  };

  failureNotify = pkgs.symlinkJoin {
    name = "failure-notify";
    paths = [
      command
      (pkgs.runCommand "failure-notify-zsh-completion" { } ''
        install -Dm644 ${./failure-notify/_failure-notify} $out/share/zsh/site-functions/_failure-notify
      '')
    ];
    meta.mainProgram = "failure-notify";
  };
in
{
  options.services.failure-notify = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "btrbk-home" ];
      description = "Services whose failure is recorded; the record is removed by their next successful run.";
    };
    sinks = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Executables called for a new record with FAILED_UNIT, FAILED_MESSAGE and FAILED_TIME (epoch) in the
        environment, as root. The core does not know where they deliver. Desktop notifications do not need one:
        a user service in each graphical session watches the records itself.
      '';
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The failure-notify command, for other modules that report through it.";
    };
    renotifySec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 86400;
      description = "The sinks are called again for a problem that is still reported after this many seconds.";
    };
  };

  config = {
    services.failure-notify.package = failureNotify;

    environment.systemPackages = [ failureNotify ];

    systemd = {
      tmpfiles.rules = [ "d ${stateDir} 0755 root root -" ];

      services = {
        "failure-notify@" = {
          description = "Record the failure of %i";
          serviceConfig.Type = "oneshot";
          path = [ config.systemd.package ];
          scriptArgs = "%i";
          script = ''
            # The unit's own last output, not systemd's "Failed to start" line that follows it.
            invocation=$(systemctl show -p InvocationID --value "$1")
            last=$(journalctl -n 1 -o cat --no-pager _SYSTEMD_UNIT="$1" _SYSTEMD_INVOCATION_ID="$invocation" 2>/dev/null || true)
            result=$(systemctl show -p Result --value "$1")
            exec ${lib.getExe failureNotify} report "$1" "''${last:-failed ($result)}; see: journalctl -u $1"
          '';
        };
      }
      // lib.genAttrs cfg.units (_: {
        onFailure = [ "failure-notify@%n.service" ];
        # "+": the record directory is root's, the unit may run as another user.
        serviceConfig.ExecStartPost = "+${lib.getExe failureNotify} clear %n";
      });
    };

    # Each graphical session notifies itself from the world-readable records (also those written before it started),
    # so nothing privileged has to reach into a user's session bus.
    systemd.user = {
      paths.failure-notify = {
        wantedBy = [ "graphical-session.target" ];
        pathConfig.PathChanged = stateDir;
      };
      services = {
        # The runtime directory outlives a graphical session (an ssh login keeps it), the notifications do not.
        failure-notify-session = {
          description = "Forget which failure records this session has shown";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/rm -f %t/failure-notify-seen";
          };
        };
        failure-notify = {
          description = "Desktop notifications for failure-notify records";
          wantedBy = [ "graphical-session.target" ];
          after = [
            "graphical-session.target"
            "failure-notify-session.service"
          ];
          # Started by the path unit on every change of the directory, which must never trip the start limit.
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.libnotify
          ];
          script = ''
            seen=$XDG_RUNTIME_DIR/failure-notify-seen
            touch "$seen"
            now=$(date +%s)
            for f in ${stateDir}/*; do
              [[ -f $f ]] || continue
              { read -r since && read -r expires && read -r _ && IFS= read -r message; } <"$f" || continue
              if ((expires != 0 && expires <= now)); then continue; fi
              key="''${f##*/} $since"
              if grep -qxF -- "$key" "$seen"; then continue; fi
              # The notification daemon may still be starting right after login.
              for attempt in 1 2 3 4 5 6; do
                if notify-send -u critical -a failure-notify "Failure: ''${f##*/}" "$message"; then
                  echo "$key" >>"$seen"
                  break
                fi
                if ((attempt < 6)); then sleep 5; fi
              done
            done
          '';
        };
      };
    };

    programs.zsh.interactiveShellInit =
      "_failure_notify_dir=${stateDir}\n" + builtins.readFile ./failure-notify/hook.zsh;
  };
}
