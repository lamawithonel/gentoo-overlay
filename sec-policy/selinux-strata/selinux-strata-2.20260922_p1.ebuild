# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MODS="strata"
POLICY_FILES="strata.te strata.fc strata.if"

inherit selinux-policy-2

DESCRIPTION="SELinux policy for sci-ml/strata"

KEYWORDS="~amd64 ~arm64"

# semanage labels the server port in pkg_postinst and pkg_postrm.
IDEPEND="sys-apps/selinux-python"

pkg_postinst() {
	selinux-policy-2_pkg_postinst

	# semanage has no ROOT option and would edit the build host's store.
	if [[ -n ${ROOT} ]]; then
		elog "Label the Strata port on the target system with:"
		elog "  semanage port -a -t strata_port_t -p tcp 8095"
		return
	fi

	# acct-user/strata owns /var/lib/strata and may merge before this
	# module, and the eclass relabels only packages that depend on it.
	[[ -d ${EROOT}/var/lib/strata ]] && restorecon -R "${EROOT}"/var/lib/strata
	# udev labels /dev/kfd only when it creates the node at boot, and an
	# older strata module left its own hsa_device_t label on it.
	[[ -c /dev/kfd ]] && restorecon /dev/kfd

	# Label every store the eclass loads the module into (EAPI 8 picks
	# them by USE, not POLICY_TYPES).  -m covers a port that already
	# carries a local label.
	local store
	for store in targeted strict mcs mls; do
		use selinux_policy_types_${store} || continue
		semanage port -S ${store} -a -t strata_port_t -p tcp 8095 2>/dev/null \
			|| semanage port -S ${store} -m -t strata_port_t -p tcp 8095 \
			|| ewarn "Failed to label tcp 8095 as strata_port_t in the ${store} store."
	done
}

pkg_postrm() {
	# Drop the port label before the eclass unloads the module: a local
	# port label that still names strata_port_t blocks the removal.
	if [[ -z ${ROOT} && -z ${REPLACED_BY_VERSION} ]]; then
		local store
		for store in targeted strict mcs mls; do
			use selinux_policy_types_${store} || continue
			semanage port -S ${store} -d -p tcp 8095 \
				|| ewarn "Failed to remove the strata_port_t label from tcp 8095 in the ${store} store."
		done
	fi

	selinux-policy-2_pkg_postrm
}
