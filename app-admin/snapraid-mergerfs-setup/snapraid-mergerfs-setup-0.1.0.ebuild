# Copyright 2025 Lucas Hall
# Distributed under the terms of the Apache License, Version 2.0

EAPI=8

inherit linux-info systemd

DESCRIPTION="SnapRAID + MergerFS + XFS bootstrap and ops tooling for Gentoo"
HOMEPAGE="https://github.com/lamawithonel/snapraid"

# All sources ship in ${FILESDIR}; nothing is fetched.
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+setup +systemd smart-tests test +doc"
# Test scripts are hardware-dependent; never run under FEATURES=test.
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

# Pure shell scripts; runtime tooling only.
RDEPEND="
	sys-fs/snapraid
	sys-fs/mergerfs
	sys-fs/xfsprogs
	sys-apps/smartmontools
	sys-apps/util-linux
	virtual/udev
	systemd? ( sys-apps/systemd )
"

# gum (charmbracelet) is required by all interactive helpers but
# has no Portage ebuild on the target host.  Operator must install
# it manually; pkg_pretend warns and pkg_postinst points at the
# release page.  helpers.sh detects gum at runtime and falls back
# to plain prompts where it can.

ALL_SCRIPTS=(
	helpers.sh
	snapraid-preflight
	snapraid-detect
	snapraid-format
	snapraid-fstab
	snapraid-genconf
	snapraid-first-sync
	snapraid-integrity-drill
	snapraid-runner
	snapraid-runner-interactive
	snapraid-enable-timers
	snapraid-tune-usb
	snapraid-recover
	snapraid-acceptance
)

src_unpack() {
	mkdir -p "${S}/files/systemd" || die
	local f
	for f in "${ALL_SCRIPTS[@]}"; do
		cp "${FILESDIR}/${f}" "${S}/files/${f}" || die
	done
	for f in snapraid-sync.service snapraid-sync.timer \
			snapraid-scrub.service snapraid-scrub.timer \
			snapraid-smart-long.service \
			snapraid-smart-long.timer; do
		cp "${FILESDIR}/systemd/${f}" \
			"${S}/files/systemd/${f}" || die
	done
}

src_prepare() {
	default

	# Rewrite install paths from the guide's /usr/local layout to
	# the conventional Portage layout.
	local f
	for f in "${S}"/files/snapraid-* "${S}"/files/systemd/*; do
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
			"${S}/files/${g}" || die "sed failed on ${g}"
	done
}

src_install() {
	# Helper library: always installed.
	insinto /usr/lib/snapraid-setup
	doins "${S}/files/helpers.sh"

	# Recovery: always installed.
	dosbin "${S}/files/snapraid-recover"

	if use setup; then
		local s
		for s in snapraid-preflight snapraid-detect \
				snapraid-format snapraid-fstab \
				snapraid-genconf snapraid-first-sync \
				snapraid-enable-timers snapraid-tune-usb; do
			dosbin "${S}/files/${s}"
		done
	fi

	if use systemd; then
		dosbin "${S}/files/snapraid-runner"
		dosbin "${S}/files/snapraid-runner-interactive"
		systemd_dounit "${S}/files/systemd/snapraid-sync.service"
		systemd_dounit "${S}/files/systemd/snapraid-sync.timer"
		systemd_dounit "${S}/files/systemd/snapraid-scrub.service"
		systemd_dounit "${S}/files/systemd/snapraid-scrub.timer"
		if use smart-tests; then
			systemd_dounit "${S}/files/systemd/snapraid-smart-long.service"
			systemd_dounit "${S}/files/systemd/snapraid-smart-long.timer"
		fi
	fi

	if use test; then
		dosbin "${S}/files/snapraid-integrity-drill"
		dosbin "${S}/files/snapraid-acceptance"
	fi

	if use doc; then
		dodoc "${FILESDIR}/snapraid-mergerfs-xfs-guide.md"
	fi

	keepdir /var/lib/snapraid-setup
	keepdir /var/log/snapraid
}

pkg_pretend() {
	if ! command -v gum >/dev/null 2>&1; then
		ewarn
		ewarn "gum (charmbracelet) is not on PATH."
		ewarn "All interactive helpers (snapraid-*-interactive,"
		ewarn "snapraid-recover, and the sr_confirm prompts) require it."
		ewarn "Install a release binary from:"
		ewarn "    https://github.com/charmbracelet/gum/releases"
		ewarn "Non-interactive scripts (snapraid-runner sync|scrub"
		ewarn "from systemd timers) work without it."
		ewarn
	fi
}

pkg_postinst() {
	elog
	elog "Recommended bootstrap sequence:"
	elog "    snapraid-preflight"
	elog "    snapraid-detect       # writes /etc/snapraid-roles.conf"
	elog "    snapraid-format       # destructive; confirm carefully"
	elog "    snapraid-fstab"
	elog "    snapraid-genconf"
	elog "    snapraid-first-sync"
	use systemd && elog "    snapraid-enable-timers"
	elog

	if use systemd; then
		elog "Reload systemd to pick up the new units:"
		elog "    systemctl daemon-reload"
		elog "Then either run snapraid-enable-timers or:"
		elog "    systemctl enable --now snapraid-sync.timer snapraid-scrub.timer"
		use smart-tests && elog \
			"    systemctl enable --now snapraid-smart-long.timer"
		elog
	fi

	if use smart-tests; then
		elog "smart-tests USE flag is ON: smart-long timer installed."
		elog "Verify your USB enclosure actually supports"
		elog "'smartctl -d sat -t long /dev/sdX' before relying on it."
		elog
	else
		elog "smart-tests USE flag is OFF (default): no smart-long"
		elog "timer is installed and snapraid-runner smart-long will"
		elog "exit non-zero.  USB enclosures rarely support SAT"
		elog "self-tests; rebuild with USE=smart-tests if yours does."
		elog
	fi

	if use setup && ! use systemd; then
		ewarn "USE=setup is ON but USE=systemd is OFF."
		ewarn "snapraid-enable-timers is installed but no unit"
		ewarn "files are; the script will report no-op."
	fi

	if ! command -v gum >/dev/null 2>&1; then
		ewarn
		ewarn "gum is still missing.  Install it from:"
		ewarn "    https://github.com/charmbracelet/gum/releases"
		ewarn
	fi
}
