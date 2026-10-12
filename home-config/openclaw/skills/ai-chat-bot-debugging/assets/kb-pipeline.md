# KB pipeline facts (airport_kb)

Debugging reference. Do not change the pipeline from a debugging session.

- Discovery: HTML `/sitemap/` plus pagination `/press-sluzba/news/N`. `sitemap.xml` returns 404 on airport.by; do not switch discovery to it.
- Cleaning: drop `nav/header/footer/aside/form/cookie` and selectors `.popup, #footer-cookies-cont, [class*=cookie], [id*=cookie]`. Content is taken by priority from `main, [role=main], article.list_of_sections, .page-content, #content, .content, .wrapper`.
- Chunking: line chunks with `INDEX_MIN_CHUNK_LEN=100`. Short tail chunks (~21 chars, e.g. «Пересадка в аэропорту») outranked real content in top-1 retrieval; keep the minimum length.
- Embedding: local Ollama `qwen3-embedding:0.6b` at `:8001`, 1024-dim, batches of at most 64.
- Language gate: `KB_LANG=""`; `INDEX_ALLOW_PREFIX` / `INDEX_DENY_PREFIXES` use the real locale prefixes `/be`, `/en`, `/zh`. `/by` and `/cn` do not exist as paths. `RAG_QUERY_LANG=""` so `rag.py` does not translate queries.
- Cadence: systemd timer `ai-chat-bot-index`, daily 04:00 (Persistent).
