---
name: lossless-compaction-threshold
description: lossless-claw produced no summaries, or context grows unchecked — read the plugin log, compute the threshold vs the model's window, set a working one.
---

# lossless-claw compaction never arms

Trigger: `/lcm` or `/lossless` reports `summaries: 0` on a long session, or the
assistant's context grows toward the model window while nothing compacts. The
usual cause is arithmetic, not breakage: the threshold is relative to the
model's own token budget, so a plausible-looking fraction is far out of reach on
a large-context model.

## Step 1 — read the plugin's own log first

The plugin logs separately from the gateway, under a dated file. Do not search
the gateway journal for it; `journalctl --user -u openclaw-gateway` has no
LCM lines at all.

```sh
ls -la /tmp/openclaw/lossless-claw-*.log
grep -iE "summar|error|threshold|debt|sweep" /tmp/openclaw/lossless-claw-*.log | tail -30
```

`assemble: done` lines carry the numbers that decide everything:
`tokenBudget`, `estimatedTokens`, `internalEstimatedTokens`, `hasSummaryItems`.

A direct read-only DB route works: `sqlite3` lives in the nix store
(`find /nix/store -maxdepth 3 -name sqlite3 -path '*bin*'`), and SELECT queries
against the live `~/.openclaw/lcm.db` return real rows. Writes are refused. The
gateway writes concurrently (WAL — live numbers drift, so timestamp every
before/after capture). Table names are `conversations`, `messages`, `summaries`,
`conversation_compaction_maintenance` (not "compaction tables"). For a stable
snapshot, run `sqlite3 <db> ".backup <path>"` first (the file is large) and
query the copy.

## Step 2 — do the arithmetic before changing anything

The single decision site (`src/compaction.ts`) is:

```
thresholdTokens = floor(contextThreshold * tokenBudget)
shouldCompact  = max(storedTokens, liveTokens) > thresholdTokens
```

`tokenBudget` is the **host's per-turn budget**, i.e. the model's window — not a
fixed budget and not the assembly budget. So on a ~1M-token model:

```
budget 995000 * 0.30 = 298500   <- a plausible 0.3 arms at ~300K and never fires
budget 995000 * 0.10 =  99500   <- target ~100K
```

Compute `target / tokenBudget` from the log's own `tokenBudget` before choosing a
number. Report the multiplication; a bare fraction is not a justification.

**Ignore the assembly-budget figure in the `/lcm` health warning when
`maxAssemblyTokenBudget` is unset.** It resolves as
`maxAssemblyTokenBudget ?? maintenance.tokenBudget ?? 128_000`, and with
neither host key set it is a hardcoded display fallback. It is not the threshold
basis and chasing it wastes the whole investigation.

**When `maxAssemblyTokenBudget` IS set, the rule changes.** The cap clamps both
the assembly budget and threshold evaluation (`min(budget, cap)`), so the
threshold basis becomes the capped value. Verify which base actually applied
from the decision line: `targetTokens` divided by `threshold` gives the base
(for example, `targetTokens=14400` at `threshold=0.08` means base 180000, the
host budget, while assembly separately ran at a much larger size). Do not assume
the cap moved the base; read the multiplication.

## Step 3 — decide whether overhead counts, from host source

The left side of the comparison is the LCM frontier **only** when the host owns
prompt framing. `hostOwnsPromptFraming` is true iff
`runtimeSettings.executionHost.id` is a non-empty string, and for the embedded
OpenClaw runner that id is `"openclaw-embedded"` (`dist/host-compat-*.mjs`).

That means system prompt, tool schemas and skills sit **on top of** the
threshold figure rather than inside it. A threshold chosen as "100K of context"
yields a real prompt nearer 100K + fixed overhead. Read
`observedRuntimeOverhead` from the `compact: decision` log line after the first
successful compaction and adjust from the measured value — do not guess it.

## Step 4 — set the threshold, and pick the knob that binds

