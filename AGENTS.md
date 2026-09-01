# lamawithonel's Gentoo Portage overlay

 This repository is a **Gentoo Portage overlay** (third-party
 ebuild repository) for the maintainer's personal use.  It is
 consumed by Portage on Gentoo systems, not built or tested as
 a normal software project.  Repo tooling is managed by `mise`
 (pinned pkgcheck/pkgdev plus check and manifest tasks in
 `.config/mise/config.toml`; test tasks are bash file tasks under
 `.config/mise/tasks/`) with `hk`-managed git hooks
 (`.config/hk.pkl`); run `mise install && mise run setup` once
 after cloning.  All devtool config lives under `.config/`
 because Portage rejects stray top-level files in an overlay.

## Repository layout

 - `metadata/layout.conf` — overlay identity (`repo-name =
   lamawithonel`), `masters = gentoo`, profile formats
   (`portage-2 profile-set`), and required manifest hashes
   (`BLAKE2B SHA512`, additionally `SHA3_512`).  Manifests are
   thin and unsigned; commits are unsigned.
 - `repositories.xml` — overlay metadata for repository
   indexes (name, owner, git sources).
 - `profiles/` — Portage profile tree:
   - `profiles/arch.list` — supported arches (`amd64`,
     `arm64`).
   - `profiles/profiles.desc` — registered profiles and their
     stability.  Every profile shipped to users must be listed
     here.
   - `profiles/custom/` — user-facing profile sets:
     `base`, `plasma/{desktop,laptop}[/selinux]`,
     `server/arm64/{rpi3,rpi4}`.  All chain up through
     `lamawithonel:custom/base` to a stage-3-style Gentoo
     profile (e.g. `gentoo:default/linux/amd64/23.0/desktop/
     plasma/systemd`) via `parent` files.
   - `profiles/features/selinux/systemd` — a feature overlay
     profile pulled in via `parent` from SELinux variants.
 - Ebuild packages, all following the standard Gentoo
   `<category>/<pkg>/<pkg>-<ver>.ebuild` + `metadata.xml` +
   `Manifest` layout:
   - `app-admin/snapraid-mergerfs-setup/` — helper scripts and
     docs for a SnapRAID + mergerfs array.
   - `dev-lang/mojo/` — the Mojo compiler and stdlib, built
     from source with upstream's Bazel wrapper (pinned commit;
     `RESTRICT=network-sandbox`).
   - `dev-mojo/max-bin/` — Modular's closed MAX + prebuilt Mojo
     compiler stack, repackaged from PyPI wheels (proprietary
     license in `licenses/`, `RESTRICT="mirror bindist strip"`;
     binaries are x86-64-v3-only).  GPU codegen exists only
     here, never in the from-source `dev-lang/mojo`.
   - `media-fonts/bitter-pro/` — the Bitter Pro typeface
     (`inherit font`; successor to the deleted upstream of
     media-fonts/bitter).

## Conventions

 - **EAPI:** 8 for ebuilds and profile `eapi` files.  EAPIs
   0–4 are banned and 5–6 are deprecated per `metadata/layout.
   conf`; do not introduce them.
 - **Profile inheritance** is via `parent` files (one entry
   per line, `repo:path` for cross-repo, `..` for relative).
   When adding a new profile directory, also add: `eapi`,
   `parent`, and a `profiles.desc` entry (with arch and
   stability `stable` or `exp`).
 - **Profile customization** lives in the standard Portage
   files: `make.defaults`, `packages`, `package.use`,
   `package.use.{force,mask}`, `package.accept_keywords`,
   `package.mask`, `package.unmask`, `use.mask`.  The
   `package.use*` and `package.accept_keywords` directories
   are split per-category (one file per category, e.g.
   `sys-kernel`, `dev-python`); keep that split when adding
   entries.
 - **Maintainer metadata:** every `metadata.xml` uses
   `<maintainer type="project">` with
   `lucas.yamanishi@gmail.com` / `Lucas Yamanishi` and a
   `<remote-id>` matching the upstream (typically GitHub).
 - **Ebuild headers:** Gentoo Authors copyright + GPL-2
   notice, blank line, then `EAPI=7`.
 - **Keywords:** new ebuilds should use unstable keywords
   (`~amd64 ~arm64`, etc.) matching `profiles/arch.list`.
 - **License preference:** keep `LICENSE=` accurate to
   upstream; `OFL-1.1` for fonts, etc.
 - **`.gitignore`** excludes generated metadata
   (`metadata/md5-cache/`, `metadata/pkg_desc_index`,
   `profiles/use.local.desc`); never commit those.

## Working with this overlay

 - Validate ebuild/profile changes locally with
   `mise run check` (`pkgcheck scan --exit`) from the overlay
   root.  Regenerate manifests with `mise run manifest`, which
   uses the repo-local distdir and fails if a Manifest changed.
   The pre-commit hook runs both against the staged changes.
 - **Test builds** run through `mise run test-mojo` (one build)
   or `mise run test-matrix` (USE-flag matrix), which build the
   working tree via `PORTAGE_REPOSITORIES` — never the
   installed copy of the overlay.  Constraints, enforced by the
   task and by gitignored `.config/mise/config.local.toml` host
   config:
   - `PORTAGE_TMPDIR` and `DISTDIR` live under `.cache/agents/`
     (never system paths; build trees can reach ~8 GiB).
   - Builds are memory-capped with `choom -n 1000` so a runaway
     compile dies before the desktop does.
   - Core cap: set `MAKEOPTS` per host in the gitignored
     `.config/mise/config.local.toml`; never commit a host's
     value.
   - `TEST_MARCH` is required: dev-lang/mojo's upstream build
     defaults to `-march=x86-64-v3` and appends user CFLAGS
     after it, so a host older than v3 SIGILLs unless an
     explicit supported `-march` (e.g. `x86-64-v2`) is passed.
     Set it in `.config/mise/config.local.toml` next to
     `MAKEOPTS`.
 - To rebuild metadata cache (only for local use; do not
   commit): `egencache --update --repo=lamawithonel
   --jobs=$(nproc)`.
 - This overlay is registered on consumer systems via
   `repositories.xml` / `eselect repository`; profile paths
   are referenced as `lamawithonel:custom/<...>`.

## Vi modeline

 Some files (e.g. `profiles/profiles.desc`) end with a
 `# vi:ts=8:sw=8:noexpandtab` modeline — preserve hard tabs
 in those files.
