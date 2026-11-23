# btrfs runbook (single NVMe filesystem, subvolumes `@root @home @nix @games @log @nocow`)

State of the filesystem and the reasoning behind each knob. Commands marked `sudo` are for the owner; the
agent user has no root.

Contents: Settings in this repo · 1. Recompressing existing data · 2. bees (deduplication) · 3. Backups (btrbk to the HDD) · 4. Compression level on the NVMe · 5. Compression on the backup HDD

## Settings in this repo

| What | Where | Why |
|---|---|---|
| `compress-force=zstd:-1,noatime` | `system-config/nixos/file-systems.nix` | -1 keeps NVMe speed (owner's benchmarks: ~4x faster than zstd:1 in a ramdisk); `-force` because the plain-compress heuristic leaves compressible data uncompressed, see section 4. Only NEW writes are affected. |
| `periodic_reclaim` + `dynamic_reclaim` | `file-systems.nix`: `boot.kernel.sysfs` for the NVMe, `btrfs-reclaim-backup.service` at mount time for the HDD | returns half-empty data chunks to unallocated space automatically (kernel >= 6.11) |
| `services.fstrim` off | `file-systems.nix` | `discard=async` already trims freed extents |
| bees dedup | `system-config/nixos/bees.nix` (import commented out) | expected gain small and the cost permanent, see section 2 |
| btrbk snapshots + backup to the HDD | `system-config/nixos/backup.nix` | see "Backups" |
| `compress-force=zstd:5` on `/backup`, monthly scrub | `file-systems.nix` | the HDD is the bottleneck, so a higher level is free; see section 5 |
| `nofail,x-systemd.device-timeout=10s` on `/games`, `/var/lib/nocow`, `/backup`; `x-systemd.automount` on `/backup` only | `file-systems.nix` | mounts the system can run without: a missing disk does not stop the boot and is given up on after 10 s. Only the HDD is an automount (mounted on first access, so a disk that shows up later needs no manual mount); for subvolumes of the system disk that buys nothing and tmpfiles rules would stop applying |
| `mountDirs` | `file-systems.nix`, `backup.nix` | directories and permissions applied by a service each time a mount comes up (`/backup` 0700, `/backup/btrbk`): tmpfiles skips automount points and must never create these paths on the NVMe root |

After regenerating `system-config/nixos/hardware-configuration.nix` (`nixos-generate-config`), check its `fileSystems` entries:
`/backup`, `/mnt/btrfs-top` and the other mounts keep their `device` and `fsType` there and their options in
`file-systems.nix`. The generator writes what is mounted at that moment, and with `/backup` automounted that is an
extra `fileSystems."/backup"` with `device = "systemd-1"; fsType = "autofs"` next to the real one. Delete the `autofs`
block (a duplicate attribute stops the build); keep the `btrfs` one. `usbhid` and `usb_storage` in
`boot.initrd.availableKernelModules` are needed for the USB keyboard and the generator may drop them: put them back.

Watch reclaim: `grep . /sys/fs/btrfs/*/allocation/data/{reclaim_count,reclaim_bytes,reclaim_errors}`.
Undo: write `0` into `periodic_reclaim` and `dynamic_reclaim` there.

## 1. Recompressing existing data

`balance` does not compress or deduplicate anything, it only moves chunks. Compression of data written before the mount option needs `btrfs filesystem defragment -czstd -L -1`, wrapped by `scripts/btrfs-recompress.sh`. Check where it pays first: `compsize` shows what is stored uncompressed (here almost all of it is game data, and most games gain little: the archives are already compressed), and `scripts/btrfs-compress-estimate.sh` estimates a `zstd -1` result without writing.

```sh
sudo compsize -x / /home /nix /games                 # stored vs uncompressed, per compression type
scripts/btrfs-recompress.sh /games /home            # dry run: prints the work units
sudo scripts/btrfs-recompress.sh --run --min-free-gib 100 /games /home
```

- Every PATH is cut into units of at most `--max-unit-gib` (default 25 GiB); free space is checked before every unit and below `--min-free-gib` the run stops and can be repeated: finished units are listed in `/var/tmp/btrfs-recompress.done`.
- Nested subvolumes and other mounts are never entered. Leave `/nix` (read-only store, hard-linked by `nix.optimise`; it can be defragmented through the top-level mount, which keeps the hard links but doubles the extent count, and the gain erodes as the store turns over), `@nocow` (NOCOW files are not compressed) and `@log` (NOCOW journals) out.
- defragment **breaks reflinks**: shared data (reflinked copies, container layers) is copied. Run it **before the backups are enabled**, because an existing snapshot keeps the old copies and every rewritten file would be stored twice until the snapshots expire.
- It reads and rewrites everything it touches at idle IO priority: expect hours and as many bytes of NVMe writes (`sudo smartctl -a /dev/nvme0n1` shows the wear indicator).
- `btrfs filesystem du -s /home` also walks everything mounted below it: with the top-level subvolume mounted at `~/mnt` it counts the whole filesystem. Unmount it first.
- A failed defragment (ENOSPC) leaves the data intact.

## 2. bees (deduplication) - disabled

`system-config/nixos/bees.nix` is written but its import in `configuration.nix` is commented out. Reasons (measured
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

Implemented in `system-config/nixos/backup.nix` (the `/backup` mount itself is in `file-systems.nix`). Backed up: `@home` (instance `home`) and `@root` (instance
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

A file deleted by mistake 20 minutes ago is in a local snapshot (copy it back); one deleted three weeks ago is only on the HDD.

### What is backed up

| Subvolume | Instance | Snapshot | Local keep | HDD keep |
|---|---|---|---|---|
| `@home` | `home` | every 10 min if changed | 2 h | 24h 14d 8w 6m |
| `@root` | `system` | daily 01:05 if changed | 2 days | 14d 8w 6m |

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
| `onCalendar = "*:0/10"` | (`home`) systemd timer: every 10 minutes (minutes 0, 10, 20, ... of each hour) (`AccuracySec` is forced to 1 min, the module's default of 10 min would blur it); `system` uses `*-*-* 01:05:00` |
| `snapshot_create = "onchange"` | take a snapshot only if `@home` changed since the last one; an idle machine creates none |
| `timestamp_format = "long"` | names carry the time (`@home.20261107T1530`); the default is a date only, which would collide every 10 minutes |
| `snapshot_preserve_min = "2h"` | local snapshots younger than 2 hours are never deleted |
| `snapshot_preserve = "no"` | after those 2 hours nothing more is kept locally (long history lives on the HDD) |
| `target_preserve_min = "no"` | on the HDD only what `target_preserve` selects is kept |
| `target_preserve = "24h 14d 8w 6m"` | `<n>h` hourly, `<n>d` daily, `<n>w` weekly, `<n>m` monthly: the last 24 hourly backups, then one per day for 14 days, one per week for 8 weeks, one per month for 6 months; which snapshot represents a day/week/month is decided by btrbk from the timestamps (`preserve_day_of_week`, default Sunday, anchors weekly and longer; `preserve_hour_of_day`, default 0, anchors daily) |
| `incremental = "yes"` | send only differences against the common parent; if there is no parent a full copy is made |
| `ExecStartPre=+<check that /backup/btrbk exists>` + `x-systemd.automount` | the check mounts `/backup` on first access, so no manual `mount`; if the HDD or the target directory is missing the unit fails before btrbk starts: nothing is created and nothing piles up. `RequiresMountsFor=/backup` would not do, a device that times out cancels the job without marking the unit failed |

btrbk sends only what the target's retention needs, so of the six snapshots per hour about one reaches the HDD.

### Why these intervals

A snapshot pins every block that is overwritten or deleted after it, so on a nearly full disk the retention window matters more than the frequency: snapshots every 10 minutes (only when something changed) with a 2 h local window keep few snapshots alive, while a 24 h window would hold ~144 and multiply bees' metadata cost. The long history lives on the HDD. btrbk was chosen over snapper (no send/receive) and rsync (no snapshots) because it snapshots, sends incrementally and prunes in tiers in one tool; restic or borg would add a file-level second copy of the most important data.

### Safety net and limits

- `/backup/btrbk` is created by the `mount-dirs-backup` service when the HDD is mounted, never by tmpfiles: if the
  HDD is missing, a tmpfiles path on the NVMe root would receive the backups onto the full disk.
- A full or read-only HDD passes the target check: btrbk keeps snapshotting `@home` every 10 minutes and skips its
  cleanup while the send fails, so react to the failure notification before the snapshots pin too much of the NVMe.
- Restoring `@root` from the HDD brings back the SSH host key, so the agenix secrets stay decryptable.
- `@home` includes caches; if the first transfer is too big, move big caches to their own subvolume.

### First run

Run the recompression (section 1) before the first backup. The first access of `/backup` mounts the disk, `mount-dirs-backup` makes it root-only and creates `/backup/btrbk`. The first run copies everything (hours for hundreds of GB over the HDD); later runs are incremental. Check beforehand:

```sh
sudo umount ~/mnt                                             # a top-level mount under /home inflates the size
sudo btrfs filesystem du -s /home                             # size of the first full send
sudo btrbk -c /etc/btrbk/home.conf dryrun                     # what the first run would do (also system.conf)
```

### Watching and restoring

```sh
sudo btrbk -c /etc/btrbk/home.conf list backups   # also system.conf              # what exists locally and on the HDD
sudo btrfs filesystem du -s /mnt/btrfs-top/.snapshots/*       # "Exclusive" = space a snapshot pins
sudo ls /backup/btrbk/                                        # browse any backup as plain files (root-only)
failure-notify list                                           # open failure records, see below
sudo btrbk -c /etc/btrbk/home.conf dryrun                     # preview what the next run would do
```

A failed `btrbk-home` or `btrbk-system` run (missing HDD included) or a failed scrub is recorded by `system-config/nixos/failure-notify.nix`
in `/var/lib/failure-notify/`: the graphical session shows a critical notification, every zsh lists open records at start and prints a
new one before the next prompt. The record disappears with the next successful run.
Concurrent reports for the same record share a lock when they read and update its timestamps; the regression test runs
with `python3 -B -m unittest discover -s system-config/nixos/failure-notify -p 'test_*.py'` from the repository root.

### Restoring

btrbk only makes and prunes copies; restoring is done by hand with `btrfs`, as root. Local snapshots are kept for
about 2 hours (`snapshot_preserve_min 2h`), so the HDD copy in `/backup/btrbk/` is usually the one to restore from.
Names are `@home.<YYYYMMDD>T<HHMM>` and `@root.<…>`. The mounts use `subvol=@home` / `subvol=@root` by name, so
renaming a subvolume in the top-level mount and putting a new one under the old name replaces it after a reboot.

**A file or a directory** needs no mount, a snapshot is plain files:

```sh
sudo ls /mnt/btrfs-top/.snapshots/ /backup/btrbk/            # find the time
sudo cp -a --reflink=auto /backup/btrbk/@home.<time>/mathew/<path> /home/mathew/<path>
```

**The whole `@home`.** Log `mathew` out first (work from ssh or a tty), nothing may write to `/home` meanwhile.

```sh
cd /mnt/btrfs-top
# only if the snapshot is no longer on the NVMe; the copy arrives read-only
sudo btrfs send /backup/btrbk/@home.<time> | sudo btrfs receive /mnt/btrfs-top/.snapshots/
sudo mv @home @home.broken                                    # kept as a way back
sudo btrfs subvolume snapshot .snapshots/@home.<time> @home   # a writable copy under the original name
sudo reboot
sudo btrfs subvolume delete /mnt/btrfs-top/@home.broken       # after checking the result
```

**The whole `@root`.** The running system cannot replace its own root, so boot a NixOS installer or live image, mount
the NVMe top level (`mount -o subvolid=5 /dev/disk/by-uuid/<NVMe UUID> /mnt`), then run the same `mv` and `snapshot`
with `@root`, taking the copy from `/backup/btrbk/` (mount the HDD there too) and receiving it into
`/mnt/.snapshots/` first.

`@home` and `@root` are copied by separate runs at different times; restoring both, pick the closest times.

## 4. Compression level on the NVMe

Measured with `sudo compsize -x` on 2026-11-07/08. Games are already compressed archives and gain little: the best cases are Proton and the Steam runtime (~47%), Phasmophobia (52%) and The Finals (68%); most others stay at 96-99%.

### compress vs compress-force

`scripts/btrfs-compress-force-test.sh` stages a game in tmpfs, remounts the whole filesystem (btrfs compression
options are shared by all subvolumes) with each option, writes the game to `/home` and records time and size
(`--report` rebuilds the tables from the CSV). Single runs, so differences below ~15% are noise; the source is in
RAM, reads and decompression were not measured.
The `--dest` and `--ram` directories are parents for unique temporary work directories; existing files there are not
removed. The benchmark refuses a parent that overlaps a dataset or the other temporary parent.

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
