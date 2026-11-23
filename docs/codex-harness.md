# Codex harness

Start Codex from this repository. `AGENTS.md` describes the flake topology, verification commands, and when to read the topic instructions in `.codex/instructions/`. Project skills live in `.agents/skills/`.

The workspace config disables the Sites, Pages, and Work Pets skills by name. These settings apply when Codex loads this repository's configuration.

The workspace also disables the corresponding app connectors by ID. Hosted ChatGPT sessions can supply their own app tools.

## Hooks

For a trusted workspace, Codex reads `.codex/hooks.json`. Review the hooks in `/hooks` when starting a new session or after their definitions change.

- Before a shell command, the Git guard checks for operations reserved for the owner. The owner can run authorized operations from their terminal. Force pushes are prohibited by the guard.
- After a Codex patch, the patch hook runs `git add -N` for new, non-ignored files and `nixfmt` on touched Nix files other than generated hardware configurations. For shell-generated changes, perform those operations explicitly as needed.
- At the end of a turn with Nix, shell or box edits, the stop hook runs `scripts/lint.sh`. On failure it surfaces the output and allows one continuation.

Check hook changes with shellcheck and representative JSON payloads. For a live check, start a fresh session from the repository root, confirm the hooks in `/hooks`, and test patch handling against a disposable worktree.

## NixOS MCP

`home-config/openclaw-npm` installs `mcp-nixos` from its pinned Nixpkgs. The owner activates the Home Manager generation with:

```sh
home-manager switch --flake ./home-config/openclaw-npm#openclaw-npm
```

Start a fresh Codex session in the trusted workspace with the Home Manager profile on `PATH`. Confirm that `nixos` appears in `/mcp` and look up an option such as `services.openssh.enable`. The server uses public indexes. Check the chosen package or option against the relevant flake's locked dependencies and local overlays before making a change.
