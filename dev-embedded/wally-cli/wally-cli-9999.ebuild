# Copyright 2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# SPDX-License-Identifier: GPL-2.0-only

EAPI=7

inherit go-module

DESCRIPTION="Flash your ZSA keyboard the EZ way"
HOMEPAGE="https://ergodox-ez.com/pages/wally"
LICENSE="MIT"

SLOT="0"
EGO_PN="github.com/zsa/wally-cli"
EGIT_REPO_URI="https://${EGO_PN}.git"

if [[ ${PV} = *9999* ]]; then
	inherit git-r3

	src_unpack() {
		git-r3_src_unpack
		go-module_live_vendor
	}
else
	KEYWORDS="~amd64 ~x86"
	EGIT_COMMIT="e488ddd9fa0aa4c9e6f42ace68937d81989b2078"

	SRC_URI="https://${EGO_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	SRC_URI+=" https://github.com/lamawithonel/gentoo-overlay/raw/master/${CATEGORY}/${PN}/files/${P}-deps.tar.xz"
	S="${WORKDIR}/${PN}-${EGIT_COMMIT}"
fi

src_compile() {
	ego build
}

src_install() {
	dobin "${PN}"
	dodoc README.md
}
