# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit check-reqs multiprocessing

# Snapshot of the modular monorepo main branch.  The Mojo compiler
# sources (KGEN/) were opened on 2026-08-18 and are not yet part of
# any release tag (newest tag max/v26.5.0 == mojo/v1.0.0 predates
# them), so we pin the "[Release] Pin lockfiles to Mojo
# 1.1.0.dev2026083005" commit and version this ebuild to match.
MY_COMMIT="f08ac164e2743513f60e46621de6dc4a5a5a30e7"

DESCRIPTION="The Mojo programming language: compiler, stdlib, LSP, and REPL"
HOMEPAGE="https://www.modular.com/mojo https://github.com/modular/modular"
SRC_URI="https://github.com/modular/modular/archive/${MY_COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/modular-${MY_COMMIT}"

# Compiler, stdlib, and the from-source LLVM/MLIR are
# Apache-2.0-with-LLVM-exceptions.  The rest covers statically linked
# third-party Bazel deps: abseil/protobuf/grpc (Apache-2.0), zstd/
# google-benchmark (BSD), fmt (MIT), zlib-ng (ZLIB).  The proprietary
# "Modular MAX Community License" covers only Modular's prebuilt MAX
# packages, none of which are fetched or installed by this ebuild.
LICENSE="Apache-2.0-with-LLVM-exceptions Apache-2.0 BSD MIT ZLIB"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# network-sandbox: Bazel fetches its external inputs at build time
# (LLVM sources at a pinned commit, Bazel module deps from the Bazel
# Central Registry, and the hermetic host toolchains listed below).
# All fetches except bazelisk go through Bazel with pinned sha256
# integrity hashes.  Pre-fetching everything into DISTDIR is not
# practical yet: upstream commits no MODULE.bazel.lock, so the full
# URL set is not enumerable without running Bazel first.
RESTRICT="network-sandbox"

# The mojo driver invokes the system "cc" to link `mojo build`
# executables at runtime (KGEN/tools/mojo/Build/mojo-build.cpp).
RDEPEND="
	|| (
		sys-devel/gcc
		llvm-core/clang
	)
"
# Everything else is hermetic: upstream's Bazel build downloads and
# uses its own pinned clang, sysroot, and Python -- see src_compile.
BDEPEND="net-misc/curl"

CHECKREQS_DISK_BUILD="40G"
CHECKREQS_MEMORY="16G"

pkg_pretend() {
	check-reqs_pkg_pretend
}

pkg_setup() {
	check-reqs_pkg_setup
	ewarn "This build downloads its Bazel toolchain and third-party"
	ewarn "sources (LLVM at a pinned commit, ~1 GiB total) at build"
	ewarn "time; the network sandbox is disabled for this package."
	ewarn "The Mojo compiler and standard library themselves are"
	ewarn "compiled entirely from source (--config=build-mojo)."
}

src_compile() {
	# Upstream hard-disables the host toolchain (bazel/internal/
	# common.bazelrc: --repo_env=CC=false, CXX=false,
	# BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1) and compiles everything
	# with a hermetic clang + sysroot; --incompatible_strict_action_env
	# additionally strips CFLAGS/CXXFLAGS/LDFLAGS from the action
	# environment.  This is a documented upstream requirement, so
	# instead of exporting toolchain variables we re-inject the
	# user's flags through Bazel options.  --conlyopt/--cxxopt/
	# --linkopt reach every target-configuration compile, including
	# the @llvm-project sub-build (external repos build in the
	# target configuration); the --host_* twins cover
	# exec-configuration tools (tablegen and friends), so e.g. a
	# user -march=<value> reaches every compilation stage.
	local -a bazel_opts=(
		--compilation_mode=opt
		--jobs="$(makeopts_jobs)"
		--verbose_failures
		--color=no
		--curses=no
	)
	local flag
	for flag in ${CFLAGS}; do
		bazel_opts+=( "--conlyopt=${flag}" "--host_conlyopt=${flag}" )
	done
	for flag in ${CXXFLAGS}; do
		bazel_opts+=( "--cxxopt=${flag}" "--host_cxxopt=${flag}" )
	done
	for flag in ${LDFLAGS}; do
		bazel_opts+=( "--linkopt=${flag}" "--host_linkopt=${flag}" )
	done

	# Keep bazelisk's and Bazel's caches inside the build dir.
	export BAZELISK_HOME="${WORKDIR}/bazelisk-home"

	# --config=build-mojo builds the Mojo compiler from KGEN/
	# sources and registers it as the Mojo toolchain, so the
	# stdlib .mojopkg below is compiled by the just-built compiler,
	# not by a downloaded nightly (bazel/internal/BUILD.bazel).
	./bazelw --output_user_root="${WORKDIR}/bazel-root" \
		build --config=build-mojo "${bazel_opts[@]}" \
		//KGEN/tools/mojo:mojo \
		//mojo/stdlib/std \
		//KGEN:CompilerRT \
		//KGEN/tools/mojo-lsp-server \
		//KGEN/tools/mojo-repl-entry-point \
		|| die "bazel build failed"
}

# Locate a unique build output under bazel-bin, dying loudly if it
# is missing so layout changes upstream cannot yield broken installs.
mojo_out() {
	local found
	found="$(find -L "${S}/bazel-bin" -name "$1" -type f -print -quit)"
	[[ -n ${found} ]] || die "build output '$1' not found under bazel-bin"
	echo "${found}"
}

src_install() {
	exeinto /usr/lib/mojo/bin
	doexe "$(mojo_out mojo)"
	doexe "$(mojo_out mojo-lsp-server)"

	# The driver resolves everything below relative to package_root
	# from /etc/modular/modular.cfg; see files/modular.cfg.
	exeinto /usr/lib/mojo/lib
	doexe "$(mojo_out libKGENCompilerRTShared.so)"
	doexe "$(mojo_out mojo-repl-entry-point)"

	insinto /usr/lib/mojo/lib/mojo
	doins "$(mojo_out std.mojopkg)"

	insinto /etc/modular
	doins "${FILESDIR}/modular.cfg"

	dosym ../lib/mojo/bin/mojo /usr/bin/mojo
	dosym ../lib/mojo/bin/mojo-lsp-server /usr/bin/mojo-lsp-server

	dodoc README.md mojo/README.md
}

pkg_postinst() {
	elog "Installed from source: mojo driver, standard library"
	elog "(std.mojopkg), KGEN compiler runtime, mojo-lsp-server,"
	elog "and the REPL entry point."
	elog ""
	elog "Not installed: 'mojo debug' (needs the Mojo LLDB build),"
	elog "'mojo format' (needs the mblack Python wheel), and the"
	elog "MAX platform, parts of which are not open source."
}
