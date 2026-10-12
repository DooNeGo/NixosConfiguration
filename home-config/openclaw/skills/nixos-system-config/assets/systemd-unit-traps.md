# Systemd unit traps: option coercion, credentials, nix-daemon proxy

Moved verbatim from `nixos-system-config/SKILL.md` on 2026-10-08 (SKILL.md
exceeded the 10,000-char authoring limit). Section headings unchanged;
SKILL.md keeps Steps 1, 2, 4, 5 and points here.

## Step 2b — NixOS systemd option type coercion (string-typed, not Nix-typed)

NixOS systemd options are typed as strings; Nix values that LOOK valid fail the
full build with a terse `cannot coerce a …` error that names the unit but not
the line. Verified 2026-10-05 (three distinct bugs, three rebuilds to find):

- Boolean options like `RemainAfterExit`/`NoNewPrivileges`: `RemainAfterExit =
  true` fails (`cannot coerce a Boolean to a string: true`) — write `"yes"`.
  (`NoNewPrivileges` coerces a bool fine; `RemainAfterExit` does not — the
  module types them differently.)
- `Environment`: an attrset inside `serviceConfig.Environment = { K = v; }` is
  not coerced (`cannot coerce a set to a string: { K = «thunk»; … }`). Put
  per-service env in the module's TOP-LEVEL `environment = { K = v; }` of the
  `systemd.services.<name>` entry — that renders `Environment="K=v"` lines.
- Interpolating an int into a string (e.g. `description = "… ${lib.length x}
  …"`) fails (`cannot coerce an integer to a string: N`) — wrap in `toString`.

These surface only at the full `system.build.toplevel` build (option
`warnings`/coercion checks run late), so a green `nix eval` of a single unit
attrset does not clear them: after touching hand-rolled units, always run the
toplevel build before declaring done. `systemd-analyze verify` on a rendered
unit catches only syntax, not NixOS coercion.

## Step 3 — systemd credentials land under the FULL unit name

`LoadCredential` mounts secrets at
`/run/credentials/<unit-name-with-suffix>/` — the `.service` suffix is kept,
never stripped (`systemd.exec` CREDENTIALS_DIRECTORY semantics, verified
2026-10-02: a generator reading `/run/credentials/sing-box/vless-key` instead
of `/run/credentials/sing-box.service/vless-key` failed every start, ~10k
restart loops). In units prefer `os.environ.get("CREDENTIALS_DIRECTORY")` +
basename over a hardcoded path; when hardcoding, include the `.service`
suffix. Diagnostic shortcut: while `ExecStartPre` runs, poll
`ls /run/credentials` — a readable catalog proves ENOENT is a wrong path, not
a permission error.

When the system journal is unreadable (openclaw is not in `adm`/`systemd-journal`
and `sudo -n` needs a password — do not collect passwords in chat), triage by
reproducing the failing `ExecStartPre` manually with the unit's `Environment`
values (from `systemctl cat <unit>`), and hand the user a one-line
`sudo journalctl -u <unit> -n 40 --no-pager -o cat` to paste. Two caveats from
2026-10-04 on sing-box: a manual run fails at `/run/credentials/<unit>/…` with
ENOENT *by construction* (LoadCredential exists only inside the service
namespace) — that is not the in-service root cause; and an instant
`socket.gaierror: Name or service not known` inside the service while the
interactive shell resolves fine usually means sandbox-scoped DNS or an
ISP-filtered host, not broken networking.


## Step 4b — proxy for the nix daemon (fetches and substitutions)

There is NO `proxy` option in `nix.conf` (verified: absent from `nix config
show`). Fetches run inside the `nix-daemon` service, so user-shell proxy env
never reaches them. Set it through the NixOS module:

```nix
systemd.services.nix-daemon.environment = {
  HTTP_PROXY  = "http://127.0.0.1:2080";
  HTTPS_PROXY = "http://127.0.0.1:2080";
};
```

Standard fetchers (`fetchurl`, `fetchGit`) declare proxy vars in
`impureEnvVars`, so daemon env propagates into builders automatically — one
place is enough. Region-blocked fetches (`curl: (22) The requested URL
returned error: 451`, e.g. download.jetbrains.com from Minsk) fail with exit
1 in the fetch drv even though a proxied shell download works — that
asymmetry means the daemon lacks the proxy env, not that the host is
unreachable.

Chicken-and-egg: the daemon proxy only takes effect AFTER a switch, but the
rebuild can itself fail on the blocked fetch. Escape by bootstrapping the
env through a manual drop-in the USER runs (needs sudo), then switch:

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
variables, and the previously-451 fetch drv builds.

