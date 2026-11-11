# Strata on Gentoo

The package installs a read-only tree under `/usr/lib/strata` and keeps
everything it writes under `/var/lib/strata`, the home of the `strata`
user.  `strata-setup` runs the upstream installer as that user in
packaged mode (`STRATA_STATE_DIR=/var/lib/strata`): it writes
`/var/lib/strata/strata-<tag>.json`, puts model data in
`/var/lib/strata/data`, and never runs pip, downloads an engine, or
compiles one.  It never starts the server either; `systemctl enable
--now strata@<tag>` does.  `strata@<tag>.service` serves that config on
the port it records (8095 for a new install) and logs to the journal.

The example drop-ins named below are installed uncompressed in
`/usr/share/doc/strata-<version>/examples/`.  Copy one to
`/etc/systemd/system/strata@.service.d/` (all tags) or
`/etc/systemd/system/strata@<tag>.service.d/` (one tag), edit it, and
run `systemctl daemon-reload`.

## Serving models from your own Hugging Face cache

The default is a separate cache in `/var/lib/strata/huggingface`.  To
reuse the models you already downloaded as your own user (`alice`
below), bind-mount your cache's `hub` folder into it instead.

1. Let `strata` read the hub cache, now and for future downloads.
   Share only `hub`: the cache root also holds your Hugging Face
   token, and `hf auth login` resets the root's mode, which masks off
   any ACL there.

       setfacl -R -m u:strata:rX ~alice/.cache/huggingface/hub
       setfacl -R -d -m u:strata:rX ~alice/.cache/huggingface/hub

2. Mount it read-only in `/etc/fstab`:

       /home/alice/.cache/huggingface/hub  /var/lib/strata/huggingface/hub  none  bind,ro  0 0

   Create the mount point first if it is missing:
   `install -d -o strata -g strata -m 0750 /var/lib/strata/huggingface /var/lib/strata/huggingface/hub`.

3. Install the `hf-cache-bind-mount.conf` drop-in.  It orders the
   service after the mount (`RequiresMountsFor=`), so the server never
   starts on the empty directory beneath it.

4. With SELinux, the policy's `strata.fc` marks
   `/var/lib/strata/huggingface` as `<<none>>`, so `restorecon` never
   relabels it and the bind-mounted cache keeps its own home-directory
   labels.  `strata_t` may not read those by default; the
   `strata_read_user_cache` boolean grants it:

       setsebool -P strata_read_user_cache on

5. Download as yourself (`hf download <repo> --revision <rev>`), then
   point setup at the snapshot folder that holds the `.gguf` shards
   (some repositories keep each quant in a subfolder) through the mount:

       strata-setup ... --gguf-dir /var/lib/strata/huggingface/hub/models--<org>--<name>/snapshots/<rev>[/<quant>]

Keep the mount read-only.  `StateDirectory=strata` makes systemd chown
`/var/lib/strata` recursively whenever its owner does not match the
`strata` user (a changed UID, or a manual `chown`), and that recursion
can reach into a writable bind mount and hand your own files to
`strata`.  On a read-only mount the chown fails instead.  Never
`chown -R` `/var/lib/strata` by hand while the cache is mounted.

## A data directory elsewhere

Model data and packs need 70 to 120 GB per model, and the packs are read
on every token, so a fast local disk can beat `/var/lib`.  For
`/srv/strata-data`:

    install -d -o strata -g strata -m 0750 /srv/strata-data
    semanage fcontext -a -t strata_var_lib_t '/srv/strata-data(/.*)?'
    restorecon -Rv /srv/strata-data
    strata-setup ... --data-dir /srv/strata-data

Skip the `semanage` and `restorecon` lines without SELinux.  The unit
can write only to `/var/lib/strata`, so also install the
`data-dir.conf` drop-in with your path in `ReadWritePaths=`.

## Allowed host names

The server checks each request's `Host` header against the names it
knows, a guard against DNS rebinding.  Clients that reach it under
another name (a reverse proxy, `my-server.lan`) need that name allowed.
Install the
`allowed-hosts.conf` drop-in and set `STRATA_ALLOWED_HOSTS` to a
comma-separated list of names (ports are ignored).  The same list can
go in the config as `"allowed_hosts": ["my-server.lan"]`, or set an
API key (`"api_key"`) instead.

