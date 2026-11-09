{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.failure-notify;
  stateDir = "/var/lib/failure-notify";

  # One file per open problem: first seen, expiry (0 = never), last sink call, message; one value per line.
  # A repeated report of the same id keeps "first seen", so shells show an incident once, and calls the sinks again
  # only after renotifySec, so a unit that fails every 10 minutes does not flood them.
  failureNotify = pkgs.writeShellApplication {
    name = "failure-notify";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      dir=''${FAILURE_NOTIFY_DIR:-${stateDir}}
      sinks=(${lib.escapeShellArgs cfg.sinks})

      usage() {
        echo "usage: failure-notify report [--ttl SECONDS] <id> <message...> | clear <id> | list" >&2
        exit 2
      }
      sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.@:-' '_'; }
      prune() {
        local f expires now
        now=$(date +%s)
        for f in "$dir"/*; do
          [[ -f $f ]] || continue
          { read -r _ && read -r expires; } <"$f" || continue
          if ((expires != 0 && expires <= now)); then rm -f "$f"; fi
        done
      }

      cmd=''${1:-}
      [[ $# -gt 0 ]] && shift
      case $cmd in
        report)
          ttl=0
          if [[ ''${1:-} == --ttl ]]; then
            ttl=$2
            shift 2
          fi
          [[ $# -ge 2 ]] || usage
          id=$(sanitize "$1")
          shift
          message=$(printf '%s' "$*" | tr '\n' ' ')
          prune
          now=$(date +%s)
          since=$now
          notified=0
          if [[ -f $dir/$id ]]; then
            { read -r since && read -r _ && read -r notified; } <"$dir/$id" || true
          fi
          expires=0
          if ((ttl > 0)); then expires=$((now + ttl)); fi
          notify=0
          if ((now - notified >= ${toString cfg.renotifySec})); then
            notify=1
            notified=$now
          fi
          printf '%s\n%s\n%s\n%s\n' "$since" "$expires" "$notified" "$message" >"$dir/.tmp.$$"
          chmod 644 "$dir/.tmp.$$"
          mv "$dir/.tmp.$$" "$dir/$id"
          if ((notify)); then
            for sink in "''${sinks[@]}"; do
              FAILED_UNIT=$id FAILED_MESSAGE=$message FAILED_TIME=$since timeout 10 "$sink" ||
                echo "failure-notify: sink $sink failed" >&2
            done
          fi
          ;;
        clear)
          [[ $# -eq 1 ]] || usage
          rm -f "$dir/$(sanitize "$1")"
          ;;
        list)
          prune 2>/dev/null || true
          for f in "$dir"/*; do
            [[ -f $f ]] || continue
            { read -r since && read -r _ && read -r _ && read -r message; } <"$f" || continue
            printf '%s  %s  %s\n' "$(date -d "@$since" '+%F %R')" "''${f##*/}" "$message"
          done
          ;;
        *) usage ;;
      esac
    '';
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
            last=$(journalctl -u "$1" -n 1 -o cat --no-pager 2>/dev/null || true)
            exec ${lib.getExe failureNotify} report "$1" "''${last:-failed}; see: journalctl -u $1"
          '';
        };
      }
      // lib.genAttrs cfg.units (_: {
        onFailure = [ "failure-notify@%n.service" ];
        # "+": the record directory is root's, the unit may run as another user.
        serviceConfig.ExecStartPost = "+${lib.getExe failureNotify} clear %n";
      });
    };

    # Desktop notifications come from the session itself, so nothing privileged has to reach into a user's session
    # bus: the records are world-readable and each graphical session notifies about the ones it has not shown yet,
    # including those that were written before it started.
    systemd.user = {
      paths.failure-notify = {
        wantedBy = [ "graphical-session.target" ];
        pathConfig.PathChanged = stateDir;
      };
      services.failure-notify = {
        description = "Desktop notifications for failure-notify records";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        # Retried while the notification daemon is not up yet.
        unitConfig = {
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
        };
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = 15;
        };
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
            notify-send -u critical -a failure-notify "Failure: ''${f##*/}" "$message"
            echo "$key" >>"$seen"
          done
        '';
      };
    };

    # Open records are listed when a shell starts (not in every tmux pane) and a new one is printed before the next
    # prompt, once per shell. Only builtins: this runs before every prompt.
    programs.zsh.interactiveShellInit = ''
      zmodload zsh/datetime
      typeset -gA _failure_notify_seen
      _failure_notify_check() {
        local quiet=$1 f lines key stamp
        for f in ${stateDir}/*(N.); do
          lines=("''${(@f)$(<$f)}")
          (( lines[2] == 0 || lines[2] > EPOCHSECONDS )) || continue
          key="$f ''${lines[1]}"
          [[ -z ''${_failure_notify_seen[$key]} ]] || continue
          _failure_notify_seen[$key]=1
          [[ -z $quiet ]] || continue
          strftime -s stamp '%F %R' $lines[1]
          print -r -- $'\e[1;31m[failure]\e[0m '"''${f:t} since $stamp: $lines[4] (dismiss: sudo failure-notify clear ''${f:t})"
        done
      }
      _failure_notify_check ''${TMUX:+quiet}
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd _failure_notify_check
    '';
  };
}
