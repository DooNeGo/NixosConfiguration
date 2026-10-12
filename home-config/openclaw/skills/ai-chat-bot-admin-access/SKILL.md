---
name: ai-chat-bot-admin-access
description: ai-chat-bot on ai-server — service status, last request via admin /logs, reproduce failing request. Bot lives in /home/admin/configuration/chat-bot, unit ai-chat-bot.service, port 5000.
---

# ai-chat-bot admin access

Trigger: the user reports a wrong/empty bot answer or asks what the last
request to the bot was.

Bot lives in `/home/admin/configuration/chat-bot` on ai-server (ssh alias
`ai-server`), unit `ai-chat-bot.service`, port 5000.

## Step 1 — service status, and where the request log is NOT

`systemctl status ai-chat-bot` — the service runs from a Nix store path
(`WorkingDirectory=/nix/store/<hash>-ai-chat-bot-app`). Note the start time:
on-disk edits reach the running service only via a rebuild/switch. Confirm
which code is live by grepping the store copy for your marker, e.g.
`grep -c TRANSPORT_LIVE_CONTEXT /nix/store/<hash>-ai-chat-bot-app/app.py`.

`journalctl -u ai-chat-bot` carries only start/stop lines and a benign
PostgreSQL collation version-mismatch warning — **no request logs at all**.
Do not hunt requests there.

## Step 2 — read the last requests via the admin route

The verified path is the admin UI. DB credentials are masked `***` in
`systemctl cat` output, and `sudo -u postgres psql` needs a TTY — do not plan
around either:

```sh
ssh ai-server 'cd /tmp && curl -s -c c.txt \
  -d "password=$PW" http://localhost:5000/admin -o /dev/null -w "login:%{http_code}\n" \
  && curl -s -b c.txt "http://localhost:5000/logs?page=1" -o logs.html'
```

`$PW` is `ADMIN_PASSWORD` from `systemctl cat ai-chat-bot` — read it into the
variable; never echo, store, or paste the value. `login:302` then `logs:200`
means success.

`GET /logs?page=1` is newest-first, 350 rows per page. Rows are HTML; strip
tags for reading, e.g. `sed -n "s/<[^>]*>/|/gp" logs.html | tr -s "|"` — each
row is time (Europe/Minsk), IP, user-agent, question, then `[topic]` plus the
full answer. Handlers: `app.py` `/admin`/`/logs`; backing table `chatlog`
(`db.py`) if direct DB access is ever needed.

## Step 3 — reproduce and inspect retrieval

Reproduce the failing request without the frontend:

```sh
curl -s -m 60 -X POST http://localhost:5000/chat-stream \
  -H 'Content-Type: application/json' \
  -d '{"history":[{"role":"user","content":"<question>"}]}'
```

To see the context the answer was built from, run the repo's
`rag.build_context(...)` with the store-env interpreter (non-interactive ssh
PATH lacks python3 — see `remote-nixos-host-path` Branch 3; the unit's
ExecStart names the exact interpreter). Print the top chunks and read their
text.

## Completion check

The last request is identified with question/topic/answer, the root cause is
reproduced with evidence (log row plus retrieval or code-level proof), and the
user knows what changed and what still needs a restart or their switch.