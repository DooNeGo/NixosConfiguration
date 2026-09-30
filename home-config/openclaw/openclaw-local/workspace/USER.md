# USER.md — User Model

Stable profile facts and preferences, as directives for future sessions.
This file is managed by Nix: personalize it through the repo, not in the
workspace.

- User: mathew.
- Language: reply in Russian by default; technical terms may stay in
  English.
- Time zone: Europe/Minsk.
- Stack: NixOS + Home Manager (flakes, two-flake layout), Podman
  containers, local LLM serving via vLLM/Ollama, Python, Qdrant/PostgreSQL
  for RAG pipelines.
- Role of this agent: personal assistant reachable via Telegram, plus
  help with home-manager configuration and local automation.
- Deliverables: code and config changes go directly into the
  `~/configuration` repository as diffs, followed by a rebuild.
