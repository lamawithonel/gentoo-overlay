# Copyright 2025 Lucas Hall
# Distributed under the terms of the Apache License, Version 2.0

EAPI=8

inherit git-r3 linux-info systemd

DESCRIPTION="SnapRAID + MergerFS + XFS bootstrap and ops tooling for Gentoo (live)"
HOMEPAGE="https://github.com/lamawithonel/snapraid"
EGIT_REPO_URI="https://github.com/lamawithonel/snapraid.git"
EGIT_BRANCH="main"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS=""
IUSE="+setup +systemd smart-tests test +doc"
RESTRICT="!test? ( test )"

# Kernel I/O scheduler hints.  snapraid-tune-usb's udev rule asks
# the kernel to set BFQ on USB whole-disks (and falls back to
# mq-deadline if BFQ is unavailable).  Neither is strictly
# required -- 'none' will work -- but BFQ gives the best HDD
# latency under mixed scrub/sync load.  The leading '~' makes
# linux-info warn rather than die when the option is missing.
CONFIG_CHECK="~IOSCHED_BFQ ~MQ_IOSCHED_DEADLINE"
ERROR_IOSCHED_BFQ="
CONFIG_IOSCHED_BFQ is not enabled in your kernel.
snapraid-tune-usb installs a udev rule that prefers the BFQ
I/O scheduler for USB-attached HDDs (best latency under mixed
scrub/sync load).  Without BFQ, the rule falls back to
mq-deadline (also recommended below); if neither is present
the kernel default ('none' on multi-queue blk-mq) is used and
performance under load may suffer.

Enable with: Block layer ---> IO Schedulers --->
<M> BFQ I/O scheduler
"
ERROR_MQ_IOSCHED_DEADLINE="
CONFIG_MQ_IOSCHED_DEADLINE is not enabled in your kernel.
This is the fallback scheduler used by snapraid-tune-usb when
BFQ is unavailable.  Without either, USB HDDs will run on the
default 'none' scheduler.

Enable with: Block layer ---> IO Schedulers --->
<M> MQ deadline I/O scheduler
"

RDEPEND="
	sys-fs/snapraid
	sys-fs/mergerfs
	sys-fs/xfsprogs
	sys-apps/smartmontools
	sys-apps/util-linux
	virtual/udev
	systemd? ( sys-apps/systemd )
"

# Path inside the cloned repo where the package files live.
SR_FILES_REL="app-admin/snapraid-mergerfs-setup/files"

src_prepare() {
	default

	local f
	for f in "${S}/${SR_FILES_REL}"/snapraid-* \
			"${S}/${SR_FILES_REL}"/systemd/*; do
		sed -i \
			-e 's|/usr/local/sbin/snapraid-|/usr/sbin/snapraid-|g' \
			-e 's|/usr/local/lib/snapraid-helpers\.sh|/usr/lib/snapraid-setup/helpers.sh|g' \
			"${f}" || die "sed failed on ${f}"
	done

	# Smart-long build-time gate.  The @SMART_LONG_ENABLED@ token
	# expands to 1 when the smart-tests USE flag is set, 0 otherwise.
	# All scripts that conditionally run, enable, or assert the
	# snapraid-smart-long.timer must be substituted here.
	local enabled=0
	use smart-tests && enabled=1
	local g
	for g in snapraid-runner snapraid-runner-interactive \
			snapraid-enable-timers snapraid-acceptance; do
		sed -i "s|@SMART_LONG_ENABLED@|${enabled}|g" \
			"${S}/${SR_FILES_REL}/${g}" || die "sed failed on ${g}"
	done
}

src_install() {
	local F="${S}/${SR_FILES_REL}"

	insinto /usr/lib/snapraid-setup
	doins "${F}/helpers.sh"

	dosbin "${F}/snapraid-recover"

	if use setup; then
		local s
		for s in snapraid-preflight snapraid-detect \
				snapraid-format snapraid-fstab \
				snapraid-genconf snapraid-first-sync \
				snapraid-enable-timers snapraid-tune-usb; do
			dosbin "${F}/${s}"
		done
	fi

	if use systemd; then
		dosbin "${F}/snapraid-runner"
		dosbin "${F}/snapraid-runner-interactive"
		systemd_dounit "${F}/systemd/snapraid-sync.service"
		systemd_dounit "${F}/systemd/snapraid-sync.timer"
		systemd_dounit "${F}/systemd/snapraid-scrub.service"
		systemd_dounit "${F}/systemd/snapraid-scrub.timer"
		if use smart-tests; then
			systemd_dounit "${F}/systemd/snapraid-smart-long.service"
			systemd_dounit "${F}/systemd/snapraid-smart-long.timer"
		fi
	fi

	if use test; then
		dosbin "${F}/snapraid-integrity-drill"
		dosbin "${F}/snapraid-acceptance"
	fi

	if use doc; then
		dodoc "${FILESDIR}/snapraid-mergerfs-xfs-guide.md"
	fi

	keepdir /var/lib/snapraid-setup
	keepdir /var/log/snapraid
}

pkg_pretend() {
	if ! command -v gum >/dev/null 2>&1; then
		ewarn "gum (charmbracelet) is not on PATH; interactive"
		ewarn "helpers will not work.  Install from:"
		ewarn "    https://github.com/charmbracelet/gum/releases"
	fi
}

pkg_postinst() {
	elog "See pkg_postinst of snapraid-mergerfs-setup-0.1.0 for"
	elog "the full bootstrap and timer-enable cookbook.  This is"
	elog "the live ebuild; expect breakage."
}
