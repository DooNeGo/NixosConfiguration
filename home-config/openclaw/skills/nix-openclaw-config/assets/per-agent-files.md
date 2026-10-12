# Per-agent files in the Nix-managed OpenClaw config

How to give ONE agent a skill or persona file declaratively, and the two
silent-drop traps that make the file invisible without any error.

## Scope: where a per-agent file can live

| Goal | Mechanism |
| --- | --- |
| Give one agent a skill | real dir in `<workspace>/skills/<name>` (loader source `openclaw-workspace`) + the name in that agent's `skills` allowlist |
| Persona bootstrap (AGENTS/SOUL/IDENTITY/USER.md) | real files in `<workspace>/<agent>/` |
| Give all agents a skill | `programs.openclaw.skills` in the module — **global**, no per-instance option exists |

Visibility has no per-skill `deny`: keep a skill off an agent by not placing the
file in its scope, or by giving that agent an explicit `skills` allowlist.
Workshop skills are per-agent by design and are never shared.

## The two silent-drop traps (both: no error visible in the list)

1. **Symlinked skill dir from `home.file`.** With
   `skills.load.allowSymlinkTargets = [ "/nix/store" ]` the symlink containment
   check passes, but the workspace loader in Nix mode (`OPENCLAW_NIX_MODE=1`) also
   rejects hardlinked files. The bypass applies only when the scanned root dir
   itself is in `/nix/store`. A workspace root is not, and a store `SKILL.md` has
   `nlink > 1` (store dedup), so the loader reports "path must not be hardlinked"
   and the skill vanishes from `openclaw skills list` entirely (not even as
   "excluded"). Reproduce with `openRootFileSync` on the file to see `nlink`.

2. **Symlinked persona bootstrap files.** Context injection refuses symlinks
   outright. The agent's system prompt shows `[UNREADABLE: symlink path component
   not allowed]` and the file (AGENTS.md, USER.md, …) is silently absent from the
   prompt. The marker in the live prompt is the diagnostic; do not re-derive it
   from the loader.

Both fixes have the same shape: **real files via `home.activation`, never
`home.file` for store-sourced content an OpenClaw loader must read.**

## Procedure: activation copy

```nix
home.activation.copyCoderSkill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  target="$HOME/.openclaw/workspace/coder/skills/code-mode-guest"
  rm -rf "$target"
  mkdir -p "$(dirname "$target")"
  cp -r ${./skills/code-mode-guest} "$target"
  chmod -R u+w "$target"
'';
```

- Source the content from the repo (committed). Nix refuses untracked paths in
  flake sources, so `git add` before building.
- `cp -r` and `cp` produce real files (nlink=1), which clears both traps.
- Persona files: use the same pattern per agent for the four bootstrap files
  (`rm -f` + `cp` + `chmod u+w`). Live edits between switches survive; a switch
  restores the repo canon. Diff repo against live before the first adoption so
  the copy does not clobber live-only changes.
- A second `home.activation.*` block is fine, but the module's closing `}` must
  stay at the very end of the file. A premature `}` fails eval with "syntax error,
  unexpected '='".
- Keep `skills.load.allowSymlinkTargets` only while some symlinked skill root is
  actually intended. It grants nothing to agents by itself and is dead config otherwise.

## Verify

- Skills: `openclaw skills list --agent <id>` is the ground truth. `ready` means
  loaded, `excluded` means discovered but not allowlisted, and absent means
  discovery failed (the traps above). Check coordinator and researcher absence too
  when the goal is coder-only.
- Bootstrap: `ls -la` shows regular files (no `l`), and the `[UNREADABLE: …]`
  marker is gone from the agent's next system prompt.
- Nothing reflects until the owner's `home-manager switch`. The CLI reads the
  running config, so "not visible yet" right after a build is expected.