**Pair the threshold with `maxAssemblyTokenBudget` deliberately: trigger =
threshold × min(host budget, cap).** Aim the trigger at roughly 16–24k of
history. A too-low fraction (0.08 was tried) fired `compact: decision force=true`
at ~14.4k nearly every turn; the summarizer spend guard then tripped (24 summary
calls per 10 min per session → 30-minute backoff → 512-token fallback summaries,
which are lossy and log `compact ok=false`). A bare low fraction schedules
summarizer storms; compute the trigger from the resolved base instead of copying
a fraction.

```nix
"lossless-claw" = {
  enabled = true;
  config = {
    contextThreshold = 0.10;
    freshTailCount = 24;          # raw tail is unsummarizable: keep it a small
                                   # fraction of a 100K budget (implicit default 64)
    leafChunkTokens = 12000;      # finer descent, less overshoot
    proactiveThresholdCompactionMode = "deferred";
  };
}
```

`freshTailCount` sets the floor on the protected raw tail; `freshTailMaxTokens`
only caps an exception path and is largely inert at a small count. Prefer the
count; do not carry a `freshTailMaxTokens` left over from a larger budget.

For the schema of `contextThresholdOverrides` — nested `match` objects, rule keys
exactly `name/match/contextThreshold/freshTailCount/leafChunkTokens` — prefer
the `openclaw.plugin.json` manifest over prose docs. Window matchers
(`modelContextWindowMin`) need explicit host window metadata and are inert
without it; `sessionPattern`/`model` are the reliable matchers. The bundled
config reference's own large-window example pairs `0.15` with
`freshTailCount: 16` and `leafChunkTokens: 12000` — copy the pattern, not just
the number.

Apply it through the Nix module, not the JSON: see `nix-openclaw-config`
(the gateway's home-config flake). For NixOS system-level units instead, see
`nixos-system-config`.

## Step 5 — confirm the deferred drain is actually wired

`deferred` mode only records a debt row; a `maintain()` pass consumes it, gated
on `runtimeContext.allowDeferredCompactionExecution === true`. Verify the host
dist actually passes it before blaming the threshold:

```sh
grep -rl "allowDeferredCompactionExecution" \
  /nix/store/*openclaw-gateway*/lib/node_modules/openclaw/dist
```

If it is absent, the debt is recorded and never drained and the fix looks like
it did nothing — that is the most likely way a correct threshold change appears
to fail. Debt is SQLite-backed, so it survives a restart; a row written under an
old threshold is superseded by live config and cannot wedge the session.

Even with the drain hook present, `deferred` can idle: the drain fires only on
the gateway's maintenance interval, and a flaky summarizer can starve it. When
debt rows pile up while context keeps growing, check the summarizer lane
(Step 7) before reaching for `inline`; fixing `summaryModel` beats
mode-switching. Do not switch to `inline` while the threshold is the real
problem: its turn-path sweeps can be slow (one ran ~200 s on the turn-critical
path) and mostly do nothing. Switch to `inline` only when the drain hook itself
is absent or never fires and turn-path cost is acceptable
(`proactiveThresholdCompactionMode` accepts `inline | deferred`, default
`deferred`).

Manual recovery that bypasses the deferred path entirely: user `/compact` runs
a synchronous foreground summarization of the whole tail (takes minutes, several
LLM calls on a large context) and publishes immediately — no maintenance, no
drain gating. It is the reliable "get the context back now" move when the plugin
idles, and the resulting post-compaction state (context below threshold)
satisfies the plugin's own bookkeeping.

## Steps 6–7 → `assets/verify-and-summarizer.md`

Full text is in the support file. Read it after setting the threshold:
**Step 6 — trigger, then verify** (arming the drain, what a real pass prints)
and **Step 7 — armed but never completes: check the summarizer** (summary lane
unusable, `summaryModel` + fallback, `reduced=true reachedTarget=true`).
