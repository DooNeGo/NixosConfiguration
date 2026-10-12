# Threshold verification + summarizer debugging

Moved verbatim from `lossless-compaction-threshold/SKILL.md` on 2026-10-08
(SKILL.md exceeded the 10,000-char authoring limit). Headings unchanged.

## Step 6 — trigger, then verify

There is no `/lossless compact` in 1.1.1; the subcommands are `status, focus,
refocus, unfocus, backup, doctor, doctor clean, doctor apply, help`. After
applying, one ordinary turn should flip `shouldCompact` to true and write debt.

To force it immediately, `/lossless focus <brief>` runs a real compaction
(`force: true`); `/lossless unfocus` clears the brief.

Verify by these lines, not by the `/lcm` counter alone:

```sh
grep -hE "compact: decision|assemble: foreground compaction" /tmp/openclaw/lossless-claw-*.log | tail -5
```

The decision line prints `shouldCompact`, `tokenBudget`, `threshold`,
`hostOwnsPromptFraming`, and `observedRuntimeOverhead`. Threshold-selection
lines also print the matched rule and its name — if `modelContextWindow=none`
appears, the override did not match and the global value is in force.

On this host the decision lines may never appear at the default log level: a
2026-10-01 run that did compact a real conversation produced none in that day's
log. Do not conclude "did not compact" from their absence — the working success
marker is the assemble line `assemble: foreground compaction ... before=<n>
after=<n> target=<n> reduced=true reachedTarget=... pending=...`.

Maintenance close (`/lossless doctor apply maintenance <id>
confirm-inactive`) — chat-only, no CLI/gateway-call surface, and it requires
`conversations.active=0`: the plugin refuses with "active-conversation"
otherwise (verified 2026-10-06 against live DB + plugin code). Dead
internal-session sessions never flip inactive — 43 workshop-review rows sat at
active=1 with their runs long gone, so close is unreachable for the whole
family; file an upstream issue for an archive mechanism instead of retrying.
A successful close resolves ONE debt row administratively (−1 pending row,
—1.5% debt at best) and deletes no content — never expect token counts to
drop. So: use it only for genuinely inactive hygiene rows, never as a way to
"make progress" on pressure, and never instead of a real compaction.
`/reset` archives the conversation instead of compacting it.

## Step 7 — armed but never completes: check the summarizer

`reachedTarget=false pending=true` on a compaction line — or one successful
compaction followed by unchecked context growth — with a plausible threshold
means the summarizer lane failed, not the arithmetic. The signs sit in the same
log:

```sh
grep -iE "summarizer timed out|empty normalized summary|retry also returned empty" /tmp/openclaw/lossless-claw-*.log | tail -5
```

Repeated `summarizer timed out` (60s cap) or `empty normalized summary` across
the configured `summaryModel` **and** its fallback means that lane is unusable;
retries change nothing, so fix the model, not the threshold. Set
`config.summaryModel` (keeping it inside `llm.allowedModels`) to a model
verified to return text, re-evaluate via the `nix-openclaw-config` flow, and
confirm the next foreground-compaction line reports `reduced=true`
`reachedTarget=true pending=false`.

Completion check: `summaries` is non-zero, the `compact: decision` line shows
`shouldCompact=true` with the expected `threshold`, the measured overhead has
been folded back into the number if it was not already accounted for, and the
