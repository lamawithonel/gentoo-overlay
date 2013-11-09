# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=3

PYTHON_DEPEND="2"

inherit python

DESCRIPTION="Python Video Entropy Daemon to seed /dev/random."
HOMEPAGE="http://www.cleeus.de/cms/component/option,com_mojo/Itemid,72/p,44/index.html"
SRC_URI="http://www.cleeus.de/pyentropyd/pyved-0.0.1.tgz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"
IUSE=""

DEPEND=">=dev-lang/python-2.6 >=dev-python/pygame-1.9.1"
RDEPEND=">=sys-apps/rng-tools-3 ${DEPEND}"

src_unpack()
{
	if [ ${A} != "" ]; then
		unpack ${A}
	else
		return 1
	fi
	return 0
}

src_install()
{
	return 0
}

pkg_postinst()
{
	elog "You'll need to edit the rngd service defaults or your random bits will never
	make it to /dev/random.  To do this edit
	/etc/conf.d/rndg and set the default device to /dev/vrandom.  If you'd like
	to make it something else you can edit this default in /etc/conf.d/pyved"
	return 0
}

pkg_config()
{
	return 0
}
