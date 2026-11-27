# Codex harness

Start Codex from this repository. `AGENTS.md` describes the flake topology, verification commands, and when to read the topic instructions in `.codex/instructions/`. Project skills live in `.agents/skills/`.

The workspace config disables the Sites, Pages, and Work Pets skills by name. These settings apply when Codex loads this repository's configuration.

The workspace also disables the corresponding app connectors by ID. Hosted ChatGPT sessions can supply their own app tools.

## Hooks

For a trusted workspace, Codex reads `.codex/hooks.json`. Review the hooks in `/hooks` when starting a new session or after their definitions change.

- Before a shell command, the Git guard checks protected operations. Merging into `main` uses the flow below. The owner runs other protected operations from their terminal. Force pushes are prohibited.
- After a Codex patch, the patch hook runs `git add -N` for new, non-ignored files and `nixfmt` on touched Nix files other than generated hardware configurations. For shell-generated changes, perform those operations explicitly as needed.
- At the end of a turn with Nix, shell or box edits, the stop hook runs `scripts/lint.sh`. On failure it surfaces the output and allows one continuation.

Check hook changes with shellcheck and representative JSON payloads. For a live check, start a fresh session from the repository root, confirm the hooks in `/hooks`, and test patch handling against a disposable worktree.

### Merging into main

The agent prepares and reviews the branch, then asks for explicit consent in chat if the owner has yet to give it. "Сливай" is enough when the branch is clear. From the repository root, the agent submits a standalone shell call with escalated approval. Use the first form when the branch has one commit outside `main` and the second when it has two or more.

```sh
bash .codex/hooks/merge-main.sh --ff-only <branch> <expected-main> <reviewed-tip>
bash .codex/hooks/merge-main.sh --no-ff <branch> <expected-main> <reviewed-tip>
```

The owner names a local branch. The agent supplies the two commit IDs from preflight and review. The project rule sends both forms to Auto-review. After that approval, the script checks the branch and commit count again, then passes the reviewed commit to Git. If the branch moved, review the changes and resubmit the command. Git can only merge the reviewed commit even if the branch moves after the script's check.

The shell hook blocks direct `git merge` calls on `main`. Run direct merges on feature branches as standalone shell calls. Run `bash .codex/hooks/test-merge-main.sh` to test the guarded merge in a disposable repository. Start a new Codex session from the trusted repository with interactive approvals and Auto-review enabled to load the command rule.

## NixOS MCP

`home-config/openclaw-npm` installs `mcp-nixos` from its pinned Nixpkgs. The owner activates the Home Manager generation with:

```sh
home-manager switch --flake ./home-config/openclaw-npm#openclaw-npm
```

Start a fresh Codex session in the trusted workspace with the Home Manager profile on `PATH`. Confirm that `nixos` appears in `/mcp` and look up an option such as `services.openssh.enable`. The server uses public indexes. Check the chosen package or option against the relevant flake's locked dependencies and local overlays before making a change.
