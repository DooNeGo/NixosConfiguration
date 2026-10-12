# Systemd unit traps: option coercion, credentials, nix-daemon proxy

## Step 2b — NixOS systemd option type coercion (string-typed, not Nix-typed)

NixOS systemd options are typed as strings. Nix values that look valid fail the
full build with a terse `cannot coerce a …` error that names the unit but not the
line. Three shapes of this bug:

- Boolean options like `RemainAfterExit`/`NoNewPrivileges`: `RemainAfterExit =
  true` fails (`cannot coerce a Boolean to a string: true`); write `"yes"`.
  (`NoNewPrivileges` coerces a bool fine; `RemainAfterExit` does not, because the
  module types them differently.)
- `Environment`: an attrset inside `serviceConfig.Environment = { K = v; }` is
  not coerced (`cannot coerce a set to a string`). Put per-service env in the
  module's TOP-LEVEL `environment = { K = v; }` of the `systemd.services.<name>`
  entry; that renders `Environment="K=v"` lines.
- Interpolating an int into a string (e.g. `description = "… ${lib.length x} …"`)
  fails (`cannot coerce an integer to a string`); wrap it in `toString`.

These surface only at the full `system.build.toplevel` build, because option
warnings and coercion checks run late. A green `nix eval` of a single unit attrset
does not clear them: after touching hand-rolled units, always run the toplevel
build before declaring done. `systemd-analyze verify` on a rendered unit checks
syntax only, not NixOS coercion.

## Step 3 — systemd credentials land under the FULL unit name

`LoadCredential` mounts secrets at `/run/credentials/<unit-name-with-suffix>/`.
The `.service` suffix is kept, never stripped (`systemd.exec` CREDENTIALS_DIRECTORY
semantics). A generator that reads `/run/credentials/sing-box/vless-key` instead
of `/run/credentials/sing-box.service/vless-key` fails every start and loops.
In units prefer `os.environ.get("CREDENTIALS_DIRECTORY")` plus the basename over a
hardcoded path; when hardcoding, include the `.service` suffix. Diagnostic
shortcut: while `ExecStartPre` runs, poll `ls /run/credentials`. A readable catalog
proves ENOENT is a wrong path, not a permission error.

When the system journal is unreadable (openclaw is not in `adm` or
`systemd-journal`, and `sudo -n` needs a password; do not collect passwords in
chat), triage by reproducing the failing `ExecStartPre` manually with the unit's
`Environment` values (from `systemctl cat <unit>`). Hand the owner a one-line
`sudo journalctl -u <unit> -n 40 --no-pager -o cat` to paste. Two caveats:

- A manual run fails at `/run/credentials/<unit>/…` with ENOENT by construction,
  because LoadCredential exists only inside the service namespace. That is not
  the in-service root cause.
- An instant `socket.gaierror: Name or service not known` inside the service,
  while the interactive shell resolves fine, usually means sandbox-scoped DNS or
  an ISP-filtered host, not broken networking.

## Step 4b — proxy for the nix daemon (fetches and substitutions)

There is NO `proxy` option in `nix.conf` (absent from `nix config show`). Fetches
run inside the `nix-daemon` service, so user-shell proxy env never reaches them.
Set it through the NixOS module:

```nix
systemd.services.nix-daemon.environment = {
  HTTP_PROXY  = "http://127.0.0.1:2080";
  HTTPS_PROXY = "http://127.0.0.1:2080";
};
```

Standard fetchers (`fetchurl`, `fetchGit`) declare proxy vars in
`impureEnvVars`, so daemon env propagates into builders automatically; one place
is enough. Region-blocked fetches (`curl: (22) The requested URL returned error:
451`, e.g. download.jetbrains.com from Minsk) fail with exit 1 in the fetch
derivation even though a proxied shell download works. That asymmetry means the
daemon lacks the proxy env, not that the host is unreachable.

Chicken-and-egg: the daemon proxy takes effect only AFTER a switch, but the
rebuild can itself fail on the blocked fetch. Escape by bootstrapping the env
through a manual drop-in the owner runs (needs sudo), then switch:

```sh
sudo mkdir -p /etc/systemd/system/nix-daemon.service.d
printf '[Service]\nEnvironment=HTTP_PROXY=http://127.0.0.1:2080\nEnvironment=HTTPS_PROXY=http://127.0.0.1:2080\n' \
  | sudo tee /etc/systemd/system/nix-daemon.service.d/proxy.conf
sudo systemctl daemon-reload && sudo systemctl restart nix-daemon
sudo nixos-rebuild switch --flake /home/shared/NixosConfiguration#nixos
# after a successful switch the repo drop-in replaces the manual one:
sudo rm /etc/systemd/system/nix-daemon.service.d/proxy.conf && sudo systemctl daemon-reload
```

Completion check: `systemctl show nix-daemon -p Environment` lists both
variables, and the previously blocked fetch derivation builds.
