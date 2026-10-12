# A child died with no output (model error)

A run that dies on a provider/model error reports an empty result — but work
it did before dying persists on the target. Do not respawn blindly.

1. Inspect the target state first: `git status`/`git diff` on the remote
   repo, `py_compile` touched files, list scratch files. A mid-task death can
   leave valid partial changes, and several partial runs can combine into the
   real state; check the union, not one run.
2. Verify the partial work (compile, targeted diff review) and either commit
   it yourself or leave it deliberately; then make the respawn brief
   state-aware — name the commit hash and "already done, do not redo".
   Check a child's diff against the repo's standing rules (e.g. the comment
   policy in AGENTS), not just correctness. Children do not reliably follow
   those rules: strip violations yourself before commit rather than relying on
   the child.
3. Classify the error first — it decides the recovery route:
   - **The same error across every child on one model is a provider outage**, not
     child-specific. Before any re-dispatch, probe the provider endpoint directly:
     `curl -s -m 10 --noproxy '*' <vllm-host>:8000/v1/models` — a hanging or refused
     call proves the lane is down. Re-route the affected tasks to a lane that
     answered recently instead of respawning into the dead one; re-check the
     endpoint when lane capacity matters again.
   - **/tmp is wiped by a gateway restart or routine cleanup, whichever comes
     first.** After either, an `agents_wait` on the old run ids returns
     `not_found` for every one of them, and artifacts under /tmp are wiped with the
     ephemeral store. Results the collector already returned survive only in your
     transcript — salvage them into a durable file before anything else, and brief
     every fan-out child to write deliverables under `~/research/...` (or any
     persistent path), never /tmp.
   - **Billing / insufficient-credit errors are account-transient**, not
     child-specific. Do not respawn on the same provider; once the balance is
     restored, resume the kept session with `sessions_send`, restating only
     where the child stopped.
   - For other dead children, `sessions_send` resume to the settled session
     is worth one attempt; only if it fails with "session rebound" fall back to a
     fresh spawn with the state-aware brief — retrying delivery after that message
     is wasted effort.
4. The transcript stays readable after the child settles
   (`sessions_history`, last assistant turns). Do not wait for the completion
   delivery of an errored run: it can stay `pending` forever while the run is
   already dead.
5. Track brief→outcome; after two consecutive empty model-error failures on
   the same agent/model, stop respawning it — either run the task directly
   yourself (if reachable via exec/ssh) or escalate to the user for a model
   change.
