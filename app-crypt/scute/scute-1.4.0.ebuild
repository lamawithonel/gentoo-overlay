# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=3

inherit autotools

DESCRIPTION="A PKCS #11 module that adds support for the OpenPGP smartcard card
to the Mozilla NSS."
HOMEPAGE="http://www.scute.org/"
SRC_URI="
	#mirror://gnupg/gcrypt/scute/${P}.tar.bz2
	ftp://ftp.gnupg.org/gcrypt/scute/${P}.tar.bz2"

LICENSE="GPL-2"
SLOT="1"
KEYWORDS="~amd64"
IUSE="static-libs"

DEPEND="
	>=dev-libs/libgpg-error-1.4
	>=dev-libs/libassuan-2.0.0
	>=app-crypt/pinentry-0.7.0"
RDEPEND="
	|| (
		>=app-crypt/gnupg-2.0[openct]
		>=app-crypt/gnupg-2.0[pcsc-lite]
		>=app-crypt/gnupg-2.0[smartcard]
	)
	${DEPEND}"

src_prepare() {
	eautoreconf || die "eautoreconf failed"
	elibtoolize || die "elibtoolize failed"
	epunt_cxx || die "epunt_cxx failed"
}

src_configure() {
	econf $(use_enable static-libs static) || die "econf failed"
}

src_compile() {
	emake || die "emake failed"
}

src_install() {
	LIBDIR=$(get_libdir)
	dosym ../libscute.so usr/${LIBDIR}/pkcs11/libscute.so \
	|| die "dosym failed"
	emake DESTDIR="${D}" install || die "emake install failed"
	dodoc AUTHORS ChangeLog NEWS README TODO || die "dodoc failed"
}
