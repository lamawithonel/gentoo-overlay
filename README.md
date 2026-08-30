gentoo-overlay
==============

Miscellaneous Gentoo ebuilds

## Usage

Register the overlay with `eselect repository` and sync it:

    eselect repository add lamawithonel git https://github.com/lamawithonel/gentoo-overlay.git
    emaint sync -r lamawithonel

Profiles ship under `profiles/custom/` and are referenced as
`lamawithonel:custom/<...>`.

## Development

Repo tooling is managed by [mise](https://mise.jdx.dev/) with
[hk](https://hk.jdx.dev/) git hooks:

    mise install       # pinned pkgcheck + pkgdev
    mise run setup     # install the git hooks
    mise run check     # pkgcheck scan over the whole overlay
    mise run manifest  # regenerate manifests, fail on drift

See `AGENTS.md` for layout, conventions, and test-build
constraints.

## License

GPL-2 (see `LICENSE`), matching the ebuild headers.
