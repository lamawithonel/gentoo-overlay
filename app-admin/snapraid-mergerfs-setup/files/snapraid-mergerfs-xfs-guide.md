# SnapRAID + MergerFS + XFS (reflink=1) on Gentoo

A reference for building a 5-bay USB-attached secondary storage
pool optimised for data integrity, with performance as a
secondary goal.  Targets Gentoo Linux with systemd, all CLI.

The shipped tooling lives in the `app-admin/snapraid-mergerfs-setup`
ebuild in this overlay.  Every script is interactive (it shows
what it will run, explains why, and asks for confirmation via
[charmbracelet/gum](https://github.com/charmbracelet/gum)) and
every script is idempotent — re-running a script that has already
completed is a no-op or at most re-verifies existing state.

This document is a *reference*: design rationale, install
instructions, and a one-line index of every script.  It does
not include script source — see `app-admin/snapraid-mergerfs-setup/files/`
for that.

## Assumptions and design decisions

- **Hardware**: 5 × USB-attached HDDs (e.g., a 5-bay USB
  enclosure).  Models need not match; the operator picks array
  members interactively from the candidate pool at
  `/dev/disk/by-id/usb-*`.
- **Software**: `snapraid`, `mergerfs`, `xfsprogs`, `gum`,
  `smartmontools`, `systemd`.  All are pulled in by the ebuild;
  no manual install is required.
- **Init**: systemd.
- **Layout**: **2 parity drives + 3 data drives**.  Five drives
  lets us choose between 1p4d (more capacity) and 2p3d (much
  higher integrity).  Since data integrity takes precedence, we
  use 2p3d.  This protects against any two simultaneous drive
  failures.
- **Filesystem**: XFS with `reflink=1` and `crc=1`.  Reflink
  enables near-instant snapshots and deduplicated copies on a
  single branch.
- **Pool**: MergerFS unifies the 3 data drives.  Parity drives
  stay out of the pool — SnapRAID needs exclusive control of
  them and any user write into a parity branch would corrupt
  parity.
- **Workload**: Backups and infrequently accessed files.
  Favours `mfs` create policy and weekly scrub schedules.
- **Caveat about reflink + mergerfs**: XFS reflinks (`FICLONE`)
  only work *within a single filesystem*.  MergerFS exposes
  branches as one namespace, but cross-branch reflinks fall
  back to a real copy.  Fine for backups; just be aware.

## Conventions

- Scripts install to `/usr/sbin/snapraid-*`.
- Shared shell helpers at `/usr/lib/snapraid-setup/helpers.sh`.
- Configuration in `/etc/snapraid.conf`,
  `/etc/snapraid-roles.conf`, and `/etc/fstab`.
- Mount points: `/mnt/snapraid0/parity1`,
  `/mnt/snapraid0/parity2`, `/mnt/snapraid0/data1`,
  `/mnt/snapraid0/data2`, `/mnt/snapraid0/data3`, and the pool
  at `/mnt/snapraid0/storage`.
- Logs in `/var/log/snapraid/`.
- Drive role assignment is **interactive** via `snapraid-detect`,
  which presents a `gum` checklist of USB candidate drives.
  Once pinned in `/etc/snapraid-roles.conf`, every later script
  reads that file as the source of truth.
- Every destructive operation targets the
  `/dev/disk/by-id/ata-*` (or `usb-*`) symlink rather than
  `/dev/sdX`, so a USB hot-plug renumbering can never pivot the
  operation onto the wrong disk.

## Installation

Add this overlay (e.g., via `eselect repository add`), then:

```sh
emerge --ask app-admin/snapraid-mergerfs-setup
```

### USE flags

| Flag           | Default | Effect                                       |
|----------------|---------|----------------------------------------------|
| `setup`        | on      | Install the bootstrap scripts (`snapraid-detect`, `snapraid-format`, `snapraid-fstab`, ...). |
| `systemd`      | on      | Install the sync/scrub service+timer pairs and `snapraid-enable-timers`. |
| `smart-tests`  | off     | Install the `snapraid-smart-long.service`+`.timer` pair (long SMART self-tests).  Enables the `@SMART_LONG_ENABLED@` substitution that activates smart-long handling in `snapraid-runner`, `snapraid-runner-interactive`, `snapraid-enable-timers`, and `snapraid-acceptance`.  Disable on hosts whose USB-to-SATA bridges do not pass `smartctl` test commands. |
| `test`         | off     | Install `snapraid-integrity-drill` and `snapraid-acceptance`. |
| `doc`          | on      | Install this guide under `/usr/share/doc/`.  |

## Quickstart

End-to-end installation order.  Every script is idempotent
unless flagged DESTRUCTIVE; re-running is safe.

1. **Attach all 5 USB drives.**  Confirm they enumerate at
   `/dev/disk/by-id/usb-*`.

2. **`snapraid-detect`** — interactive picker.  Select 2 parity
   then 3 data drives from the candidate list.  Each row shows
   the drive's `by-path` topology ID and its `ata-*` serial-
   bearing ID.  Writes `/etc/snapraid-roles.conf`.

3. **`snapraid-preflight`** — verifies required binaries,
   kernel modules, systemd as PID 1, and that every drive
   listed in the roles file is present, SMART-healthy, and on
   USB transport.  Read-only.  Re-run any time.

4. **`snapraid-tune-usb`** — *optional but recommended*.
   Installs the udev rule that sets BFQ (or mq-deadline as
   fallback) scheduler, deepens read-ahead and request queue,
   and disables aggressive APM/spin-down on USB whole-disks.
   Run before `snapraid-format` so the freshly-formatted drives
   mount with the tuned settings already applied.

5. **`snapraid-format`** — **DESTRUCTIVE**.  Wipes signatures,
   GPT-labels, partitions, and `mkfs.xfs`'s each role drive
   (`reflink=1,crc=1,finobt=1`).  Skips drives already carrying
   the expected XFS partition with the role label.  Per-disk
   confirmation prompt before any write.

6. **`snapraid-fstab`** — generates fstab entries between
   marker lines (preserves your other entries), then runs
   `systemctl daemon-reload` and `mount -a`.  The MergerFS pool
   at `/mnt/snapraid0/storage` comes online here.  After it
   completes, `findmnt /mnt/snapraid0/storage` should show
   `fuse.mergerfs` and `df -h /mnt/snapraid0/data*` should show
   each XFS branch mounted.

7. **`snapraid-genconf`** — writes `/etc/snapraid.conf` (parity
   files, content files on every data drive, the data role
   list, default exclude rules, per-disk `smartctl` commands).

8. **`snapraid-first-sync`** — runs the initial `snapraid sync`.
   Fast on empty data drives (parity is still mostly zero).

9. **`snapraid-integrity-drill`** (USE=`test`) — writes ~50 MB
   of test data, syncs, deliberately corrupts a block on one
   data drive, verifies SnapRAID detects and repairs the
   corruption, then cleans up.  Do not proceed to production
   data until this passes 2/2.

10. **(operator action)** Copy real data into
    `/mnt/snapraid0/storage`.  MergerFS picks a backing data
    drive per file according to its create policy.

11. **`snapraid-runner sync`** — re-sync after the bulk import.
    (Or skip and let the timer run it.)

12. **`snapraid-enable-timers`** — enables and starts the
    timers installed by USE=`systemd` (and USE=`smart-tests`,
    if enabled).  From this point on the array maintains
    itself.

13. **`snapraid-acceptance`** (USE=`test`) — final smoke test.
    Verifies mounts, timers active, SnapRAID state, scheduler
    tuning.  Should run all green.

**Operational (anytime)**

- **`snapraid-recover`** — interactive runbook for failed-drive
  replacement, single-file restore, or rebuilding parity after
  a drive swap.  Only invoke deliberately; it will not run on
  its own.
- **`snapraid-runner-interactive`** — wraps `snapraid-runner`
  with a confirmation prompt for ad-hoc sync/scrub/smart-long
  runs outside the timer schedule.

## Architecture rationale

Design choices that are not obvious from reading the scripts:

### Why parity is not in the mergerfs pool

SnapRAID needs exclusive control of parity files; any user
write into a parity branch would corrupt parity.  Parity
mountpoints (`/mnt/snapraid0/parity{1,2}`) stay outside the
pool and are referenced only by SnapRAID.

### `nofail` is absent from the mergerfs `Options=` line

libfuse rejects unknown mount options
(`fuse: unknown option 'nofail'`) and util-linux does *not*
strip them for FUSE helpers the way it does for in-kernel
filesystems.  The fstab entry instead lists every data branch
in `x-systemd.requires=`; each branch is itself `nofail`, so
if any branch is missing, systemd skips the mergerfs mount
without failing the boot.  The net behaviour is equivalent.

### BFQ → mq-deadline scheduler fallback

The udev rule installed by `snapraid-tune-usb` lists two
`ATTR{queue/scheduler}=` assignments — `bfq` first, then
`mq-deadline`.  udev silently ignores assignments the kernel
rejects, so on hosts without `CONFIG_IOSCHED_BFQ` the
mq-deadline assignment wins.  `snapraid-acceptance` accepts
either.  bfq is preferred for mixed-workload HDDs; mq-deadline
is a perfectly reasonable fallback.

The ebuild uses `linux-info`'s `CONFIG_CHECK` (with the `~`
warn-only prefix) to surface a build-time `ewarn` when neither
`IOSCHED_BFQ` nor `MQ_IOSCHED_DEADLINE` is enabled in the
running kernel's config.  The package still installs — `none`
is a valid scheduler — but you will lose the latency and
throughput benefits the udev tuning is designed to provide.

### `MAX_DEL_THRESHOLD` and `MAX_UPD_THRESHOLD` in the runner

`snapraid-runner sync` aborts if a single diff shows more than
500 deletions or 2000 updates.  This catches `rm -rf` accidents
*before* parity is overwritten with the bad state.  Override by
running `snapraid-runner-interactive` and confirming.

### `--force-empty` in the integrity-drill cleanup

The drill writes test files, syncs, then deletes them and runs
a final sync.  After the deletion, plain `snapraid sync` would
exit non-zero with "files previously present ... are now
missing" — a safety check meant to catch unmounted disks.
Inside the drill that warning is the expected lifecycle, so
the cleanup `EXIT`/`INT`/`TERM` trap and the final sync both
pass `--force-empty`.  The *initial* sync stays protective so
a real anomaly still halts the drill.

### Per-disk smartctl in `snapraid.conf`

`snapraid-genconf` writes one `smartctl <name> -d sat ...` line
per drive instead of a single global wildcard line.  Generic
USB-to-SATA bridges need explicit `-d sat` to translate ATA
pass-through; without it, `snapraid -e check` errors with
`Unknown 'smartctl' name '-d'` because SnapRAID's parser does
not accept positional flags in the wildcard form.

### by-id symlinks for every destructive op

`snapraid-format` and `snapraid-recover` operate on
`/dev/disk/by-id/ata-<model>_<serial>` (or `usb-*`) rather
than `/dev/sdX`.  USB enclosures renumber kernel devices on
hot-plug, but the by-id alias is stable and tied to the actual
drive serial.  This makes it physically impossible for a
mid-operation hot-plug to pivot a `wipefs`/`mkfs` onto the
wrong disk.

### Drill discovers data branches from `snapraid.conf`

`snapraid-integrity-drill` parses `snapraid.conf` for `data`
lines instead of hardcoding `/mnt/snapraid0/data{1,2,3}`.
Lets the drill keep working if the operator adds or removes
data drives later.  It also checks that
`/mnt/snapraid0/storage` is a `fuse.mergerfs` mount before
writing test data — otherwise dd would land on the underlying
empty directory and the drill would silently look for files
that never reached a backing branch.

## Script reference

All scripts install to `/usr/sbin/`.  Source lives in
`app-admin/snapraid-mergerfs-setup/files/` in this overlay.

### Bootstrap (USE=`setup`)

- **[`snapraid-preflight`](app-admin/snapraid-mergerfs-setup/files/snapraid-preflight)**
  — read-only health check.  Verifies binaries, kernel
  modules, systemd-as-PID-1, and the candidate USB drives.
  Idempotent.
- **[`snapraid-detect`](app-admin/snapraid-mergerfs-setup/files/snapraid-detect)**
  — interactive role picker; writes
  `/etc/snapraid-roles.conf`.  Idempotent against an existing
  roles file when its IDs still resolve.
- **[`snapraid-format`](app-admin/snapraid-mergerfs-setup/files/snapraid-format)**
  — **DESTRUCTIVE.**  Per-disk confirmed wipe + GPT +
  `mkfs.xfs`.  Idempotent: skips drives already correctly
  formatted with the expected role label.
- **[`snapraid-fstab`](app-admin/snapraid-mergerfs-setup/files/snapraid-fstab)**
  — splices marker-bracketed entries into `/etc/fstab`,
  reloads systemd, and runs `mount -a`.  Idempotent.
- **[`snapraid-genconf`](app-admin/snapraid-mergerfs-setup/files/snapraid-genconf)**
  — writes `/etc/snapraid.conf` with per-disk smartctl lines.
  Idempotent.
- **[`snapraid-first-sync`](app-admin/snapraid-mergerfs-setup/files/snapraid-first-sync)**
  — runs the initial `snapraid sync` after a confirmation
  prompt and a dry-run `snapraid diff`.
- **[`snapraid-tune-usb`](app-admin/snapraid-mergerfs-setup/files/snapraid-tune-usb)**
  — installs `/etc/udev/rules.d/60-snapraid-usb.rules` (BFQ /
  mq-deadline scheduler, deeper read-ahead and queue, no
  hdparm spin-down).  Idempotent.

### Runtime (USE=`systemd`)

- **[`snapraid-runner`](app-admin/snapraid-mergerfs-setup/files/snapraid-runner)**
  — non-interactive wrapper around `snapraid sync | scrub |
  smart-long`, called by the timers.  Enforces deletion and
  update thresholds before letting `sync` overwrite parity.
- **[`snapraid-runner-interactive`](app-admin/snapraid-mergerfs-setup/files/snapraid-runner-interactive)**
  — interactive front-end to `snapraid-runner` for ad-hoc
  manual runs.
- **[`snapraid-enable-timers`](app-admin/snapraid-mergerfs-setup/files/snapraid-enable-timers)**
  — enables and starts the timers installed by the active USE
  flag set.  Idempotent: skips timers already enabled and
  active.
- **[`snapraid-recover`](app-admin/snapraid-mergerfs-setup/files/snapraid-recover)**
  — interactive recovery runbook (failed-drive replacement,
  single-file restore, parity rebuild).  Operator-driven; not
  scheduled.

### Tests (USE=`test`)

- **[`snapraid-integrity-drill`](app-admin/snapraid-mergerfs-setup/files/snapraid-integrity-drill)**
  — corrupt → detect → repair → verify drill on real
  parity.  Self-cleaning via `EXIT` trap.
- **[`snapraid-acceptance`](app-admin/snapraid-mergerfs-setup/files/snapraid-acceptance)**
  — final smoke test of mounts, timers, scheduler, SnapRAID
  config, reflink support.  Read-only.

### Helpers

- **[`helpers.sh`](app-admin/snapraid-mergerfs-setup/files/helpers.sh)**
  — sourced by every script; provides styled prompts,
  confirmation, idempotency sentinels, root check, common
  paths.  Installs to `/usr/lib/snapraid-setup/helpers.sh`.

### Systemd units (USE=`systemd`)

Installed under `/usr/lib/systemd/system/`:

- **[`snapraid-sync.service`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-sync.service)**
  + **[`snapraid-sync.timer`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-sync.timer)**
  — daily sync.
- **[`snapraid-scrub.service`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-scrub.service)**
  + **[`snapraid-scrub.timer`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-scrub.timer)**
  — weekly scrub.
- **[`snapraid-smart-long.service`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-smart-long.service)**
  + **[`snapraid-smart-long.timer`](app-admin/snapraid-mergerfs-setup/files/systemd/snapraid-smart-long.timer)**
  (USE=`smart-tests`) — monthly long SMART self-test.

## Operational notes

- **Re-running scripts**: every script is idempotent.  If a
  step has nothing to do, it prints a `SKIP:` line and exits.
  Pass `--force` to redo state-managed steps where supported.
- **First sync of real data**: after copying data to
  `/mnt/snapraid0/storage`, run `snapraid-runner-interactive`
  and choose `sync`.
- **Adding a sixth drive later**: the enclosure is capped at
  5 bays.  Growth means swapping a drive for a larger one:
  copy data off the smaller drive, reformat the bigger one,
  sync.
- **Why XFS over Btrfs/ZFS**: chosen for `reflink=1` plus the
  maturity of `xfsprogs` on Gentoo.  XFS reflink does *not*
  give you snapshots like Btrfs.  If you want snapshots later,
  layer them at the application level (`cp --reflink=always`
  for cheap copies on a single branch).
- **Encryption**: not addressed by the shipped tooling.  If
  needed, add LUKS between the partition and XFS.  Do this
  before `snapraid-format`; everything downstream is
  unchanged.
- **Cancellation**: every confirmation defaults to **No**, so
  hitting Enter or Ctrl-C cancels.  Scripts exit with a
  `WARN: User cancelled` message and no destructive side
  effects.
