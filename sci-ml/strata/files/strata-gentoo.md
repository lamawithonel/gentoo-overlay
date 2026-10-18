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

## SELinux

`sec-policy/selinux-strata` runs the server and its engine in
`strata_t`, for now as a permissive domain: denials are logged, not
enforced.  It labels `/dev/kfd`, the ROCm compute node, as
`hsa_device_t` (the type Fedora uses), which `strata_t` may open.
Unconfined users keep ROCm access; confined user domains such as
`staff_t` and `user_t` lose it.  Base policy 2.20260922 labels
`/dev/kfd` on its own, and two labels for one path fail the policy
load, so this package blocks every newer base policy until a matching
`selinux-strata` bump, which drops its own label once the base has one.

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
