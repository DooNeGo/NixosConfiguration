# Nix files

- Reach every flake input through `inputs`; take stable-channel packages from the overlay in `lib/pkgs.nix` (`pkgs.stable.<x>`), not from an extra `pkgs-stable` argument.
- Group repeated attribute paths into one set (statix `repeated_keys` is on, and the owner prefers grouped keys).
- The Codex patch hook formats edited `.nix` files. Run `nixfmt` explicitly for shell-generated changes.
- Shared modules: one in `home-config/shared/` that `DooNeGo` imports must also evaluate on darwin (guard Linux-only parts with `pkgs.stdenv.hostPlatform.isLinux`). `system-config/shared/` holds modules for both NixOS and nix-darwin: use only options both module systems have (`environment.*`, `programs.tmux.extraConfig`), or the darwin host cannot import them.
- Layering: `environment.systemPackages` and `systemd.tmpfiles.rules` are system-level only (not valid in Home Manager). A tmpfiles rule must create the full directory chain.
- Report a failing service through `system-config/nixos/failure-notify.nix`: add it to `services.failure-notify.units`, or call `failure-notify report` from a handler. It already delivers to shells and desktop sessions without root touching a session bus, so a unit needs no `OnFailure` or `notify-send` of its own.
- Keep logic out of `.nix` files: a shell script over ~20 lines, or with functions, option parsing, `flock` or `trap`, goes into a `.sh` (zsh: `.zsh`) next to its module, read with `builtins.readFile`; values from Nix reach it through `runtimeEnv`. A short, plain script may stay inline. Writing such a file: `.codex/instructions/shell-tools.md`.
- A script run by a unit must not call `systemctl` for a unit that is ordered after it without `--no-block`: the script waits for that unit's job, the job waits for the script, and the start (and any `switch`) hangs.
- `Type=simple` counts as active before the service is ready; for `After=` to mean ready, hold the unit in activating with an `ExecStartPost` that waits for the socket.
- `deadnix --edit` can break flake `outputs`: a closed pattern like `{ self, nixpkgs }:` must keep `...` after `self` is dropped. Rebuild or evaluate every flake after an auto-fix.
- Use the workspace `nixos` MCP server to find candidate packages and options in upstream indexes. Verify them against the relevant flake's pinned inputs.
- Look an option up before using or changing it. The local NixOS manual describes every option of the built release: `grep -o '/nix/store[^ ]*index.html' $(which nixos-help)` gives the path, and `options.html` beside it has an `opt-<option path>` anchor (strip tags with `sed 's/<[^>]*>//g'`).
- The manual does not say what a module enables or for whom (`services.sunshine.autoStart` starts the unit for every user), so also read the module: `nix eval --raw ./system-config/nixos#nixosConfigurations.nixos.pkgs.path` is the nixpkgs tree, the file is the `Declared by` path under `nixos/modules/`.
- `system-config/nixos/sing-box/kinds/*.nix` are plain functions called by `sing-box.nix`, not modules: do not add them to `imports`; the shape is in `docs/sing-box-tunnels.md`.
