# A child died with no output (model error)

Moved verbatim from `resilient-delegated-batch/SKILL.md` on 2026-10-08
(SKILL.md exceeded the 10,000-char authoring limit). Heading unchanged.

## A child died with no output (model error)

A run that dies on a provider/model error reports an empty result — but work
it did before dying persists on the target. Do not respawn blindly.

1. Inspect the target state first: `git status`/`git diff` on the remote
   repo, `py_compile` touched files, list scratch files. A mid-task death can
   leave valid partial changes (verified 2026-10-02: two failed runs left a
   correct prompt fix in the working tree; a later one added a second edit on
   top — the union was the real state).
2. Verify the partial work (compile, targeted diff review) and either commit
   it yourself or leave it deliberately; then make the respawn brief
   state-aware — name the commit hash and "already done, do not redo".
   When verifying a child's diff, check it against the user's standing
   repo standards, not just correctness: the operator's rule is that
   comments are an anti-pattern (AGENTS, commit 8aecbe3), yet a coder
   child still filled `sing-box.nix` with explanatory comments (verified
   2026-10-05 — the user had to ask why). Strip them yourself before
   commit; do not rely on the AGENTS rule to reach the child.
3. Classify the error first — it decides the recovery route:
   - **The same error across every child on one model is a provider outage**, not
     child-specific. Before any re-dispatch, probe the provider endpoint directly:
     `curl -s -m 10 --noproxy '*' <vllm-host>:8000/v1/models` — a hanging or refused
     call proves the lane is down (verified 2026-10-04: vLLM was unreachable at
     :8000 and every vllm child died with the same "LLM request timed out" while
     retries were still being burned; mimo children on the other lane kept working).
     Re-route the affected tasks to a lane that answered recently instead of
     respawning into the dead one; re-check the endpoint when lane capacity matters
     again.
   - **/tmp is wiped by a gateway restart or routine cleanup, whichever comes
     first** (verified 2026-10-06: build-tool wrappers vanished from /tmp
     overnight with no restart). After either, an
     `agents_wait` on the old run ids returns `not_found` for every one of them, and
     artifacts under /tmp are wiped with the ephemeral store. Results the collector
     already returned survive only in your transcript — salvage them into a durable
     file before anything else, and brief every fan-out child to write deliverables
     under `~/research/...` (or any persistent path), never /tmp (verified
     2026-10-04: five pending tts-research collectors plus /tmp/tts-research were
     lost overnight; the one already-collected result was rebuilt from context).
   - **Billing / insufficient-credit errors are account-transient**, not
     child-specific. Do not respawn on the same provider; once the balance is
     restored, resume the kept session with `sessions_send` restating only
     where the child stopped. Verified 2026-10-03: a coder run that died on an
     OpenRouter billing error mid-verification was resumed this way and
     completed its remaining checks.
   - For other dead children, `sessions_send` resume to the settled session
     is worth one attempt (verified 2026-10-03 on a settled error run); only
     if it fails with "session rebound" fall back to a fresh spawn with the
     state-aware brief — retrying delivery after that message is wasted
     effort.
4. The transcript stays readable after the child settles
   (`sessions_history`, last assistant turns) — and do not wait for the
   completion delivery of an errored run: it can stay `pending` forever
   while the run is already dead (verified 2026-10-02, two runs settled
   `error` with empty results and pending delivery).
5. Track brief→outcome; after two consecutive empty model-error failures on
   the same agent/model, stop respawning it — either run the task directly
   yourself (if reachable via exec/ssh) or escalate to the user for a model
   change (verified 2026-10-02: five consecutive failed coder spawns on one
   provider before the coordinator took the work over manually).

