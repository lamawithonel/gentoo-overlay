# Copyright 1999-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit autotools systemd

DESCRIPTION="Distributed compiling of C(++) code across several machines; based on distcc"
HOMEPAGE="https://github.com/icecc/icecream"
SRC_URI="https://github.com/icecc/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="firewalld systemd"

DEPEND="
	acct-user/icecream
	acct-group/icecream
	sys-libs/libcap-ng
	app-text/docbook2X
	app-arch/zstd
"
RDEPEND="
	${DEPEND}
	dev-util/shadowman
	firewalld? ( net-firewall/firewalld )
	systemd? ( sys-apps/systemd )
"

AT_NOELIBTOOLIZE='yes'

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	econf \
		--enable-clang-rewrite-includes \
		--enable-clang-wrappers \
		--disable-fast-install
}

src_install() {
	default
	find "${D}" -name '*.la' -delete || die

	if use systemd; then
		systemd_dounit "${FILESDIR}/iceccd.service"
		systemd_dounit "${FILESDIR}/icecc-scheduler.service"

		insinto /etc/tmpfiles.d
		newins "${FILESDIR}/icecream-tmpfiles.conf" icecream.conf

		keepdir /var/log/icecc
		fowners icecream:icecream /var/log/icecc
		fperms  0750              /var/log/icecc
	else
		newconfd suse/sysconfig.icecream icecream
		newinitd "${FILESDIR}/icecream-r2" icecream
	fi

	insinto /etc/logrotate.d
	newins suse/logrotate icecream

	if use firewalld; then
		insinto /usr/lib/firewalld/services
		doins "${FILESDIR}/iceccd.xml"
		doins "${FILESDIR}/icecc-scheduler.xml"
	fi

	insinto /usr/share/shadowman/tools
	newins - icecc <<<'/usr/libexec/icecc/bin'
}

pkg_prerm() {
	if [[ -z ${REPLACED_BY_VERSION} && ${ROOT} == / ]]; then
		eselect compiler-shadow remove icecc
	fi
}

pkg_postinst() {
	if [[ ${ROOT} == / ]]; then
		eselect compiler-shadow update icecc
	fi
}
