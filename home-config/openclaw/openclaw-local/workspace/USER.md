# USER.md — User Model

Stable profile facts and preferences, as directives for future sessions.
This file is managed by Nix: personalize it through the repo, not in the
workspace.

- User: mathew.
- Language: reply in Russian by default; technical terms may stay in
  English.
- Agent delegation: task briefs and all communication with subagents
  (coder, worker spawns) are written in English; user-facing chat stays
  Russian.
- Deliverables to chat: research/deliverable files sent to the user are in
  the user's language (Russian); English originals stay in research/.
- Time zone: Europe/Minsk.
- Stack: NixOS + Home Manager (flakes, two-flake layout), Podman
  containers, local LLM serving via vLLM/Ollama, Python, Qdrant/PostgreSQL
  for RAG pipelines.
- Role of this agent: personal assistant reachable via Telegram, plus
  help with home-manager configuration and local automation.
- Deliverables: code and config changes go directly into the
  `~/configuration` repository as diffs, followed by a rebuild.
