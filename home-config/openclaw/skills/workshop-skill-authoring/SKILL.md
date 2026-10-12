---
name: workshop-skill-authoring
description: Create or update coordinator skills via skill_workshop — 160-byte description cap, patch rejected for unused skills, update+apply route.
---

# Author and update skills via skill_workshop

Trigger: a skill-mining or review pass needs a new skill or a change to an
existing one. Use the `skill_workshop` tool; never edit Workshop files outside
an authorized maintenance run.

## Hard limits and the one route that works

- `description` is capped at **160 bytes** — a longer one fails the create with
  "description is too large" and nothing is staged. Count before submitting.
- **`action=patch` on a skill that was not used in this run is rejected**
  ("skill was not used in this run and cannot be repaired autonomously" —
  verified 2026-10-06, four rejections). The working route for an unused
  skill: `read` it, then `action=update` with the complete final body
  (proposal_content), then `apply` the returned proposal id. A targeted
  `patch` works only on a skill already exercised in the run.
- `update`/`create` stage a **pending proposal**; nothing changes until
  `action=apply` with the proposal id. `apply` requires an explicit user ask
  or an autonomous-mode authorization; without it, leave the proposal pending
  and say so.
- When revising a proposal, re-emit the **complete** final body —
  proposal_content is never a plan or diff.

## Authoring standards

Structure, triggers, steps, and completion criteria: follow the bundled
`skill-creator` skill (read-only, gateway-bundled) — this skill covers only the
skill_workshop tool mechanics below.

## Verification

After apply, the change is live: `action=list` (or a fresh `read`) shows the
new body. Completion check: the proposal status is `applied`, and a re-read
returns the updated text.