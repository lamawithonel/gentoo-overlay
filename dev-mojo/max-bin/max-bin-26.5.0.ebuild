# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Modular's closed-source MAX + prebuilt Mojo compiler stack,
# repackaged from the official PyPI wheels.  This exists because GPU
# codegen and launch live only inside Modular's prebuilt compiler:
# the open-source tree used by dev-lang/mojo registers only the Host
# target (KGEN/lib/Target/) and has no plugin path for accelerator
# lowerings, so a from-source build can never drive a GPU.
#
# The stack installs self-contained under /opt/modular-max with an
# env-wired `mojo-max` launcher, deliberately independent of
# dev-lang/mojo and its /etc/modular/modular.cfg.
#
# Versions move in lockstep across Modular's PyPI tree: MAX-side
# wheels carry 26.5.0 (= PV) while the Mojo-side wheels carry 1.0.0.
# Nightlies exist only on dl.modular.com and get pruned, so only the
# permanent files.pythonhosted.org releases are fit for SRC_URI.
MOJO_PV="1.0.0"

DESCRIPTION="Modular MAX platform with the prebuilt Mojo compiler (GPU support)"
HOMEPAGE="https://www.modular.com/max https://pypi.org/project/max-core/"
SRC_URI="
	https://files.pythonhosted.org/packages/6b/10/c6d6e504cf5a89861691f0efd4e7f281291d90fd16ac767cd4a0ae1148bf/max_core-${PV}-py3-none-manylinux_2_34_x86_64.whl
	https://files.pythonhosted.org/packages/57/ea/e942472029ecd8058a790663ddaaab3ec4f06c4438da52031dd59fdd18d4/max_mojo_libs-${PV}-py3-none-any.whl
	https://files.pythonhosted.org/packages/f0/5f/f38fefe327d1c81e28def69c4a52ae4f75e389cb6e613a2c04ca8d68d582/mojo_compiler-${MOJO_PV}-py3-none-manylinux_2_34_x86_64.whl
	https://files.pythonhosted.org/packages/54/99/ea401ff1db56a4af8607283b95627e01b986fc67f510715b07f100118105/mojo_compiler_mojo_libs-${MOJO_PV}-py3-none-any.whl
"
S="${WORKDIR}"

LICENSE="MAX-Platform-Software-License"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="cuda rocm"

# The governing Modular Community License Terms (Apr 12, 2025; these
# wheels predate the Aug 18, 2026 rewrite) prohibit redistributing
# the SDK "or any part thereof" (s.1) -- no Gentoo mirrors, no binary
# packages -- and prohibit modifying it (s.2(a)) -- no stripping, no
# patchelf.  Personal, non-production use is explicitly unrestricted
# (s.2.1: "No capacity restrictions for any usage, on any physical
# devices").
RESTRICT="mirror bindist strip"

# manylinux_2_34 wheels (glibc-only; nothing to depend on under
# musl, where these binaries simply cannot run).  GPU userlands are
# dlopened at runtime, so the flags only pull the right stack in.
RDEPEND="
	elibc_glibc? ( >=sys-libs/glibc-2.34 )
	cuda? ( x11-drivers/nvidia-drivers )
	rocm? ( dev-util/hip )
"
BDEPEND="app-arch/unzip"

QA_PREBUILT="opt/modular-max/*"

MAX_ROOT="/opt/modular-max"

src_unpack() {
	# Wheels are zip files portage does not unpack natively; keep
	# each in its own directory so the dist-info trees cannot
	# collide.
	local f
	for f in ${A}; do
		unzip -qo "${DISTDIR}/${f}" -d "${WORKDIR}/${f%.whl}" \
			|| die "unpacking ${f} failed"
	done
}

src_install() {
	# Every wheel stages its payload under <name>.data/platlib/
	# modular/{bin,lib,lib/mojo}; the trees are designed to merge
	# into one prefix.  cp -a preserves the shipped permissions and
	# symlinks; the license forbids altering the binaries, so they
	# are installed exactly as published.
	dodir "${MAX_ROOT}"
	local d
	for d in "${WORKDIR}"/*/*.data/platlib/modular; do
		cp -a "${d}/." "${ED}${MAX_ROOT}/" || die "merging ${d} failed"
	done
	# The MAX C API headers sit at the max-core wheel root, outside
	# platlib.
	cp -a "${WORKDIR}"/max_core-*/max/include "${ED}${MAX_ROOT}/" || die

	# Wheel zip entries carry world-writable modes; normalizing
	# permission bits alters no SDK content.  (The remaining QA
	# notice about libibverbs/librdmacm/libfabric sonames is the
	# nixl RDMA transport plugins, dlopened only on fabrics that
	# have those stacks.)
	find "${ED}${MAX_ROOT}" -perm /o+w -exec chmod o-w {} + || die

	# Sanity: the two files the mojo driver actually probes.
	# lib/libmax.so is the isMaxInstalled() marker
	# (Support/lib/Configuration.cpp), bin/mojo is the closed
	# compiler everything routes through.
	[[ -x ${ED}${MAX_ROOT}/bin/mojo ]] \
		|| die "prebuilt mojo compiler missing from image"
	[[ -e ${ED}${MAX_ROOT}/lib/libmax.so ]] \
		|| die "libmax.so (MAX marker library) missing from image"

	# Env-wired launcher: the same variable seam Modular's own pip
	# launcher uses (mojo/python/mojo/run.py), so nothing here
	# touches dev-lang/mojo's /etc/modular/modular.cfg.
	cat > "${T}"/mojo-max <<-EOF || die
		#!/bin/sh
		export MODULAR_MAX_PACKAGE_ROOT="${MAX_ROOT}"
		export MODULAR_MOJO_MAX_PACKAGE_ROOT="${MAX_ROOT}"
		export MODULAR_MOJO_MAX_IMPORT_PATH="${MAX_ROOT}/lib/mojo"
		export MODULAR_MOJO_MAX_DRIVER_PATH="${MAX_ROOT}/bin/mojo"
		exec "${MAX_ROOT}/bin/mojo" "\$@"
	EOF
	exeinto /usr/bin
	newexe "${T}"/mojo-max mojo-max
}

pkg_postinst() {
	ewarn "These are Modular's prebuilt binaries, compiled for"
	ewarn "x86-64-v3 (AVX2).  On older CPUs (x86-64-v2 and below)"
	ewarn "they die with SIGILL -- there is no rebuild option; the"
	ewarn "sources are closed."
	ewarn ""
	ewarn "AMD GPU support: RDNA3 (e.g. gfx1100 / RX 7900) is in"
	ewarn "Modular's 'Known compatible' tier, not the continuously"
	ewarn "tested CDNA tier.  The runtime dlopens the host HIP/ROCm"
	ewarn "userland (USE=rocm pulls dev-util/hip)."
	elog ""
	elog "Use 'mojo-max' to invoke the prebuilt toolchain; it is"
	elog "fully independent of dev-lang/mojo's 'mojo'."
}
