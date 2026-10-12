# Resolution order, gateway auth, active-memory, schema-lag traps

Moved verbatim from `nix-openclaw-config/SKILL.md` on 2026-10-08 (SKILL.md
exceeded the 10,000-char authoring limit). Section headings unchanged;
SKILL.md keeps Step 1, 2, 4b, 5 and points here.

## Step 3 — know the resolution order before adding a default

For thinking/reasoning, later config does not override earlier config. A
per-agent `thinkingDefault` beats a per-model `params.thinking`, so a
redundant-looking agent setting silently defeats a per-model one. Check the
existing agent entries before assuming a per-model default takes effect.

Adding entries to `agents.defaults.models` has a second side effect: with no
explicit `modelPolicy.allow`, the gateway (2026.9.5) treats the **keys** of that
block as the model allowlist, so the first `params.*` entry silently forbids
every other model for subagent spawns (`sessions_spawn` fails with
`model not allowed: <model>` for worker and coder alike). Verified 2026-10-02:
mimo-v2.6-flash spawns broke exactly when the thinking-params block was
introduced. Fix inside `agents.defaults`:

```nix
modelPolicy.allow = [ "openrouter/*" "vllm/*" ];
```

Wildcard refs are supported; include every model you rely on (coordinator's
primary, the heartbeat/vLLM model) or those paths break the same way.

Before relying on any provider model id, verify it with a trivial spawn
(`model: "<id>"`, task "Reply with exactly: OK", no tools) — a wrong id fails
fast with "model not found" and costs seconds, not a real run. Ids must match
the provider slug exactly: an `~`-prefixed form (`~xiaomi/mimo-v2.6-flash`)
fails provider lookup where the plain `openrouter/xiaomi/mimo-v2.6-flash`
works. Cheap pre-filter: `GET https://openrouter.ai/api/v1/models` (no key)
confirms the slug exists, but only a trivial spawn proves the key/balance
works (verified 2026-10-03: mimo listed and OK while a glm-flash run had died
on a billing error the day before). Verify by
building the openclaw user's activation package and grepping the generated
`openclaw.json` for `modelPolicy` — then the usual switch + gateway restart.

User requirement (2026-10-02, tools policy): agents governed by a `tools.allow`
list get **no** `tools.deny` — the allow list already hides everything else, so
denies there are dead config. Write `deny` only for deny-list agents (e.g. the
coordinator keeps a deny list and no allow list). When touching tools policy,
remember: `deny` wins over `allow`; `allow` and `alsoAllow` cannot coexist in
one scope; `write`, `edit`, `apply_patch` are separate tool ids (denying
`write` alone does not block file mutation — deny `group:fs` instead).
Verified 2026-10-02: dropping the redundant `deny` blocks from worker/coder,
keeping coordinator's deny list only (commit a2d46cf).

