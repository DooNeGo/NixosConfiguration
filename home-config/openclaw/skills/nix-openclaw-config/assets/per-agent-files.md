# Per-agent files in the Nix-managed OpenClaw config

How to give ONE agent a skill or persona file declaratively — and the two
silent-drop traps that make the file invisible without any error. Verified
2026-10-02 (code-mode-guest relocation, persona bootstrap fix; commits
aa07a13, 30fc4ec, 0a4ae1b).

## Scope: where a per-agent file can live

| Goal | Mechanism |
| --- | --- |
| Give one agent a skill | real dir in `<workspace>/skills/<name>` (loader source `openclaw-workspace`) + the name in that agent's `skills` allowlist |
| Persona bootstrap (AGENTS/SOUL/IDENTITY/USER.md) | real files in `<workspace>/<agent>/` |
| Give all agents a skill | `programs.openclaw.skills` in the module — **global**, no per-instance option exists |

Visibility has no per-skill `deny`: keep a skill off an agent by not placing
the file in its scope, or by giving that agent an explicit `skills` allowlist.
Workshop skills are per-agent by design and are never shared.

## The two silent-drop traps (both: no error visible in the list)

1. **Symlinked skill dir from `home.file`.** With
   `skills.load.allowSymlinkTargets = [ "/nix/store" ]` the symlink
   containment check passes — but the workspace loader in Nix mode
   (`OPENCLAW_NIX_MODE=1`) also rejects hardlinked files. The bypass applies
   only when the scanned root dir itself is in `/nix/store`; a workspace
   root is not, and a store `SKILL.md` has `nlink > 1` (store dedup) →
   "path must not be hardlinked" → the skill vanishes from
   `openclaw skills list` entirely (not even "excluded"). Diagnosed by
   mining a timed-out analysis child's transcript (nlink=4 on SKILL.md,
   reproduced with `openRootFileSync`).

2. **Symlinked persona bootstrap files.** Context injection refuses symlinks
   outright: the agent's own system prompt shows
   `[UNREADABLE: symlink path component not allowed]` and the file
   (AGENTS.md, USER.md, …) is silently absent from the prompt. The marker in
   the live prompt is the diagnostic — do not re-derive it from the loader.

Both fixes are the same shape: **real files via `home.activation`, never
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

- Source the content from the repo (committed). Nix refuses untracked paths
  in flake sources — `git add` before building.
- `cp -r`/`cp` produce real files (nlink=1) — both traps cleared.
- Persona files: same pattern per agent for the four bootstrap files
  (`rm -f` + `cp` + `chmod u+w`). Live edits between switches survive; a
  switch restores the repo canon. Diff repo vs live before the first
  adoption so the copy does not clobber live-only changes.
- A second `home.activation.*` block is fine, but the module's closing `}`
  must stay at the very end of the file — a premature `}` fails eval with
  "syntax error, unexpected '='" (cost a build round trip 2026-10-02).
- Keep `skills.load.allowSymlinkTargets` only while some symlinked skill
  root is actually intended; it grants nothing to agents by itself but is
  dead config otherwise.

## Verify

- Skills: `openclaw skills list --agent <id>` is the ground truth —
  `ready` = loaded, `excluded` = discovered but not allowlisted, absent =
  discovery failure (traps above). Check coordinator/worker absence too when
  the goal is coder-only.
- Bootstrap: `ls -la` shows regular files (no `l`), and the
  `[UNREADABLE: …]` marker is gone from the agent's next system prompt.
- Nothing reflects until the user's `home-manager switch` — the CLI reads the
  running config, so "not visible yet" right after a build is expected, not a
  failure.