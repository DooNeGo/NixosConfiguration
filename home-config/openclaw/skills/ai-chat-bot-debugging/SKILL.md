---
name: ai-chat-bot-debugging
description: ai-chat-bot on ai-server misbehaves - last request via admin /logs, off_topic refusals, junk KB chunks, airport_kb rebuild.
---

# Debug ai-chat-bot on ai-server

Trigger: the user reports a wrong, empty, or refused bot answer, or asks what the last request to the bot was. Bot lives in `/home/admin/configuration/chat-bot` on ai-server (ssh alias `ai-server`), unit `ai-chat-bot.service`, port 5000, Qdrant collection from env `QDRANT_COLLECTION`.

## Step 1 — service status, and where the request log is NOT

`systemctl status ai-chat-bot` — the service runs from a Nix store path (`WorkingDirectory=/nix/store/<hash>-ai-chat-bot-app`). Note the start time: on-disk edits reach the running service only via a rebuild/switch. Confirm which code is live by grepping the store copy for your marker, e.g. `grep -c TRANSPORT_LIVE_CONTEXT /nix/store/<hash>-ai-chat-bot-app/app.py`.

`journalctl -u ai-chat-bot` carries only start/stop lines and a benign PostgreSQL collation version-mismatch warning — **no request logs at all**. Do not hunt requests there.

## Step 2 — read the last requests via the admin route

The verified path is the admin UI. DB credentials are masked `***` in `systemctl cat` output, and `sudo -u postgres psql` needs a TTY — do not plan around either:

```sh
ssh ai-server 'cd /tmp && curl -s -c c.txt \
  -d "password=$PW" http://localhost:5000/admin -o /dev/null -w "login:%{http_code}\n" \
  && curl -s -b c.txt "http://localhost:5000/logs?page=1" -o logs.html'
```

`$PW` is `ADMIN_PASSWORD` from `systemctl cat ai-chat-bot` — read it into the variable; never echo, store, or paste the value. `login:302` then `logs:200` means success.

`GET /logs?page=1` is newest-first, 350 rows per page. Rows are HTML; strip tags for reading, e.g. `sed -n "s/<[^>]*>/|/gp" logs.html | tr -s "|"` — each row is time (Europe/Minsk), IP, user-agent, question, then `[topic]` plus the full answer. Handlers: `app.py` `/admin`/`/logs`; backing table `chatlog` (`db.py`) if direct DB access is ever needed.

## Step 3 — reproduce and inspect retrieval

Reproduce the failing request without the frontend:

```sh
curl -s -m 60 -X POST http://localhost:5000/chat-stream \
  -H 'Content-Type: application/json' \
  -d '{"history":[{"role":"user","content":"<question>"}]}'
```

To see the context the answer was built from, run the repo's `rag.build_context(...)` with the store-env interpreter named in the unit's ExecStart. Non-interactive ssh PATH lacks python3; follow `assets/remote-host-path.md`. Print the top chunks and read their text.

## Step 4 — classify the failure

- **Refusal or `off_topic` on an in-topic message** (no airport keywords, often a follow-up): classifier context problem, not missing keywords. Fix: pass the last two user questions to `classify_topic`. Placement rules, the refusal-branch cost, and the composition rule are in `assets/classifier.md`.
- **Answer degrades to footer snippets** (e.g. `- Email: info@airport.by`) while the top-1 URL looks right: junk-chunk contamination. Template boilerplate (menus, cookie banners, language switchers) outranks real content. Diagnose by reading the retrieved chunk TEXT, never the URL alone — a check that confirms only the URL can pass while the KB is broken. Fix with the KB steps below; pipeline facts are in `assets/kb-pipeline.md`.

## Step 5 — KB rebuild (airport_kb)

Trigger: "rebuild the KB", "pages missing from the KB", "answers cite garbage or duplicated chunks", or "KB needs a refresh". Run from `/home/admin/configuration` on ai-server.

1. **Stop and confirm with the coordinator before the rebuild command.** `--rebuild` deletes the legacy collection, so do not run it without that confirmation.
2. Rebuild: `python chat-bot/scripts/index_site.py --rebuild --collection airport_kb`. Expected green output: `added=102 chunks=187 errors=0 strict=True` in ~145 s, exit 0.
3. Verify: `index_site.py --verify` must report `points=187 distinct_ids=187 urls=102 incomplete=0 → OK`. Then read one retrieved chunk's TEXT (Step 4 contamination check) and run one `POST /chat-stream` smoke question (the Step 3 curl). A green rebuild with wrong counts means the locale gate or discovery changed; see `assets/kb-pipeline.md`.
4. Partial refresh: the indexer (`chat-bot/scripts/indexer.py`) diffs by `{url, sha256}` stored in the Qdrant payload. Unchanged pages are skipped; changed or removed pages are deleted only under strict discovery, then re-upserted with `id = uuid5(url#idx)`.

## Completion check

The last request is identified with question/topic/answer; the root cause is reproduced with evidence (log row plus retrieval or code-level proof); for KB work, the `--verify` counts match and one chunk-text read shows no contamination. The user knows what changed and what still needs a restart or their switch.
