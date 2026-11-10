{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.failure-notify;
  stateDir = "/var/lib/failure-notify";

  helpText = pkgs.writeText "failure-notify-help" ''
    Usage: failure-notify report [--ttl SECONDS] [--] ID MESSAGE...
           failure-notify clear ID
           failure-notify list
           failure-notify -h | --help

    Keep a record of a failure that shells and desktop sessions then show to the users.

    Commands:
      report   Create or renew the record ID. A repeated report keeps the time of the first one and calls the
               sinks again only after ${toString cfg.renotifySec} seconds. Needs write access to the record directory.
      clear    Remove the record ID. Needs write access to the record directory.
      list     Print the open records, one per line: time, ID, message.

    Options:
      --ttl SECONDS  Drop the record after SECONDS (default: keep it until it is cleared).
      -h, --help     Show this help and exit.

    Environment:
      FAILURE_NOTIFY_DIR  Record directory (default: ${stateDir}).

    Exit status: 0 on success, 1 on a runtime error (e.g. the directory cannot be locked), 2 on a usage error.

    Examples:
      failure-notify report backup-disk "backup disk is not connected"
      failure-notify report --ttl 3600 smartd-sda "SMART: reallocated sectors"
      failure-notify clear backup-disk
  '';

  # One file per open problem: first seen, expiry (0 = never), last sink call, message; one value per line.
  # A repeated report of the same id keeps "first seen", so shells show an incident once, and calls the sinks again
  # only after renotifySec, so a unit that fails every 10 minutes does not flood them.
  command = pkgs.writeShellApplication {
    name = "failure-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      dir=''${FAILURE_NOTIFY_DIR:-${stateDir}}
      sinks=(${lib.escapeShellArgs cfg.sinks})

      help() { cat ${helpText}; }
      # Usage errors go to stderr with a pointer to the help, not the whole help.
      usage() {
        [[ $# -eq 0 ]] || echo "failure-notify: $*" >&2
        echo "Try 'failure-notify --help' for more information." >&2
        exit 2
      }
      is_help() { [[ ''${1:-} == -h || ''${1:-} == --help ]]; }
      # A leading dot would hide the record from the globs, ".." would escape the directory.
      sanitize() {
        local id
        id=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.@:-' '_')
        [[ -n $id ]] || usage
        printf '%s' "''${id/#./_}"
      }
      # Only the changes of the directory are serialised, so that a pruning cannot delete a record that a report has
      # just renewed. Fails quietly when the lock file cannot be opened (list as an ordinary user).
      lock() {
        { exec 9>"$dir/.lock"; } 2>/dev/null && flock -w 30 9
      }
      unlock() {
        flock -u 9
      }
      prune() {
        local f expires now
        now=$(date +%s)
        for f in "$dir"/*; do
          [[ -f $f ]] || continue
          { read -r _ && read -r expires; } <"$f" || continue
          if ((expires != 0 && expires <= now)); then
            lock || return 0
            # The record may have been renewed while waiting for the lock.
            { read -r _ && read -r expires; } <"$f" && ((expires != 0 && expires <= now)) && rm -f "$f"
            unlock
          fi
        done
      }

      cmd=''${1:-}
      [[ $# -gt 0 ]] && shift
      case $cmd in
        report)
          ttl=0
          while [[ ''${1:-} == -* ]]; do
            case $1 in
              -h | --help)
                help
                exit 0
                ;;
              --ttl)
                [[ $# -ge 2 ]] || usage "option '--ttl' requires an argument"
                ttl=$2
                shift 2
                ;;
              --ttl=*)
                ttl=''${1#--ttl=}
                shift
                ;;
              --)
                shift
                break
                ;;
              *) usage "unknown option '$1'" ;;
            esac
          done
          [[ $ttl =~ ^[0-9]+$ ]] || usage "--ttl needs a number of seconds, got '$ttl'"
          [[ $# -ge 2 ]] || usage "report needs an ID and a message"
          id=$(sanitize "$1")
          shift
          # Shown raw in terminals: no control characters.
          message=$(printf '%s' "$*" | tr '\n\t' '  ' | tr -d '\000-\037\177')
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
          lock || {
            echo "failure-notify: could not lock $dir" >&2
            exit 1
          }
          printf '%s\n%s\n%s\n%s\n' "$since" "$expires" "$notified" "$message" >"$dir/.tmp.$$"
          chmod 644 "$dir/.tmp.$$"
          mv "$dir/.tmp.$$" "$dir/$id"
          unlock
          if ((notify)); then
            for sink in "''${sinks[@]}"; do
              FAILED_UNIT=$id FAILED_MESSAGE=$message FAILED_TIME=$since timeout 10 "$sink" ||
                echo "failure-notify: sink $sink failed" >&2
            done
          fi
          ;;
        clear)
          if is_help "$@"; then
            help
            exit 0
          fi
          [[ $# -eq 1 ]] || usage "clear needs exactly one ID"
          id=$(sanitize "$1")
          lock || {
            echo "failure-notify: could not lock $dir" >&2
            exit 1
          }
          rm -f "$dir/$id"
          ;;
        list)
          if is_help "$@"; then
            help
            exit 0
          fi
          [[ $# -eq 0 ]] || usage "list takes no arguments"
          prune 2>/dev/null || true
          for f in "$dir"/*; do
            [[ -f $f ]] || continue
            { read -r since && read -r _ && read -r _ && IFS= read -r message; } <"$f" || continue
            printf '%s  %s  %s\n' "$(date -d "@$since" '+%F %R')" "''${f##*/}" "$message"
          done
          ;;
        -h | --help)
          help
          ;;
        "") usage "missing command" ;;
        *) usage "unknown command '$cmd'" ;;
      esac
    '';
  };

  # The completion rides in the same package, so every profile that installs the command gets it.
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

    # Desktop notifications come from the session itself, so nothing privileged has to reach into a user's session
    # bus: the records are world-readable and each graphical session notifies about the ones it has not shown yet,
    # including those that were written before it started.
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
