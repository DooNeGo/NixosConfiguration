---
name: "code-mode-guest"
description: "Use when OpenClaw Code Mode is engaged — correct guest JS recipes (exec evaluates code, tools are async globals, shell via guest exec), avoiding shell-in-code, heredoc-via-ssh, and unawaited-promise failures."
---

# Code Mode guest recipes

Use when a run is engaged in OpenClaw Code Mode: top-level `exec` evaluates
JavaScript, not shell. Goal: correct calls on the first try — no
shell-in-code rejections, no broken quoting.

## Core rules

1. Top-level `exec` takes `{ code, language }` only. `command` is an alias for
   the JS source, never a shell string; shell-looking `code` is rejected with
   `invalid_input` before execution.
2. Every enabled non-MCP tool is an async global with its normal parameters.
   Shell from guest code is the regular
   `exec({ command, workdir, timeoutSeconds, background })` global. Unknown
   tool name → `await catalog.search("...")`; the call returns an array of
   callable handles (`const [t] = await catalog.search(...)`), and
   `t.describe()` shows the full schema.
3. Await everything. An unawaited promise fails the cell. Emit results with
   `text(value)` / `json(value)` or as the final `return`.
4. No `import`/`require`, no fs, no network, no Node API inside guest code
   (QuickJS-WASI). Only TextEncoder/TextDecoder, timers, `yield_control`, and
   tool globals.
5. Long work: `background: true` on the shell `exec` global, then
   `process({ action: "poll", sessionId, timeout })` — polling in the same
   cell after `background` works (verified). sessionId is a process id, not a
   Code Mode runId; `wait({ runId })` is only for code-mode `waiting` results
   from nested tool calls (default per-cell deadline 10 s).
6. Output budget: cumulative `maxOutputBytes` (default 65536). Emit trimmed
   `text()`; oversized results arrive with `truncated: true` (success, not
   error). Tool errors are normal JS exceptions — catch, read `error.code`,
   verify state before retrying.

## Tool return shapes (verified — objects, not strings)

- `exec` (shell) → `{ status, exitCode, aggregated, ... }`: combined stdout is
  `.aggregated`, success check via `.exitCode`. `b64.trim()` on the raw object
  fails — use `b64.aggregated.trim()`.
- `read` → `{ kind: "text" | "image", content, ... }`: take `.content`.
- `write` → `{ changed, created, diff, patch }`.
- Default cwd may not be a git repo — pass `workdir` explicitly for
  repo-bound commands.
- `read` on a missing path throws ENOENT as a JS exception — catch it or
  check first; the cell fails loudly, not silently.

## Reliable patterns

Copy-paste ready companion file with the same shapes:
`examples/recipes.js`.

```javascript
// Shell inside guest code (top-level code stays JS)
const st = await exec({ command: "git status --short", workdir: "/home/openclaw/repo", timeoutSeconds: 30 });
text(st.aggregated);

// Tool global with normal params
const f = await read({ path: "/home/openclaw/file.txt" });
text(f.content);

// Remote file transfer — never a heredoc inside ssh quotes
await write({ path: "/tmp/deploy.sh", content: script });      // local staging
await exec({ command: "scp /tmp/deploy.sh host:/path/" });
// or base64 one-liner (base64 alphabet is quote-safe):
const b64 = await exec({ command: "base64 -w0 /tmp/deploy.sh" });
await exec({ command: `ssh host "echo '${b64.aggregated.trim()}' | base64 -d > /path/f"` });

// Background work + poll (same cell works)
const bg = await exec({ command: "nix build .#pkg --no-link", background: true, timeoutSeconds: 0 });
const p = await process({ action: "poll", sessionId: bg.sessionId, timeout: 30000 });
text(p.aggregated);
```

## Failure modes from observed runs (2026-10-02)

- Shell command pasted as top-level `code` → `invalid_input`. Fix: wrap in
  `await exec({ command })`.
- «write недоступен»: standalone `write` is hidden from the model surface but
  present as a guest global — `await write({ path, content })`, or
  `catalog.search("write file")`.
- Heredoc through ssh → far-end SyntaxError (quotes eaten by the outer
  shell). Fix: local `write` + `scp`, or base64 one-liner; never nest
  multi-line quoted heredocs in a double-quoted ssh argument.
- Treating `exec`/`read` results as strings → `.trim()`/`.length` surprises;
  they are objects (see Tool return shapes).

## Engagement (config side)

Code Mode engages per config: `enabled: true` forces it on every tool-capable
run; `"auto"` engages only for models flagged `compat.codeMode: preferred`.
Forcing it on a non-preferred model is a deliberate choice — train the model
with this skill (live check 2026-10-02: mimo-v2.6-flash passed 6/6 forced-code
mini-tasks) and revert to `"auto"` if runs keep failing.

Source docs: `tools/code-mode/*.md` in the gateway package (2026.9.5);
return shapes live-verified: 6/6 mini-task run, 2026-10-02.