Per-agent `skills` lists follow the same docs
(`config-agents/workspace-and-bootstrap`): a non-empty list is the final set
(no merge with defaults), `[]` = no skills, unset = unrestricted. An
allowlisted skill stays invisible to the agent until `home-manager switch`
(and even then only for new sessions — verified 2026-10-02: added
`code-mode-guest` to coder's list; `openclaw skills list --agent coder`
still reported 4/55 ready until the switch). Adding a skill to an agent's
allowlist is the user's decision — the user keeps coder's list strict and
corrected an unprompted addition the same day; bundle related work ("check
the skill") does not grant allowlist changes. When a run must follow skill
rules before the allowlist/switch lands, inline the rules into the task
brief instead.

There is NO per-agent denylist (verified 2026-10-06 across runtime code, zod
schema, generated nix options, and docs: the filter is exact-match
`baseFilter.includes(skillName)`, the zod schema is `strict()`, the option
type is `nullOr (listOf str)`). The only deny is GLOBAL
`skills.entries.<key>.enabled = false` — it hides the skill for every agent
(it is checked before agent filters) and cannot be scoped per agent.
Place the deny map INSIDE the gateway `config` attrset (`config.skills.entries
= …`), not at the module level: `programs.openclaw.skills` is the
skill-registration list, so a module-level `skills.entries` collides with it
and fails eval with a duplicate attribute error pointing at the
`skills = [` line (verified 2026-10-06). Take exact keys from
`openclaw skills list --json` — an invented key (e.g. `onepassword` for
`1password`) silently denies nothing. Bundled
and plugin skills reach an allowlisted agent only via a new allowlist line,
so revise the list at each `nix-openclaw` bump — new skills cannot arrive
without one. Do not chase an allow/deny object form or glob patterns:
`"-*"` is a literal name that matches nothing.

Distributing a skill or persona file to ONE agent is a file-placement
problem, not a config-list one: per-agent scope is `<workspace>/skills` and
the workspace bootstrap files; the module's `programs.openclaw.skills` is
global and no per-skill `deny` exists. Use real-file `home.activation`
copies — `home.file` symlinks into the store are silently dropped twice over
(hardlink rejection for workspace skills, symlink refusal for bootstrap
injection). The verified procedure, traps, and verification:
`per-agent-files.md`.

A custom provider declared with only `baseUrl`/`apiKey` gets `reasoning:
false`, which makes `params.thinking` a silent no-op. An explicit model entry
with `reasoning = true` is required for the setting to mean anything.

Verify the endpoint actually accepts the parameter before promising the config
works — server acceptance and client transmission are separate claims:

```sh
curl -s -m 30 --noproxy '*' "$BASE_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"<id>","messages":[{"role":"user","content":"reply ok"}],"reasoning_effort":"high"}'
```

Note that adding an explicit `models` list to a provider **replaces** whatever
the catalog previously discovered there. Say so when you do it, and ask before
removing models the user may rely on.

Completion check: the evaluated JSON shows the intended value, and the user knows
what the change does not prove.

## Gateway auth schema traps (verified 2026-10-01)

Secret-provider names must match `^[a-z][a-z0-9_-]{0,63}$` — camelCase
(`localGatewayPassword`) fails eval with "config is invalid". Passing
`gateway.auth.token` via SecretRef clears build AND JSON validation, but the
RUNTIME rejects it and the gateway crash-loops with exit 78/CONFIG — do not
retry that shape. The working scheme: `auth.mode = "trusted-proxy"` +
`trustedProxies = [ "127.0.0.1" ]` + password SecretRef with provider
`local-gateway-password` + `identityScopes`.

`codeMode.enabled`: forced `true` with a model outside the catalog-preferred
list (`xiaomi/mimo-v2.6-flash`; only mimo-v2.5 preferred) broke heredocs and
spawned model errors — use `"auto"` (commit b54e5b7) and note why in a comment.

Plugin config follows the same module and the same apply consent. For the
lossless-claw compaction threshold — where a plausible fraction silently arms
past the model's window and nothing ever compacts — see
`lossless-compaction-threshold`.

## active-memory plugin wiring (verified 2026-10-06, both hosts)

Take the accepted keys from the plugin's bundled manifest
(`openclaw.plugin.json` → `configSchema`), not prose docs: main
`plugins.entries.*` allows only `{config, enabled, hooks, llm, subagent}` —
plugin payload goes under `.config`, and a top-level `mode`/`agents` set is
rejected with "Unrecognized keys" (cost one round trip on the Mac).
`config.agents` matches **exact agent ids** — `"main"` is dead config for an
agent id `coordinator` (the plugin loaded, validated, enabled… and never fired
for the real agent; caught only by grepping gateway logs since the restart).
`rememberAcrossConversations` is NOT in the plugin schema — it lives at
`agents.entries.<id>.memory.search.rememberAcrossConversations`. Escalation
depends on lcm tools reaching the agent: `tools.alsoAllow` the four `lcm_*`
ids. Completion check: after switch+restart, gateway logs show active-memory
lines for the actual agent id (absence after a restart = wrong `agents` list,
not a silent-but-working plugin).

## Step 4 — schema may lag the runtime before you trust an eval refusal

The generated options (`nix/generated/openclaw-config-options.nix`, pinned to the
nix-openclaw input's gateway source rev) can be narrower than the gateway's own
runtime schema. Verified 2026-10-03: `tts.providers.<name>` declares only
`apiKey`, while the 2026.9.5 runtime reads `command`, `args`, `outputFormat`,
`timeoutMs`, `cwd`, `env` from `dist/speech-provider-*.mjs`. Writing the
runtime-supported keys fails eval with "The option … does not exist" even though
they are correct per the docs — check the generated options
(`getSubOptions` / grep the file) before concluding a provider block is valid,
and check the gateway dist source before concluding a key is unsupported.

The only escape hatch in the generated schema is `channels.*` — its
`freeformType = attrsOf anything` (openclaw-config-options.nix:2921) is the
single freeform block in the file, and it accepts arbitrary nested keys.
Verified 2026-10-04: `channels.telegram.tts.providers."tts-local-cli"` with
`command`/`args`/`outputFormat`/`timeoutMs` evaluates fine, lands verbatim in
the generated JSON, and the runtime (tts-local-cli plugin, docs
plugins/reference/tts-local-cli.md) reads those exact fields — so the working
pattern is: declare the provider under the channel override and set global
`tts.provider` to its id. Other passthroughs fail: redeclaring the nested
option with `freeformType` errors with `already declared`, a duplicate
top-level declaration leaves the nested leaf governed by the generated schema
(both verified 2026-10-03), no extraConfig/rawJson/prelude exists anywhere in
nix-openclaw, and regenerating at the pinned rev reproduces the gap — the
generator root cause is `generate-config-options.ts` rendering a Zod catchall
only for objects with zero declared properties, so the real fix is upstream.

