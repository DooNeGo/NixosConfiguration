---
name: "code-mode-guest"
description: "Use when OpenClaw Code Mode is engaged — correct guest JS recipes (exec evaluates code, tools are async globals, shell via guest exec), avoiding shell-in-code, tools.-namespace, wrong payload keys, heredoc/quoting breakage, busy-wait status loops, and backslash-escaping regressions."
---

# Code Mode guest recipes

Use when a run is engaged in OpenClaw Code Mode: top-level `exec` evaluates
JavaScript, not shell. Goal: correct calls on the first try — no
shell-in-code rejections, no broken quoting, no wasted status round trips.

## Core rules

0. FIRST call in any Code Mode run, before any shell/file work:
   `const s = await skills.read("code-mode-guest"); text(s);`
   `skills.read(name)` is the guest global for loading a skill by name.
   Observed cost of skipping: 6 failed tool results and ~6 minutes before
   the first successful file write (2026-10-02, seq5–seq44).
1. Top-level `exec` takes `{ code, language }` only — `code` is the one
   required key. Payload under `content` → `Validation failed for tool
   "exec": code: must have required properties code` (happened even after
   the skill was read); shell-looking `code` → `invalid_input`. On
   `Validation failed` your KEY is wrong — resend the same JS under `code`.
2. There is NO `tools` object: `tools.exec(...)`, and even `tools?.ls?.(...)`,
   fail with `ReferenceError: tools is not defined` (optional chaining does
   not help — the identifier itself is undeclared). Call the global directly:
   `await exec({ command, ... })`. Unknown tool name →
   `const [t] = await catalog.search("...")` (returns an array of callable
   handles; `t.describe()` shows the full schema).
3. Await everything — an unawaited promise fails the cell. Emit results with
   `text(value)` / `json(value)` or as the final `return`.
4. No `import`/`require`, no fs, no network, no Node API inside guest code
   (QuickJS-WASI). Only TextEncoder/TextDecoder, timers, `yield_control`,
   and tool globals.
5. Long work: `background: true` on the shell `exec` global, then
   `process({ action: "poll", sessionId, timeout })` — polling in the same
   cell after `background` works (verified).
   - A cell whose poll loop outlives the per-cell deadline (~10 s) returns
     `{ status: "waiting", runId, reason: "pending_tools" }` — resume with
     `await wait({ runId })`; long jobs legitimately chain 3–6 waits.
   - A synchronous guest `exec` with a large `timeoutSeconds` may
     auto-background and return `{ status: "running", sessionId, pid,
     followUp: "Use process (list/poll/log/...)" }` instead of output — take
     `.sessionId` and poll it; `text(r.aggregated)` on that envelope prints
     `null`.
   - Abort with `process({ action: "kill", sessionId })` (verified).
   - NEVER wait by issuing fresh status ssh calls or remote `sleep` loops:
     polling the sessionId you already have costs 0 extra round trips
     (observed: 33 redundant status ssh calls in 8 minutes).
   - Local background runs may be killed when the session is cleaned up
     mid-run; jobs that must outlive the session start detached on the
     target host (`ssh host 'nohup sh /tmp/job.sh > /tmp/job.log 2>&1 &'`)
     and you poll the log file instead.
   - sessionId is a process id, not a Code Mode runId; `wait({ runId })` is
     only for code-mode `waiting` results (default per-cell deadline 10 s).
6. Output budget: cumulative `maxOutputBytes` (default 65536). Emit trimmed
   `text()`; oversized results arrive with `truncated: true` (success, not
   error). Tool errors are normal JS exceptions — catch, read `error.code`,
   verify state before retrying.
7. Batch per phase, not per fact: one cell = one phase. Combine all
   environment probes into ONE script (write + scp + run) or one quote-free
   one-liner; one runner script per measurement loop (all variants × metrics
   → JSON summary), launched with `background: true`, then poll it. Observed
   cost of violating: 24 tool calls in the first 8 minutes, incl. 7
   consecutive ssh probes to find one Python with PIL. Working loop: read
   summary → decide → edit → relaunch.

