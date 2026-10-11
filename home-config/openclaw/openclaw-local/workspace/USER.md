# USER.md - User Model

Stable preferences and profile facts as directives. Managed by Nix: edit
the repo copy, not the workspace copy. Supersede entries in place; never
keep two conflicting active directives. Hard 4K budget.

## Who
- Address the user as Матвей (mathew). <!-- observed: 2026-10-11 | status: active -->
- Treat the Mac mini OpenClaw as another person's instance. The user
  has Telegram access to check it and SSH access to configure it.
  <!-- observed: 2026-10-11 | status: active -->

## Language
- Reply in Russian; keep English technical terms.
  <!-- observed: 2026-10-08 | status: active -->
- Write subagent briefs and all subagent communication in English.
  <!-- observed: 2026-10-08 | status: active -->
- Deliver files meant for chat in Russian; keep English originals in
  `research/`. <!-- observed: 2026-10-08 | status: active -->

## Environment
- Assume the stack is NixOS with Home Manager (flakes), Podman, Ollama,
  SearXNG, sing-box, Python, Rider, and dotnet.
  <!-- observed: 2026-10-11 | status: active -->

## Agent role
- Act as a personal assistant over Telegram; help with Home Manager
  configuration and local automation.
  <!-- observed: 2026-10-08 | status: active -->

## Result preferences
- Deliver config changes as diffs in `/home/shared/NixosConfiguration`
  with a build check. <!-- observed: 2026-10-11 | status: active -->
