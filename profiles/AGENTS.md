# `profiles/` (lamawithonel overlay)

This directory is the Portage **profile tree** for the
`lamawithonel` Gentoo overlay.  It is consumed by Portage,
not built or tested by a normal toolchain.  See the
repository-root `AGENTS.md` for overlay-wide context; the
notes below are specific to working inside `profiles/`.

## Layout

- `arch.list` — supported arches for this overlay
  (`amd64`, `arm64`).  Any new profile or ebuild keywords
  must stay within this set.
- `profiles.desc` — registry of every shipped profile:
  `<arch> <path-under-profiles/> <stability>` where
  stability is `stable` or `exp`.  Ends with a
  `# vi:ts=8:sw=8:noexpandtab` modeline; the file uses
  **hard tabs** as field separators — preserve them.
- `custom/` — user-facing profile sets that consumers
  select via `eselect profile` as
  `lamawithonel:custom/<...>`:
  - `custom/base/` — common root; chains up to a
    stage-3-style Gentoo profile via `parent`.
  - `custom/plasma/{desktop,laptop}[/selinux]/`
  - `custom/server/arm64/{rpi3,rpi4}/`
- `features/` — non-selectable feature overlays pulled in
  via `parent` from other profiles
  (e.g. `features/selinux/systemd`).  Do not list these in
  `profiles.desc`.

## Profile directory contract

Every profile directory must contain:

- `eapi` — single line, currently `7`.  EAPIs 0–4 are
  banned and 5 is deprecated by `metadata/layout.conf`;
  do not introduce them here.
- `parent` — one entry per line.  Use `repo:path` for
  cross-repo references (e.g.
  `gentoo:default/linux/amd64/23.0/desktop/plasma/systemd`,
  `lamawithonel:custom/base`) and relative paths (`..`,
  `../selinux`) for in-tree inheritance.  All `custom/*`
  profiles ultimately chain through
  `lamawithonel:custom/base` to a Gentoo stage-3 profile.
- A matching entry in `profiles.desc` if the profile is
  user-selectable (everything under `custom/`).  Features
  under `features/` are inherited only.

## Customization files

Profile tunables use the standard Portage filenames:
`make.defaults`, `packages`, `package.use`,
`package.use.{force,mask}`, `package.accept_keywords`,
`package.mask`, `package.unmask`, `use.mask`.

When a name like `package.use` or `package.accept_keywords`
appears as a **directory**, this overlay splits entries
**one file per category** (e.g. `sys-kernel`,
`dev-python`, `kde-plasma`).  Keep that split when adding
entries — do not create a single flat file, and do not move
existing entries between category files.

Keywords for any new ebuild referenced from these files
should stay unstable (`~amd64`, `~arm64`) and within
`arch.list`.

## SELinux variants

`custom/.../selinux/` profiles inherit both the non-SELinux
sibling and `lamawithonel:features/selinux/systemd` via
`parent`.  When adding a new SELinux variant, mirror the
parent layout of an existing one (e.g.
`custom/plasma/desktop/selinux/parent`) rather than
inventing a new chain.

## Validation

From the overlay root (one directory up):

- `pkgcheck scan profiles/` — profile-aware lint.
- `repoman full` — legacy full check.

There is no automated CI in this repo; run the above
manually before committing profile changes.

## House style

- Hard tabs in `profiles.desc`; preserve any
  `# vi:ts=8:sw=8:noexpandtab` modelines.
- Comments and prose wrap before 80 columns (72 preferred),
  matching the repo-wide style in `AGENTS.md`.
- Commits: one logical profile change per commit,
  imperative mood, unsigned (matches overlay policy).
