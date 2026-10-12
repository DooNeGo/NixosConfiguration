---
name: ai-chat-bot-kb-management
description: ai-chat-bot on ai-server — rebuild/verify the airport_kb Qdrant collection, diagnose KB junk-chunk contamination, indexer pipeline facts. Same host/repo: /home/admin/configuration/chat-bot.
---

# ai-chat-bot KB management

Trigger: "rebuild the KB", "pages missing from the KB", "answers cite garbage
or duplicated chunks", or "KB needs a refresh".

Same host and repo as `ai-chat-bot-admin-access`: `ssh ai-server`
(→ `admin@100.114.127.10`), `/home/admin/configuration`, app `chat-bot/`.

## Known pitfall — KB junk-chunk contamination (verified 2026-10-02)

Symptom: answers degrade to footer snippets (`- Email: info@airport.by`)
while the top-1 URL looks correct. Cause: indexing kept template boilerplate
(menus, cookie banners, "RU EN BY CN" switchers) that exists on every crawled
page and outranks real content in the vector search. Diagnose by reading the
retrieved chunk TEXT, never the URL alone — a retrieval spot-check that
confirms only the URL can pass while the KB is effectively broken.

## KB rebuild

1. Rebuild the collection:
   `python chat-bot/scripts/index_site.py --rebuild --collection airport_kb`
   from `/home/admin/configuration`. Expected green (measured 2026-10-02):
   `added=102 chunks=187 errors=0 strict=True` in ~145 s, exit 0.
   `--rebuild` also removes the legacy collection with uuid4 duplicates
   (246 points, 6× dup ids).
2. Verify: `index_site.py --verify` → must report `points=187 distinct_ids=187
   urls=102 incomplete=0 → OK`. Then read one retrieved chunk's TEXT (not just
   the URL — the contamination pitfall above) and run one `POST /chat-stream`
   smoke question (the Step 3 curl from `ai-chat-bot-admin-access`).
3. If only part of the pipeline needs a run, the indexer
   (`chat-bot/scripts/indexer.py`) diffs by `{url, sha256}` stored in the
   Qdrant payload — unchanged pages are skipped; changed/removed are deleted
   only under strict discovery, then re-upserted with `id = uuid5(url#idx)`
   (dedup by construction).

### Pipeline facts (for debugging, not editing)

- Discovery: HTML `/sitemap/` + pagination `/press-sluzba/news/N` (sitemap.xml
  is 404 on airport.by — do not "fix" to it).
- Cleaning: drop `nav/header/footer/aside/form/cookie` and selectors
  `.popup, #footer-cookies-cont, [class*=cookie], [id*=cookie]`; content by
  priority `main, [role=main], article.list_of_sections, .page-content, #content,
  .content, .wrapper`.
- Chunking: line chunks with `INDEX_MIN_CHUNK_LEN=100` — the 21-char tail
  chunks («Пересадка в аэропорту») used to steal top-1 retrieval.
- Embedding: local Ollama `qwen3-embedding:0.6b` at `:8001`, 1024-dim, batches ≤64.
- Language gate: `KB_LANG=""` + `INDEX_ALLOW_PREFIX`/`INDEX_DENY_PREFIXES`
  using the real locale prefixes `/be`, `/en`, `/zh` (`/by` and `/cn` DO NOT
  exist as paths). `RAG_QUERY_LANG=""` so `rag.py` does not translate queries.
- Cadence: systemd timer `ai-chat-bot-index` runs daily 04:00 (Persistent).

Rebuild completion check: the `--verify` counts match the numbers above plus
one real chunk-text read; a green rebuild with wrong counts means the locale
gate or discovery changed.

## Completion check

The `--verify` counts match the expected numbers, one real chunk-text read
confirms no junk-chunk contamination, and a `POST /chat-stream` smoke
question returns a grounded answer.