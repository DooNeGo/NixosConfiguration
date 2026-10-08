# USER.md — User Model

Stable profile facts and preferences, as directives for future sessions.
This file is managed by Nix: personalize it through the repo, not in the
workspace.
Directive format: each fact may carry `<!-- observed: YYYY-MM-DD |
status: active -->`; supersede in place — never stack conflicting
directives (hard 4K budget; history goes to memory diaries).

- User: mathew. <!-- observed: 2026-10-08 | status: active -->
- Language: reply in Russian by default; technical terms may stay in
  English. <!-- observed: 2026-10-08 | status: active -->
- Agent delegation: task briefs and all communication with subagents
  (coder, worker spawns) are written in English; user-facing chat stays
  Russian. <!-- observed: 2026-10-08 | status: active -->
- Deliverables to chat: research/deliverable files sent to the user are in
  the user's language (Russian); English originals stay in research/.
  <!-- observed: 2026-10-08 | status: active -->
- Stack: NixOS + Home Manager (flakes, two-flake layout), Podman
  containers, local LLM serving via vLLM/Ollama, Python, Qdrant/PostgreSQL
  for RAG pipelines. <!-- observed: 2026-10-08 | status: active -->
- Role of this agent: personal assistant reachable via Telegram, plus
  help with home-manager configuration and local automation.
  <!-- observed: 2026-10-08 | status: active -->
- Deliverables: code and config changes go directly into the
  `/home/shared/NixosConfiguration` repository as diffs, followed by a
  rebuild.
  <!-- observed: 2026-10-08 | status: active; supersedes ~/configuration -->
- Delegation: all substantive tasks are delegated to subagents;
  coordinator stays free for intake, orchestration and verification.
  <!-- observed: 2026-10-08 | status: active -->
