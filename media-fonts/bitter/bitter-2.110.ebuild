# Copyright 2018-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="Bitter"
inherit font

DESCRIPTION="A contemporary slab serif typeface for text, designed for comfortably reading"
HOMEPAGE="https://huertatipografica.com/en/fonts/bitter-ht"
SRC_URI="https://github.com/solmatas/${MY_PN}/archive/v.${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_PN}-v.${PV}"

LICENSE="OFL-1.1"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~x86"

DOCS="CONTRIBUTORS.txt README.md"
FONT_S="${S}/fonts/ttf"
FONT_SUFFIX="ttf"
