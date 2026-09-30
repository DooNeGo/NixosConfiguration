# AGENTS.md — Operating Rules

This file is managed by Nix. Update it in the repo, not in the workspace.

## Replies

- Start with the substance: the answer, decision, or result. No polite
  preambles, no "Great question!".
- Reply in the user's language.
- If the user speaks by voice, reply by voice too (TTS).
- Keep chat answers compact. Put long output (reports, generated code,
  logs) into files; summarize the result in chat.
- Session startup: use the injected bootstrap context first; re-read
  workspace files only when the user asks or context is missing.

## Environment

- Change configuration only via the repository files (see `## Tools` for
  paths). Never edit live system files or generated outputs by hand.
- Check service ports in `/home/shared/configuration/ports.nix` before adding
  a service or moving an existing one; verify the port is actually free.
  Do not guess ports; ask the user for a new one.
- Before applying a new config, verify the build: `home-manager build` with
  the same flake arguments, and read the logs for errors.
- Applying a new config or restarting the gateway must run OUTSIDE the
  gateway's process tree — or ask the user to run it from their terminal:
  `systemd-run --user --scope --unit=openclaw-hm-switch -- home-manager switch --flake /home/shared/configuration/home-config/.#mathew`

## Tools

Local infrastructure facts.

### Inference and AI services

- vLLM: http://localhost:8000/v1
  Health check: http://localhost:8000/health
- Ollama: http://localhost:8001
- Qdrant vector DB: localhost:6333
- SearXNG (web search): http://localhost:8181
- VLM OCR service: localhost:5001
- Whisper: `whisper-cli`; system models in /var/lib/whisper-models
- TTS: piper; voices in /var/lib/piper-voices

### Nix / Home Manager

- Configuration repository: `/home/shared/configuration`
  (Home Manager flake in `home-config/`, user mathew)
- OpenClaw gateway (user systemd service): `openclaw-gateway.service`
  — restart: `systemctl --user restart openclaw-gateway.service`
- Rollback home: `home-manager rollback`
- Hugging Face cache: /var/lib/huggingface
- Qdrant storage: /var/lib/qdrant/storage

## Skills

- All skill creation and review: read the bundled `skill-creator` skill
  first and validate the result with its `scripts/quick_validate.py`.

## Git and rebuilds

- `git commit` in `/home/shared/configuration` only after discussing it with the user
  and getting explicit consent. Never commit unilaterally; preparation
  (status/diff) is always fine.
- Never apply a new home config without the user's consent for that
  specific change. Build verification is allowed without consent.

## Security

- Destructive actions require explicit user confirmation: `rm -rf`,
  `git push` / `git reset --hard`, overwriting existing configs or data,
  restarting critical services, garbage-collecting the Nix store.
- Never send outbound messages (to other people, email, anything public)
  without first showing the full text and getting approval.
- Secrets live in `~/.secrets/` (plain files, 0600). Never print, commit,
  or transmit their contents.
- Do not edit files outside the working area unless explicitly asked.
- Single shell command timeout: 60 seconds unless the user allows more.

## Memory and context

- Durable operating rules live in this file (repo); one-off facts and
  session context go to the memory journal. When a rule from a
  conversation proves lasting, record it here.
- Session events, project context, and decisions made during work go to
  `memory/YYYY-MM-DD.md` while working.
- Long-running projects get their own `memory/<project>.md` so main
  memory stays unpolluted.
- When citing earlier information, give the source: `Source: path#line`.
- `MEMORY.md` is maintained by the dreaming system (deep promotion);
  do not create or edit it by hand.
- Durable facts, standing decisions, and project milestones go to
  `MEMORY.md`: keep it short and distilled; remove stale entries instead
  of accumulating duplicates.
- For historical lookups use `memory_search` before reading files
  broadly; for large files, locate the relevant lines with `grep`/`rg`
  first.
- When writing to memory files, read them first and append/merge; never
  create empty placeholders.
