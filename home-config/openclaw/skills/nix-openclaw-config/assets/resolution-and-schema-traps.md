# Resolution order, gateway auth, active-memory, schema-lag traps

## Step 3 — know the resolution order before adding a default

For thinking and reasoning, later config does not override earlier config. A
per-agent `thinkingDefault` beats a per-model `params.thinking`, so a
redundant-looking agent setting silently defeats a per-model one. Check the
existing agent entries before assuming a per-model default takes effect.

Adding entries to `agents.defaults.models` has a second side effect. With no
explicit `modelPolicy.allow`, the gateway treats the **keys** of that block as the
model allowlist, so the first `params.*` entry silently forbids every other model
for subagent spawns (`sessions_spawn` fails with `model not allowed: <model>`
for worker and coder alike). Fix it inside `agents.defaults`:

```nix
modelPolicy.allow = [ "openrouter/*" "vllm/*" ];
```

Wildcard refs are supported. Include every model you rely on (the coordinator's
primary, the heartbeat/vLLM model), or those paths break the same way.

Before relying on any provider model id, check it with a trivial spawn
(`model: "<id>"`, task "Reply with exactly: OK", no tools). A wrong id fails fast
with "model not found" and costs seconds, not a real run. Ids must match the
provider slug exactly: an `~`-prefixed form (`~xiaomi/mimo-v2.6-flash`) fails
provider lookup where the plain `openrouter/xiaomi/mimo-v2.6-flash` works. A cheap
pre-filter is `GET https://openrouter.ai/api/v1/models` (no key), which confirms
the slug exists; only a trivial spawn proves the key and balance work. Then
verify by building the openclaw user's activation package and grepping the
generated `openclaw.json` for `modelPolicy`, then the usual switch and gateway restart.

Tools policy: agents governed by a `tools.allow` list get **no** `tools.deny`.
The allow list already hides everything else, so denies there are dead config.
Write `deny` only for deny-list agents (e.g. the coordinator keeps a deny list and
no allow list). When touching tools policy: `deny` wins over `allow`; `allow` and
`alsoAllow` cannot coexist in one scope; and `write`, `edit`, `apply_patch` are
separate tool ids, so denying `write` alone does not block file mutation (deny
`group:fs` instead).

Per-agent `skills` lists follow the docs (`config-agents/workspace-and-bootstrap`):
a non-empty list is the final set (no merge with defaults), `[]` means no skills,
and unset means unrestricted. An allowlisted skill stays invisible to the agent
until `home-manager switch`, and even then only for new sessions. Adding a skill
to an agent's allowlist is the owner's decision; keep an agent's list strict and
do not add skills as a side effect of related work. When a run must follow skill
rules before the allowlist and switch land, inline the rules into the task brief.

There is NO per-agent denylist. The filter is exact-match `baseFilter.includes(skillName)`,
the zod schema is `strict()`, and the option type is `nullOr (listOf str)`. The only
deny is GLOBAL `skills.entries.<key>.enabled = false`, which hides the skill for
every agent (it is checked before agent filters) and cannot be scoped per agent.
Place the deny map INSIDE the gateway `config` attrset (`config.skills.entries = …`),
not at the module level: `programs.openclaw.skills` is the skill-registration list,
so a module-level `skills.entries` collides with it and fails eval with a duplicate
attribute error. Take exact keys from `openclaw skills list --json`; an invented key
(e.g. `onepassword` for `1password`) silently denies nothing. Bundled and plugin
skills reach an allowlisted agent only via an allowlist line, so revise the list at
each `nix-openclaw` bump. Do not chase allow/deny object forms or glob patterns:
`"-*"` is a literal name that matches nothing.

Distributing a skill or persona file to ONE agent is a file-placement problem, not
a config-list one. Per-agent scope is `<workspace>/skills` and the workspace
bootstrap files. Use real-file `home.activation` copies: `home.file` symlinks into
the store are silently dropped twice over (hardlink rejection for workspace skills,
symlink refusal for bootstrap injection). Procedure and traps: `per-agent-files.md`.

