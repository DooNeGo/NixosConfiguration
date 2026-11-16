# Rider Remote Development

The backend runs on `openclaw-npm` (Rider from `overlays/rider.nix`), the client is Gateway (`mathew`, `DooNeGo`). Both come from the same pin and must be the same release.

## How Gateway finds the backend

- `programs.jetbrains-remote` (`home-config/shared/rider.nix`) runs `<ide>/bin/<mainProgram>-remote-dev-server registerBackendLocationForGateway` on activation. That puts a symlink to the IDE root into `~/.cache/JetBrains/RemoteDev/userProvidedDist/`, and Gateway starts `bin/remote-dev-server.sh` from there.
- The package in `ides` therefore has to be `pkgs.jetbrains.rider`: the `riderFHS` wrapper has only `bin/rider`, so the activation fails on the missing `rider-remote-dev-server`, and the FHS root is not an IDE root.
- When Gateway offers to download an IDE instead of using the registered one, it unpacks a plain JetBrains tarball into `~/.local/share/JetBrains/Toolbox/apps/`. That copy has no nix wrapping; its `Rider.BackendHost` (self-contained .NET) exits with code 134 and "Couldn't find a valid ICU package". Pick the registered path (`/nix/store/…-rider-<version>/rider`) and delete the Toolbox copy and its symlink in `userProvidedDist`.

## Where the logs are

- Backend, on the host: `~/.cache/JetBrains/Rider<version>/log/` (`backend.*-err.log` holds the host process error, `idea.log` the IDE).
- Running sessions: `~/.cache/JetBrains/RemoteDev/recent/` (`idePath` says which IDE was started; a Toolbox path means the download above).
- Connections: `journalctl -u sshd`. An accepted login with no new Rider log means the client stopped before starting the IDE.
- Client, on the Mac: `~/Library/Logs/JetBrains/JetBrainsGateway<version>/idea.log`; the "error in the connection provider" message comes from there.
