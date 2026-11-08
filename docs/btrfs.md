# btrfs runbook (single NVMe filesystem, subvolumes `@root @home @nix @games @log @nocow`)

State of the filesystem and the reasoning behind each knob. Commands marked `sudo` are for the owner; the
agent user has no root.

## Settings in this repo

| What | Where | Why |
|---|---|---|
| `compress-force=zstd:-1,noatime` | `system-config/file-systems.nix` | -1 keeps NVMe speed (owner's benchmarks: ~4x faster than zstd:1 in a ramdisk); `-force` because the plain-compress heuristic leaves compressible data uncompressed, see section 4. Only NEW writes are affected. |
| `periodic_reclaim` + `dynamic_reclaim` | tmpfiles in `file-systems.nix` | returns half-empty data chunks to unallocated space automatically (kernel >= 6.11) |
| `services.fstrim` off | `file-systems.nix` | `discard=async` already trims freed extents |
| bees dedup | `system-config/bees.nix` (import commented out) | expected gain small and the cost permanent, see section 2 |
| btrbk snapshots + backup to the HDD | `system-config/backup.nix` | see "Backups" |

Watch reclaim: `grep . /sys/fs/btrfs/*/allocation/data/{reclaim_count,reclaim_bytes,reclaim_errors}`.
Undo: write `0` into `periodic_reclaim` and `dynamic_reclaim` there.

## 0. Baseline

Measured 2026-11-07 on the whole filesystem (top-level mounted):

| compsize | Disk usage | Uncompressed | Referenced |
|---|---|---|---|
| TOTAL | 1.5T (91%) | 1.7T | 2.1T |
| none | 1.4T | 1.4T | 1.7T |
| zstd | 93G (39%) | 238G | 388G |

`btrfs filesystem usage`: 1.86 TiB device, 1.58 TiB used, 281 GiB free, 102 GiB unallocated, data chunks 90% full.

- The NVMe has **1.7 TB of unique data uncompressed**; this is the number bees' hash table is sized from.
- `Referenced` (2.1T) > `Uncompressed` (1.7T): about 0.4 TB of data is already referenced more than once
  (reflinks or an earlier dedup). Whoever rewrites those files copies them.
- 1.4 TB is stored without compression: games (already-compressed archives, which the btrfs heuristic skips).

Re-measure (the agent has no root):

```sh
sudo compsize -x / /home /nix /games
sudo btrfs filesystem usage /
```

`btrfs filesystem du -s /home` also walks everything mounted below it: with the top-level subvolume mounted at
`~/mnt` it counts the whole filesystem (this is why `/home` showed 1.77 TiB). Unmount it first or give explicit
paths: `sudo btrfs filesystem du -s /home/mathew/Documents ...`.

## 1. Recompress existing data (defrag)

`balance` does not compress or deduplicate anything, it only moves chunks. Recompressing old data needs
`btrfs filesystem defragment -czstd -L -1`, wrapped by `scripts/btrfs-recompress.sh`.

What to expect on this machine: 1.4 TB are stored uncompressed, almost all of it game data. A `zstd -1` estimate of
`/games/SteamLibrary/steamapps/common` (`scripts/btrfs-compress-estimate.sh`, no writes) says 1146 GiB would become
981 GiB, and 102 of the 165 GiB saved come from four games (The Finals, World of Tanks, Phasmophobia, Control);
most others compress to 90-99%. Part of the data is already stored compressed, so the real saving is smaller;
compare with `sudo compsize -x <dir>`.

### Whole disk

```sh
scripts/btrfs-recompress.sh /games /home            # dry run: prints the work units (~200 for /games)
sudo scripts/btrfs-recompress.sh --run --min-free-gib 100 /games /home
```

- Every PATH is cut into units of at most `--max-unit-gib` (default 25 GiB): a bigger directory becomes its own
  files plus its subdirectories, recursively. Free space is checked before every unit (before every file for the
  files of a big directory); below `--min-free-gib` the run stops and can be repeated: finished units are listed in
  `/var/tmp/btrfs-recompress.done`.
- Nested subvolumes and other mounts are never entered, so `~/mnt` (top-level mount), `/var/lib/nocow`, the
  podman layers, `/nix` and `/var/log` stay as they are. Leave `/nix` (read-only store, hard-linked by
  `nix.optimise`), `@nocow` (NOCOW files are not compressed) and `@log` (NOCOW journals) out; `/` (`@root`) is small
  and can be added as one more PATH.
- Cost: it reads and rewrites ~1.7 TB at idle IO priority, so expect several hours and about 1.7 TB of NVMe
  writes (check `sudo smartctl -a /dev/nvme0n1` for the wear indicator before and after).
- A failed defragment (ENOSPC) leaves the data intact.

### Space

defragment **breaks reflinks**: shared data (reflinked copies, container layers, dedup) is copied. What is shared
inside the paths to be processed is what can grow: `btrfs filesystem du` reports 15.8 GiB shared in `/games` and
5.2 GiB in `/nix`; the ~0.4 TB gap between `Referenced` and `Uncompressed` in `compsize` most likely sits in nested
subvolumes (podman layers), which defragment does not enter. `/home` is not measured yet: unmount `~/mnt` (it makes
`btrfs filesystem du -s /home` count the whole filesystem) and run `sudo btrfs filesystem du -s /home` first.

- run it **before the backups are enabled**: an existing snapshot keeps the old copies, so every rewritten file
  would be stored twice until the snapshots expire.
- re-run `sudo compsize -x /games /home` afterwards and compare with the baseline.

To process only the worthwhile games instead of everything, pass their directories:

```sh
sudo scripts/btrfs-recompress.sh --run --min-free-gib 100 "/games/SteamLibrary/steamapps/common/The Finals"
```

## 2. bees (deduplication) - disabled

`system-config/bees.nix` is written but its import in `configuration.nix` is commented out. Reasons (measured
2026-11-07):

- `jdupes -r -m -X size+:1M /games` found 3003 duplicate files in 1227 sets occupying ~15 GB, i.e. about 1% of
  1.4 TB. `btrfs filesystem du` reports ~15.8 GiB as shared in `/games`, similar to the size of the duplicates,
  so many of them are probably already shared; this is inferred from the two totals, not checked per file.
  (Whole-file duplicates only; bees also finds partial ones, which games may or may not have.)
- the nix store is already deduplicated by `nix.optimise` (hard links).
- the cost is permanent: a first pass that reads 1.7 TB, a 1 GB locked hash table, constant background IO, extra
  metadata whenever snapshots exist (`@home` is snapshotted every 10 minutes), and defragment (section 1) undoes
  what it did.

Enable it only if a measurement on `@home` shows a real gain: uncomment the import, `nixos-rebuild switch`, and
compare `sudo btrfs filesystem usage /` before and after the first pass.

```sh
sudo systemctl status beesd@nixos
journalctl -u beesd@nixos -f
sudo cat /run/bees/*.status                   # scan progress, hash table fill
sudo systemctl stop beesd@nixos               # stop any time
```

Hash table: 1024 MB, see the comment in `bees.nix` (upstream: 2-4x the plain-filesystem size for compressed
data, counted on uncompressed volume: 1.7 TB here). A full `btrfs balance` invalidates the table (stop bees, delete
`.beeshome/beeshash.dat` on the top-level subvolume). `@nocow` files have no checksums and are skipped.

## 4. Measurements after recompressing (2026-11-07/08)

All with `sudo compsize -x`; "Disk" is what is stored, "Uncomp." the same data without compression.

| Scope | Disk | Uncomp. | Not compressed | Note |
|---|---|---|---|---|
| `/games /home /` (after the defrag of section 1) | 1.1T (86%) | 1.3T | 971G | zstd part: 215G from 396G |
| `/home` | 112G (68%) | 164G | 79G | zstd part: 32G from 84G (38%) |
| `/nix` before | 213G (83%) | 254G | 188G | |
| `/nix` after | 158G (62%) | 254G | 92G | extents 893k -> 1.79M |

- `/nix/store` is mounted read-only, so defragment reached it through the top-level subvolume:
  `sudo btrfs filesystem defragment -r -czstd -L -1 -t 128M ~/mnt/@nix/store`. It saved 55G (estimate: 65-80G);
  `Uncompressed` and `Referenced` did not change, so hard links stayed shared. The extent count doubles because a
  compressed extent holds at most 128K. The gain erodes as the store turns over: new paths are written by the
  mount option, not by defragment.
- Per game (already compressed by the defrag): Proton and SteamLinuxRuntime ~47%, Phasmophobia 52%, Subnautica 64%,
  The Finals 68%, Control 70%; Forza, Sea of Thieves, Hogwarts Legacy, Kingdom Come, R6 Siege, World of Tanks Blitz
  stay at 96-99%. Little is left to gain in `/games`.

### compress vs compress-force

`scripts/btrfs-compress-force-test.sh` stages a game in tmpfs, remounts the whole filesystem (btrfs compression
options are shared by all subvolumes) with each option, writes the game to `/home` and records time and size
(`--report` rebuilds the tables from the CSV). Single runs, so differences below ~15% are noise; the source is in
RAM, reads and decompression were not measured.

| Phasmophobia, 20 GiB | on disk | write speed, 1 writer |
|---|---|---|
| no compression | 20.0 GiB | 3.1 GiB/s |
| `compress=zstd:-1` | 14.3 GiB (71%) | 3.3 GiB/s |
| `compress-force=zstd:-1` | 11.0 GiB (54%) | 2.8 GiB/s |
| `compress-force=zstd:-3` | 11.6 GiB (57%) | 3.1 GiB/s |
| `compress-force=zstd:1` | 10.1 GiB (50%) | 2.3 GiB/s |
| `compress-force=zstd:2` | 9.9 GiB (49%) | 2.1 GiB/s |
| `compress-force=zstd:-6 / -9 / -12 / -15` | 61% / 65% / 70% / 75% | 3.2 / 3.2 / 2.7 / 2.5 GiB/s |

- Plain `compress` keeps 68-72% (-2 .. 2) and 82-94% at -3 .. -15: the heuristic skips a file whose first extent does
  not shrink, so compressible data stays uncompressed. `compress-force` stores about 3 GiB less on this game.
- World of Tanks Blitz (incompressible): every `compress` is 100%; `compress-force` at -1/-2 is 99% at the speed of
  no compression, at 1/2 it is 96% but 70-100% slower. So forcing only costs time at the higher levels.
- Faster levels than -1 give a worse ratio without a faster write (the disk is the limit); levels 1 and 2 cost
  20-30% of the write time for 1 GiB more.
- The number of parallel writers (1, 3, 6) made no stable difference: one `cp` already keeps the compression
  workers (`thread_pool`, default min(CPUs+2, 8)) busy.

Decision: `compress-force=zstd:-1`.
