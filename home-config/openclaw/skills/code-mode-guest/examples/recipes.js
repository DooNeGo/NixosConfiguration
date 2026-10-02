// Verified-shape examples (gateway 2026.9.5) — companion to SKILL.md "Reliable patterns".
// All return shapes live-verified 2026-10-02: exec/read/write return OBJECTS, not strings.

// 1) shell inside guest code (top-level code stays JS)
const log = await exec({ command: "git log --oneline -5", timeoutSeconds: 30 });
text(log.aggregated);                    // exec → { status, exitCode, aggregated, ... }

// 2) tool globals with normal params
const src = await read({ path: "/home/openclaw/file.txt" });
text(src.content);                       // read → { kind: "text"|"image", content, ... }
const w = await write({ path: "/tmp/out.txt", content: "hello" }); // → { changed, created, diff, patch }

// 3) remote file transfer without heredoc (base64 alphabet is quote-safe)
await write({ path: "/tmp/deploy.sh", content: script });   // local staging
await exec({ command: "scp /tmp/deploy.sh host:/path/" });
// or one-liner:
const b64 = await exec({ command: "base64 -w0 /tmp/deploy.sh" });
await exec({ command: `ssh host "echo '${b64.aggregated.trim()}' | base64 -d > /path/f"` });

// 4) background work + poll (polling in the same cell works)
const bg = await exec({ command: "nix build .#pkg --no-link", background: true, timeoutSeconds: 0 });
const p = await process({ action: "poll", sessionId: bg.sessionId, timeout: 30000 });
text(p.aggregated);