## Network access

The server itself reaches out only for MCP tool servers and for images
given by URL.  `--offline` blocks both.  With `USE=default-offline`
every instance starts with it; without the flag none does.  Either way,
the `offline.conf` and `online.conf` drop-ins switch an instance (or all
of them) to the other behaviour.  Downloads and setup never go through
the service.

## Images

With `USE=vision` the package installs two image readers next to the
engine: `strata-vision-hip` on the GPU and `strata-vision` on the CPU,
its fallback.  `strata-setup` finds them in the engine's `BUILD.json`
and records them in the config, so a model with a picture encoder reads
images.  Without the flag those models answer text only.

## hipBLASLt tuning

With `USE=hipblaslt` the engine uses hipBLASLt for the dense matrix
products of the prompt and installs upstream's tuning tables in
`/usr/lib/strata/engine/tuning`.  It loads the table for its GPU and
the running hipBLASLt version by itself on gfx1151 (Strix Halo), where
upstream measured prompts about twice as fast.  On other cards a table
changes answers in their last digits for a gain near 1%, so it stays
off unless you set `Environment=STRATA_HIPBLASLT_TABLE=on` in a
drop-in.  A card or hipBLASLt version without a table falls back to
plain hipBLAS.

## Models with their own engine

DeepSeek-V4.1-Flash, and any model upstream's model list marks with a
shape of its own, run on separate engines that upstream ships only
through its signed update feed.  This package does not include them,
so `strata-setup` stops when you choose one of those models.

## Huge pages

The engine asks for its CPU expert arena in 2 MiB huge pages, all or
nothing.  With the pool short by even one page, it logs
`MAP_HUGETLB unavailable (needed N 2 MiB pages, vm.nr_hugepages=M)`
and falls back to normal pages, plus transparent huge pages where the
kernel gives them.  It still runs, just with more TLB misses.

The reliable way to get the pages is to reserve them at boot, before
memory fragments.  Add `hugepages=N` to the kernel command line, or
put `vm.nr_hugepages = N` in `/etc/sysctl.d/strata.conf`.  Those pages
are gone for everything else until you lower the number again.

To hold them only while the instance runs, install the
`hugepages.conf` drop-in under `strata@<tag>.service.d/` and set
`STRATA_HUGEPAGES=N`.  Before each start, `/usr/libexec/strata-hugepages`
adds N pages to the pool; after each stop it takes back what it added.
On a long-running machine the kernel may find fewer than N free 2 MiB
blocks.  The helper then gives back what it got, logs how many it
found, and lets the instance start on normal pages.  If that keeps
happening, reserve the pages at boot instead.

## SELinux

`sec-policy/selinux-strata` runs the server and its engine in
`strata_t`, for now as a permissive domain: denials are logged, not
enforced.  Base policy 2.20260922 and later label `/dev/kfd`, the ROCm
compute node, as `xserver_misc_device_t`, which `strata_t` may open.
Older base policies leave it `device_t`, so `selinux-strata` versions
for them label it `hsa_device_t` (the type Fedora uses) themselves.
There, unconfined users keep ROCm access, but confined user domains
such as `staff_t` and `user_t` lose it.  Two labels for one path fail
the policy load, so those versions block newer base policies: upgrade
`selinux-base-policy` and `selinux-strata` together.

The package labels tcp 8095 as `strata_port_t`.  Label any other port
an instance listens on, and delete that label before you uninstall the
policy, because a local label that names `strata_port_t` makes the
module removal fail:

    semanage port -a -t strata_port_t -p tcp 8096
    semanage port -d -p tcp 8096

A plain `/var/lib/strata/huggingface` (not a bind mount) created before
the policy was loaded keeps `var_lib_t`: `strata.fc` marks that path
`<<none>>`, so `restorecon` skips it.  Label it once:

    chcon -R -t strata_var_lib_t /var/lib/strata/huggingface
