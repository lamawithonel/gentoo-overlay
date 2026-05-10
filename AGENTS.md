# lamawithonel's Gentoo Portage overlay

 This repository is a **Gentoo Portage overlay** (third-party
 ebuild repository) for the maintainer's personal use.  It is
 consumed by Portage on Gentoo systems, not built or tested as
 a normal software project.  There is no compile/lint/test
 toolchain checked into the repo.

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
 - `media-fonts/bitter/` — the only ebuild package currently
   in the overlay (EAPI 7, `inherit font`).  New packages
   follow the standard Gentoo `<category>/<pkg>/<pkg>-<ver>.
   ebuild` + `metadata.xml` + `Manifest` layout.

## Conventions

 - **EAPI:** 7 for ebuilds and profile `eapi` files.  EAPIs
   0–4 are banned and 5 is deprecated per `metadata/layout.
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
   `pkgcheck scan` and/or `repoman full` from inside the
   overlay root.  Regenerate manifests with
   `pkgdev manifest` (or `ebuild <pkg>.ebuild manifest`) in
   the package directory after changing `SRC_URI` or
   bumping a version.
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
