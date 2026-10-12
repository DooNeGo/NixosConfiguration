# Remote NixOS host: tool not on PATH

Trigger: a command such as `python3` fails with "command not found" on a remote NixOS host (ai-server, repo `/home/admin/configuration`) although the tool exists there.

- Non-interactive SSH shells skip the interactive profile, so PATH may miss Nix profile dirs. Do not chase rc files.
- Find the tool's store env: `ls /nix/store | grep -E '<name>.*python3'`. Prefer an `-env` variant when the needed dependencies exist only in that env. Invoke the full store path.
- Check what the env ships: `ls /nix/store/<env>/lib/python3.*/site-packages/ | grep -i <dep>`.
- Service-side discovery: `systemctl cat <unit>` shows the ExecStart with the exact interpreter the running service uses; copy it verbatim.

Completion check: the remote command runs via the full store path, and that path is reused for the rest of the session.