## Tool return shapes (verified — objects, not strings)

- `exec` (shell) → `{ status, exitCode, aggregated, ... }`: combined stdout is
  `.aggregated`, success check via `.exitCode`. `b64.trim()` on the raw object
  fails — use `b64.aggregated.trim()`.
- `read` → `{ kind: "text" | "image", content, ... }`: take `.content`.
- `write` → `{ changed, created, diff, patch }`.
- Default cwd may not be a git repo — pass `workdir` explicitly for
  repo-bound commands.
- `read` on a missing path throws ENOENT as a JS exception — catch it or
  check first; the cell fails loudly, not silently. Optional-read pattern
  (verified): `read({ path, optional: true }).catch(() => null)`.

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

// Remote multi-line work is always a FILE: local write → scp → run.
// Never assemble multi-command strings with nested quotes (three observed
// breakages: zsh `(eval):1: no matches found`, missing closing quote →
// `unmatched '`), and never embed heredocs — not in ssh arguments AND not
// twice inside one shipped script (two `<<EOF` blocks broke it).
await write({ path: "/tmp/deploy.sh", content: script });      // local staging
await exec({ command: "scp /tmp/deploy.sh host:/path/" });
await exec({ command: "ssh host 'sh /tmp/deploy.sh'" });
// Short single command without nested quotes is fine as one ssh call.

// Background work + poll (same cell works)
const bg = await exec({ command: "nix build .#pkg --no-link", background: true, timeoutSeconds: 0 });
const p = await process({ action: "poll", sessionId: bg.sessionId, timeout: 30000 });
text(p.aggregated);
```

- After `ssh host 'cat file'` capture, restore a possibly stripped trailing
  newline before rewriting: `if (!c.endsWith("\n")) c += "\n";`.
- `pkill -f pattern` over ssh can match and kill the remote shell itself
  (exit 255); use a self-excluding pattern such as `name[.]py`.
- Files containing backslashes (prompts, LaTeX, regex): build them with
  `String.raw` templates (observed for a full Python pipeline), then VERIFY
  the shipped file numerically (`grep -c`, `py_compile`, `git diff`) — never
  by eye (observed: `\\(` collapsed to `\(` in a plain template literal;
  one edit dropped a closing `]`).

## Anti-patterns (observed)

- `tools.<name>(...)` anywhere in guest code → `ReferenceError: tools is not
  defined`.
- Payload under `content` instead of `code` → `Validation failed … must have
  required properties code`.
- Shell command pasted as top-level `code` → `invalid_input`. Fix: wrap in
  `await exec({ command })`.
- «write недоступен»: standalone `write` is hidden from the model surface
  but present as a guest global — `await write({ path, content })` works
  (recovery verified via `skills.read("code-mode-guest")`).
- Assembly-line waiting: fresh ssh status calls or remote `sleep` loops
  instead of polling the sessionId you already have.
- Backslash-heavy content written in a plain JS template literal → silent
  on-disk corruption (see Reliable patterns; use `String.raw` + numeric
  verify).
- Treating `exec`/`read` results as strings → `.trim()`/`.length` surprises;
  they are objects (see Tool return shapes).

## Engagement (config side)

Code Mode engages per config: `enabled: true` forces it on every tool-capable
run; `"auto"` engages only for models flagged `compat.codeMode: preferred`.
Forcing it on a non-preferred model is a deliberate choice — train the model
with this skill (live check 2026-10-02: mimo-v2.6-flash passed 6/6 forced-code
mini-tasks) and revert to `"auto"` if runs keep failing.

Telemetry note: `visibleTools` showed only `["exec","wait"]` with
`catalogSize: 9` — the surface list does not reflect guest globals (`write`
gave `Tool write not found` while the guest global worked). Do not conclude
a tool is missing from the surface alone; try the global or
`catalog.search`.

Source docs: `tools/code-mode/*.md` in the gateway package (2026.9.5);
return shapes live-verified: 6/6 mini-task run, 2026-10-02.