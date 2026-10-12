---
name: head-to-head-model-test
description: Which model is better, or compare two LLM endpoints: live head-to-head run with deterministic scorers and latency.
---

# Head-to-head model test

Compare two models by running them, not by citing leaderboards. Triggers: "which
model is better for X", "compare our local model with <provider> model", or any
claim about which model should fill an agent role.

## Step 1 — resolve real endpoints from config

Read the actual provider block, never guess URLs or ids. In OpenClaw agent/model
overrides the id must be the plain `openrouter/<vendor>/<model>` form. A
`~`-prefixed variant is rejected by the provider with "model not found" while the
same id without `~` works.

```sh
readlink -f ~/.openclaw/openclaw.json   # live path; may be a symlink into /nix/store
python3 -c "import json;d=json.load(open('/home/openclaw/.openclaw/openclaw.json'));print(json.dumps(d.get('models',{}),indent=1));print('primary:',d.get('agents',{}).get('defaults',{}).get('model'))"
```

Secrets live in `~/.secrets/`; read with `$(cat ...)` into a variable and never
print or persist the value. Health-check both endpoints before building
anything — a model route can be dead independently of the gateway.

## Step 2 — network shape differs per endpoint

OpenRouter and other internet hosts go through the configured proxy. A
Tailscale/LAN vLLM host does **not** and fails unless proxying is disabled for
it, so pass `--noproxy '*'` on local calls and leave it off for provider calls.
Working pair:

```sh
# provider: via proxy, bearer auth
curl -s -m 60 https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"<id>","messages":[...],"reasoning":{"effort":"high"}}'

# local vLLM: bypass proxy, no auth
curl -s -m 60 --noproxy '*' http://<host>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' -d '{"model":"<id>","messages":[...]}'
```

`GET <vllm>/v1/models` returns `max_model_len` — read it and cap any long-context
prompt to the **smaller** of the two context windows, otherwise the comparison
silently measures context size instead of the model.

## Step 3 — deterministic scorers only

Design tests whose score is decided by code, never by your reading or by an
LLM judge:

- coding → hidden pytest suites, run the extracted function, report passed/total;
- tool calling → compare the planned call sequence to the known-correct one,
  plus counts of hallucinated paths and unused tools;
- constraint following → regex/string assertions, one per constraint, counted
  as violations/n;
- structured output → schema validation plus any literal requirement like
  "exactly 3 entries";
- long context → a distinctive token buried mid-prompt, exact-match grade.

Send the byte-identical prompt to both models, extract fenced code robustly
(` ``` ` and `~~~`), and score an unparseable or refused answer as **0 with the
reason recorded** — never retry it into passing.

**Before trusting any score, run a known-good reference solution and a
known-bad one through your own checkers and confirm 100% and <100%.** Skipping
this produces confident nonsense; show the sanity-check output.

## Step 4 — throttle free-tier endpoints

Free provider routes are capped by credit-tier request count, not spend, and
the cap is invisible in billing. Sleep 6–8s between calls to those. On
repeated credit/rate errors, stop that side, keep the other side's results, and
report the observed cap as a finding — an incomplete run beats a lost run.

## Step 5 — read latency, not just score

Record wall-clock seconds, completion tokens, and tok/s per call. A model that
scores marginally higher at 3× the latency is the wrong default for an
interactive agent role. Reasoning effort changes this independently of quality:
sweep it (low/medium/high) on a couple of tests before adopting a default, and
pin the effort explicitly when a provider's catalog default is higher than the
measured optimum.

**Confirm the provider reports reasoning tokens at all before sweeping effort.**
Some providers accept every effort level (including `xhigh`) with HTTP 200 yet
report zero reasoning tokens, while latency still changes. Accepting the
parameter is not evidence that it did anything: compare reported reasoning
tokens per effort, not just the HTTP status.

## Report honestly

- n=1 per test is **indicative only**; say so in the writeup.
- Keep coding and tool-calling conclusions separate — they can diverge sharply.
- Distinguish a refusal/parse failure from a wrong answer.
- Give raw paths to the harness, results JSON, and checkers so the numbers can
  be re-run.
