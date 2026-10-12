---
name: "resilient-delegated-batch"
description: "Long delegated batch work a restart, model cut, or timeout can kill — persist every unit immediately, order phases by value, resume from the kept session."
---

# Resilient delegated batch work

Applies when a child run performs many units of work (benchmarks, migrations,
bulk edits, crawl-then-process) long enough that a gateway restart, model cut,
or timeout can interrupt it. A killed child loses everything it held in memory;
only what it already wrote survives.

## Brief for interruption survival

Before spawning, fix these three things in the task text:

1. **Persistence point.** Name the exact artifact path and state: write each
   unit's result the moment it is scored, append-only, keyed by a stable
   identifier. Re-running must skip keys already present. A single write at the
   end means one restart discards the whole run — that is the failure mode this
   prevents, and it is a brief-authoring mistake, not a runtime fault.
2. **Phase order.** Order phases so the highest-value answer lands first (fast
   tests before long-context tests, cheap targets before expensive ones). Losing
   a late phase is acceptable; losing the answer is not.
3. **Secrets.** Instruct reading secrets at runtime
   (`K="$(cat ~/.secrets/<name>)"`) and never persisting a value to any file.

## Recover an interrupted child

1. Inspect the artifact path first. Files that exist are evidence of what
   survived — do not re-derive or re-brief before looking.
2. Resume with `sessions_send` to the **same sessionKey**, not a fresh spawn.
   The kept session still holds the harness or plan in its transcript; a new
   spawn starts from nothing.
3. In the recovery message, restate only what changed: the persistence rule,
   the phase order, and that already-recorded keys must be skipped. The
   original brief remains in the child's transcript — restating all of it wastes
   context and hides the delta.
4. Verify the child is actually running (artifact files growing, or task state
   `running`) before telling the user recovery succeeded. An accepted
   `sessions_send` reports `queued`, which is not the same as started.

## A child died with no output (model error) → `assets/dead-child-no-output.md`

Full text moved to the support file (SKILL.md 10K-char limit): diagnosing a
dead child that produced no output, distinguishing model error from real
failure, and the recovery recipe.

## A child hit the timeout: mine the transcript before re-running

A timeout reports an empty result block, but the child's analysis survives in
its transcript. Read `sessions_history` (includeTools false, last few
assistant turns) — the thinking blocks carry the partial findings. Verified
2026-10-02: a worker that timed out after 41 tool calls had the complete root
cause (hardlink rejection of nix-store SKILL.md) in its thinking; the fix was
written from the transcript without any re-run. Re-running a deep
investigation child blind throws that away and burns another 25 minutes. When a
deep read-only child stalls past ~45 min having written nothing, split it by
question into narrow parallel children instead of waiting: each gets 1–2
distinct questions, a short report contract (≤60 lines), and mandatory
incremental writes (verified 2026-10-06: a 48-min compaction-debt child was
cancelled with zero disk output and 282k context; two narrow children answered
the same questions in ~17 min each — the budget-proposal part went to the
advisor as a verdict, not research).

If the user redirects the task to a different agent mid-run, cancel by the
`taskId` from `subagents(action=list)` — a runId fails with "Task outside
session tree" — and respawn on the requested agent with the same brief plus
any facts already confirmed. A cancel/kill does NOT roll back file edits the
child already made on the target: the respawn brief must include a
"check `git diff`, revert the killed run's leftovers, keep pre-existing
user hunks" step, or the retry builds on a half-applied obsolete spec
(verified 2026-10-03: a killed classifier run left its off_topic deletion in
the working tree; the retry had to revert it before applying the revised spec).

## Waiting without a completion event

The normal path is a completion message. When a follow-up run is queued rather
than owned by the current turn, `sessions_yield` fails with "No pending child
completion is owned by this turn" — expected, not an error to retry. Fall back
to polling the artifact path:

```sh
prev=-1; stale=0
for i in $(seq 1 40); do
  [ -f REPORT.md ] && { echo DONE; break; }
  n=$(python3 -c "import json;print(len(json.load(open('results.json'))))" 2>/dev/null || echo 0)
  [ "$n" -ge "$TARGET" ] && break
  if [ "$n" = "$prev" ]; then stale=$((stale+1)); else stale=0; fi
  [ "$stale" -ge 10 ] && { echo "STALLED at $n"; break; }
  prev=$n; sleep 8
done
```

Reset the stale counter on every growth signal so a slow-but-live run is not
killed, and break on real stalling so a dead child surfaces instead of hanging
the turn. An exec loop that outruns the tool's foreground limit returns a
process session id — re-read the artifact rather than starting a second
watcher.

## Re-delegating into a new session: clear the old session's queue first

Queued `sessions_send` followups in a kept session fire when the child's next
run starts — even much later, after the task there looked finished. Re-spawning
the same brief into a fresh session while a followup still sits in the old one
guarantees two children working the same task concurrently (verified
2026-10-02: a KB pipeline was fully delivered by the old session's queued
followup while a fresh spawn re-implemented it — duplicate commits had to be
intercepted). Before a fresh spawn, check the old session's
`sessions_history` `pendingInputs` and let the user know both lanes exist, or
the fresh child gets an explicit "this task may already be done; verify target
state first" line in its brief.

Stopping a busy child mid-call by steering usually fails:
`queue_message_failed ... steering message was not committed before timeout`
repeats on retry while the child stays inside a long tool call. If three
steers fail, do not keep trying — let the run end, intercept its report, and
apply/ignore its output against the delivered duplicate deliberately.

## Text-only final-step failure

A child that exhausts tools/context right before its final file write reports
"BLOCKED: plan ready, file NOT written" (recurred twice 2026-10-03). Do not
re-run the child: re-deliver the plan text to the parent and have the parent
write the file. The persistence rule makes this rare; this is the fallback
when it still happens.

## Reporting an interruption

State what was lost, that it was measured, and what changed to prevent a
recurrence. Never report the restarted run's results before they exist, and
never reconstruct a table from partial scores as if it were complete.