A custom provider declared with only `baseUrl`/`apiKey` gets `reasoning: false`,
which makes `params.thinking` a silent no-op. An explicit model entry with
`reasoning = true` is required for the setting to mean anything.

Verify the endpoint accepts the parameter before promising the config works.
Server acceptance and client transmission are separate claims:

```sh
curl -s -m 30 --noproxy '*' "$BASE_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"<id>","messages":[{"role":"user","content":"reply ok"}],"reasoning_effort":"high"}'
```

Adding an explicit `models` list to a provider **replaces** whatever the catalog
previously discovered there. Say so when you do it, and ask before removing
models the owner may rely on.

Completion check: the evaluated JSON shows the intended value, and you state what
the change does not prove.

## Gateway auth schema traps

Secret-provider names must match `^[a-z][a-z0-9_-]{0,63}$`. camelCase
(`localGatewayPassword`) fails eval with "config is invalid". Passing
`gateway.auth.token` via SecretRef clears build and JSON validation, but the
runtime rejects it and the gateway crash-loops with exit 78/CONFIG. Do not retry
that shape. The working scheme: `auth.mode = "trusted-proxy"` +
`trustedProxies = [ "127.0.0.1" ]` + password SecretRef with provider
`local-gateway-password` + `identityScopes`.

`codeMode.enabled`: forced `true` with a model outside the catalog-preferred list
broke heredocs and spawned model errors. Use `"auto"`, and record the reason in a
Nix comment.

Plugin config follows the same module and the same apply consent. For the
lossless-claw compaction threshold, where a plausible fraction silently arms past
the model's window and nothing ever compacts, see `lossless-compaction-threshold`.

## active-memory plugin wiring

Take the accepted keys from the plugin's bundled manifest (`openclaw.plugin.json`
→ `configSchema`), not prose docs. Main `plugins.entries.*` allows only
`{config, enabled, hooks, llm, subagent}`: plugin payload goes under `.config`, and
a top-level `mode` or `agents` set is rejected with "Unrecognized keys".
`config.agents` matches **exact agent ids**. `"main"` is dead config for an agent
id `coordinator`: the plugin loads, validates and enables, and never fires for the
real agent. Only the gateway logs show it. `rememberAcrossConversations` is NOT in
the plugin schema; it lives at `agents.entries.<id>.memory.search.rememberAcrossConversations`.
Escalation depends on the lcm tools reaching the agent: `tools.alsoAllow` the four
`lcm_*` ids. Completion check: after switch and restart, gateway logs show
active-memory lines for the actual agent id. Absence after a restart means a wrong
`agents` list, not a silent-but-working plugin.

## Step 4 — schema may lag the runtime before you trust an eval refusal

The generated options (`nix/generated/openclaw-config-options.nix`, pinned to the
nix-openclaw input's gateway source rev) can be narrower than the gateway's own
runtime schema. Example: the generated `tts.providers.<name>` declares only
`apiKey`, while the runtime reads `command`, `args`, `outputFormat`, `timeoutMs`,
`cwd` and `env` from `dist/speech-provider-*.mjs`. Writing the runtime-supported
keys then fails eval with "The option … does not exist", even though they are
correct per the docs. Check the generated options (`getSubOptions`, or grep the
file) before concluding a provider block is invalid, and check the gateway dist
source before concluding a key is unsupported.

The only escape hatch in the generated schema is `channels.*`: its
`freeformType = attrsOf anything` is the single freeform block in the file and
accepts arbitrary nested keys. The working pattern: declare the provider under the
channel override (`channels.telegram.tts.providers."tts-local-cli"` with
`command`/`args`/`outputFormat`/`timeoutMs`), which evaluates, lands verbatim in the
generated JSON, and is read by the runtime plugin. Then set global `tts.provider`
to its id. Other passthroughs fail. Redeclaring the nested option with
`freeformType` errors with `already declared`, and a duplicate top-level declaration
leaves the nested leaf governed by the generated schema. No extraConfig, rawJson or
prelude exists in nix-openclaw. Regenerating at the pinned rev reproduces the gap:
the generator renders a Zod catchall only for objects with zero declared properties,
so the real fix is upstream.
