# btrfs runbook (single NVMe filesystem, subvolumes `@root @home @nix @games @log @nocow`)

State of the filesystem and the reasoning behind each knob. Commands marked `sudo` are for the owner; the
agent user has no root.

## Settings in this repo

| What | Where | Why |
|---|---|---|
| `compress-force=zstd:-1,noatime` | `system-config/file-systems.nix` | -1 keeps NVMe speed (owner's benchmarks: ~4x faster than zstd:1 in a ramdisk); `-force` because the plain-compress heuristic leaves compressible data uncompressed, see section 4. Only NEW writes are affected. |
| `periodic_reclaim` + `dynamic_reclaim` | `file-systems.nix`: `boot.kernel.sysfs` for the NVMe, `btrfs-reclaim-backup.service` at mount time for the HDD | returns half-empty data chunks to unallocated space automatically (kernel >= 6.11) |
| `services.fstrim` off | `file-systems.nix` | `discard=async` already trims freed extents |
| bees dedup | `system-config/bees.nix` (import commented out) | expected gain small and the cost permanent, see section 2 |
| btrbk snapshots + backup to the HDD | `system-config/backup.nix` | see "Backups" |
| `compress-force=zstd:5` on `/backup`, monthly scrub | `file-systems.nix` | the HDD is the bottleneck, so a higher level is free; see section 5 |
| `nofail,x-systemd.device-timeout=10s` on `/games`, `/var/lib/nocow`, `/backup`; `x-systemd.automount` on `/backup` only | `file-systems.nix` | mounts the system can run without: a missing disk does not stop the boot and is given up on after 10 s. Only the HDD is an automount (mounted on first access, so a disk that shows up later needs no manual mount); for subvolumes of the system disk that buys nothing and tmpfiles rules would stop applying |
| `mountDirs` | `file-systems.nix`, `backup.nix` | directories and permissions applied by a service each time a mount comes up (`/backup` 0700, `/backup/btrbk`): tmpfiles skips automount points and must never create these paths on the NVMe root |

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

## 3. Backups (btrbk to the HDD)

Implemented in `system-config/backup.nix` (the `/backup` mount itself is in `file-systems.nix`). Backed up: `@home` (instance `home`) and `@root` (instance
`system`). The NVMe top-level subvolume is mounted at
`/mnt/btrfs-top` (btrbk's working volume, `.snapshots` lives there); the backup disk is `sda4` (btrfs, label
`games_arch`, UUID `66a4672a-...`, HDD) mounted at `/backup`.

### Where the backups live

`/backup`, next to `/games`: both are permanent data mounts of this machine. `/mnt` is the FHS place for
temporary mounts, which is why only the technical top-level mount (`/mnt/btrfs-top`) is there. Games stay on the
NVMe: `sda4` is a 7200 rpm disk (slow loading) and only 800 GB, and mixing games into the backup filesystem would
let them compete for the space retention needs.

### How the data is backed up

1. **Snapshot.** btrbk takes a read-only snapshot of `@home` into `/mnt/btrfs-top/.snapshots/@home.<time>`. It is
   instant and takes no space at first: it shares all blocks with the live `@home`. Later, every block you
   overwrite or delete stays pinned by the snapshot, so a snapshot costs exactly what changed since it was taken.
2. **Incremental send.** `btrfs send` compares the new snapshot with the previous one that is on the HDD and
   streams only the difference to `btrfs receive` on `/backup/btrbk`. The first transfer is a full copy; after
   that a run moves only what changed. The result on the HDD is again a read-only subvolume you can browse as
   plain files, compressed with the HDD's own `compress-force=zstd:5` (section 5).
3. **Retention.** btrbk deletes snapshots that no longer fit the policy, locally and on the HDD. It always keeps the
   newest snapshot that exists on both sides (the "latest pair"), because the next incremental send needs it as
   the parent.

Example, a Tuesday around noon: 10-minute snapshots from 10:00 to 12:00 exist locally; the HDD has about one snapshot per hour for the last day, then one per day for 14 days, one per week for
8 weeks and one per month for 6 months. A file deleted by mistake at 11:40 is in a local snapshot (copy it back); one deleted three weeks ago is
only on the HDD.

### What is backed up

| Subvolume | Instance | Snapshot | Local keep | HDD keep |
|---|---|---|---|---|
| `@home` | `home` | every 10 min if changed | 2 h | 24h 14d 8w 6m |
| `@root` | `system` | daily 04:05 if changed | 2 days | 14d 8w 6m |

Not backed up: `@games`, `@nix` (reproducible), `@log`, `@nocow`. Two instances because `@home` is snapshotted
often and `@root` (little changes there) once a day.

Nested subvolumes are **not** part of a snapshot of their parent (they show up as empty directories). Inside `@root`
there are `/var/lib/machines`, `/var/lib/portables`, `/var/tmp` and `/srv` (created by systemd-tmpfiles), and the
podman `btrfs` storage driver creates one per container layer under `~/.local/share/containers/storage`. All of
that is skipped, which is fine here; list them with `sudo btrfs subvolume list /`.

`@root` contains `/etc/ssh/ssh_host_ed25519_key`, the only recipient key of the agenix secrets, so the HDD now
holds it as well: `/backup` is kept readable by root only (`mountDirs`, mode 0700; the snapshots keep the original
permissions).

### What the settings mean

| Setting | Meaning |
|---|---|
| `onCalendar = "*:0/10"` | (`home`) systemd timer: every 10 minutes (minutes 0, 10, 20, ... of each hour) (`AccuracySec` is forced to 1 min, the module's default of 10 min would blur it); `system` uses `*-*-* 04:05:00` |
| `snapshot_create = "onchange"` | take a snapshot only if `@home` changed since the last one; an idle machine creates none |
| `timestamp_format = "long"` | names carry the time (`@home.20261107T1530`); the default is a date only, which would collide every 10 minutes |
| `snapshot_preserve_min = "2h"` | local snapshots younger than 2 hours are never deleted |
| `snapshot_preserve = "no"` | after those 2 hours nothing more is kept locally (long history lives on the HDD) |
| `target_preserve_min = "no"` | on the HDD only what `target_preserve` selects is kept |
| `target_preserve = "24h 14d 8w 6m"` | `<n>h` hourly, `<n>d` daily, `<n>w` weekly, `<n>m` monthly: the last 24 hourly backups, then one per day for 14 days, one per week for 8 weeks, one per month for 6 months; which snapshot represents a day/week/month is decided by btrbk from the timestamps (`preserve_day_of_week`, default Sunday, anchors weekly and longer; `preserve_hour_of_day`, default 0, anchors daily) |
| `incremental = "yes"` | send only differences against the common parent; if there is no parent a full copy is made |
| `ExecStartPre=+<check that /backup/btrbk exists>` + `x-systemd.automount` | the check mounts `/backup` on first access, so no manual `mount`; if the HDD or the target directory is missing the unit fails before btrbk starts: nothing is created and nothing piles up. `RequiresMountsFor=/backup` would not do, a device that times out cancels the job without marking the unit failed |

btrbk sends only what the target's retention needs, so of the six snapshots per hour about one reaches the HDD.

### Scenarios

| | Snapshots | Local keep | HDD keep | Cost |
|---|---|---|---|---|
| A. conservative | daily | 2 days | 14d 8w 6m | minimal; up to a day of work can be lost |
| **B. implemented** | every 10 min, only if changed | 2 h | 24h 14d 8w 6m | few snapshots alive at once, so little pinned space and little bees interference |
| C. aggressive | every 10 min | 24 h | as B | ~144 snapshots; pins every overwritten block on a nearly full disk and multiplies bees' metadata cost |

On a nearly full disk the retention window matters more than the frequency, which is why the local window is short.

### Tool choice

| Tool | Verdict |
|---|---|
| **btrbk** | chosen: snapshots + incremental send/receive + tiered retention in one tool, NixOS module, browsable backups |
| snapper | local timeline snapshots only, no send/receive |
| restic / borg | file-level, encrypted, independent of btrfs; slower, needs the tool to restore. Worth adding later as a second copy of the most important data |
| rsync | no snapshots, no history |

### Safety net and limits

- `/backup/btrbk` is created by the `mount-dirs-backup` service when the HDD is mounted, never by tmpfiles: if the
  HDD is missing, a tmpfiles path on the NVMe root would receive the backups onto the full disk.
- A full or read-only HDD passes the target check: btrbk keeps snapshotting `@home` every 10 minutes and skips its
  cleanup while the send fails, so react to the failure notification before the snapshots pin too much of the NVMe.
- Restoring `@root` from the HDD brings back the SSH host key, so the agenix secrets stay decryptable.
- `@home` includes caches; if the first transfer is too big, move big caches to their own subvolume.

### First start (after any defrag, see section 1)

After `nixos-rebuild switch` and a reboot nothing has to be prepared by hand: the first access mounts the disk,
`mount-dirs-backup` makes `/backup` root-only (the `@root` backups hold the agenix key) and creates
`/backup/btrbk`. Look at the disk first:

```sh
sudo ls -la /backup                                           # triggers the automount; expect drwx------ and btrbk/
sudo btrfs filesystem usage /backup                           # what is on the disk already, free space
```

Then:

```sh
sudo umount ~/mnt                                             # a top-level mount under /home inflates the size
sudo btrfs filesystem du -s /home                             # size of the first full send
sudo btrbk -c /etc/btrbk/home.conf dryrun                     # what the first run would do (also system.conf)
sudo systemctl start btrbk-system btrbk-home && journalctl -fu btrbk-home
systemctl list-timers 'btrbk-*'
```

The first run copies everything (hours for hundreds of GB over the HDD); later runs are incremental.

### Watching and restoring

```sh
sudo btrbk -c /etc/btrbk/home.conf list backups   # also system.conf              # what exists locally and on the HDD
sudo btrfs filesystem du -s /mnt/btrfs-top/.snapshots/*       # "Exclusive" = space a snapshot pins
sudo ls /backup/btrbk/                                        # browse any backup as plain files (root-only)
failure-notify list                                           # open failure records, see below
sudo cp -a --reflink=auto /mnt/btrfs-top/.snapshots/@home.<time>/mathew/<file> /home/mathew/   # quick undo
sudo btrbk -c /etc/btrbk/home.conf dryrun                     # preview what the next run would do
```

A failed `btrbk-home` or `btrbk-system` run (missing HDD included) or a failed scrub is recorded by `system-config/failure-notify.nix`
in `/var/lib/failure-notify/`: the graphical session shows a critical notification, every zsh lists open records at start and prints a
new one before the next prompt. The record disappears with the next successful run.

Whole-subvolume restore: `btrfs send` the backup (or local snapshot) and `btrfs receive` it next to the broken
one, then swap the subvolume in the top-level mount.

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

## 5. Compression on the backup HDD (2026-11-08)

Same script as in section 4 with `MNT=/backup`, 8 GiB of Phasmophobia (compressible) and of World of Tanks Blitz
(incompressible), one writer, one run per variant (speeds are noisy, sizes repeat). The HDD writes ~0.10 GiB/s.

| Phasmophobia, 8.0 GiB | Disk | Write |
|---|---|---|
| no compression | 100% | 0.10 GiB/s |
| `compress` zstd:1 .. 12 | 65-68% | 0.13 GiB/s |
| `compress-force` zstd:1 / 3 | 51% / 49% | 0.20 GiB/s |
| `compress-force` zstd:5 .. 10 | 46-47% | 0.20 GiB/s |
| `compress-force` zstd:12 / 13 | 46% | 0.16 / 0.13 GiB/s |
| `compress-force` zstd:14 / 15 | 45% | 0.09 / 0.08 GiB/s |

- Blitz: `compress` stays at 100%, `compress-force` gives 95-96% at every level and the speed of the uncompressed
  write (0.09-0.10 GiB/s), so forcing costs nothing here.
- Unlike the NVMe, compression makes the write about twice as fast: the disk is the limit and less data reaches it.
  Above zstd:10 the CPU becomes the limit and the write slows down, for a 1 point gain.
- Levels 5 to 10 are the same within noise. Games are already on the plateau; `@home` and `@root` hold more text
  and may gain from a higher level, which was not measured.

Decision: `compress-force=zstd:5` (the lowest level on the plateau, least CPU).
