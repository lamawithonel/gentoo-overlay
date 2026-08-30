# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_{12..15} )

inherit check-reqs multiprocessing python-r1

# Snapshot of the modular monorepo main branch.  The Mojo compiler
# sources (KGEN/) were opened on 2026-08-18 and are not yet part of
# any release tag (newest tag max/v26.5.0 == mojo/v1.0.0 predates
# them), so we pin the "[Release] Pin lockfiles to Mojo
# 1.1.0.dev2026083005" commit and version this ebuild to match.
MY_COMMIT="f08ac164e2743513f60e46621de6dc4a5a5a30e7"

DESCRIPTION="The Mojo programming language: compiler, stdlib, LSP, and REPL"
HOMEPAGE="https://mojolang.org https://github.com/modular/modular"
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
IUSE="debug doc examples jupyter python test"
REQUIRED_USE="
	jupyter? ( debug )
	python? ( ${PYTHON_REQUIRED_USE} )
"

# network-sandbox: Bazel fetches its external inputs at build time
# (LLVM sources at a pinned commit, Bazel module deps from the Bazel
# Central Registry, and the hermetic host toolchains listed below).
# All fetches except bazelisk go through Bazel with pinned sha256
# integrity hashes.  Pre-fetching everything into DISTDIR is not
# practical yet: upstream commits no MODULE.bazel.lock, so the full
# URL set is not enumerable without running Bazel first.
RESTRICT="network-sandbox !test? ( test )"

# The mojo driver invokes the system "cc" to link `mojo build`
# executables at runtime (KGEN/tools/mojo/Build/mojo-build.cpp).
RDEPEND="
	|| (
		sys-devel/gcc
		llvm-core/clang
	)
	jupyter? ( dev-python/jupyter-client )
	python? ( ${PYTHON_DEPS} )
"
# Everything else is hermetic: upstream's Bazel build downloads and
# uses its own pinned clang, sysroot, and Python -- see src_compile.
BDEPEND="net-misc/curl"

pkg_pretend() {
	CHECKREQS_MEMORY="16G"
	# The debugger stack adds an LLDB-scale build on top of the
	# base LLVM+compiler build.
	if use debug; then
		CHECKREQS_DISK_BUILD="60G"
	else
		CHECKREQS_DISK_BUILD="40G"
	fi
	check-reqs_pkg_pretend
}

pkg_setup() {
	CHECKREQS_MEMORY="16G"
	if use debug; then
		CHECKREQS_DISK_BUILD="60G"
	else
		CHECKREQS_DISK_BUILD="40G"
	fi
	check-reqs_pkg_setup
	ewarn "This build downloads its Bazel toolchain and third-party"
	ewarn "sources (LLVM at a pinned commit, ~1 GiB total) at build"
	ewarn "time; the network sandbox is disabled for this package."
	ewarn "The Mojo compiler and standard library themselves are"
	ewarn "compiled entirely from source (--config=build-mojo)."
	ewarn ""
	ewarn "Upstream's toolchain defaults to -march=x86-64-v3.  On"
	ewarn "older CPUs the build itself dies with SIGILL (its just-"
	ewarn "built host tools use v3 instructions) unless CFLAGS and"
	ewarn "CXXFLAGS carry a -march your CPU supports (-march=native"
	ewarn "is fine); the user flag is appended last and wins."
}

src_prepare() {
	default
	# tools/bazel probes local GPUs (nvidia-smi/amd-smi) to seed
	# --local_resources, and aborts on hosts where amd-smi exists
	# without a usable GPU.  The result only matters for GPU test
	# scheduling, not for building the compiler, so pre-seed the
	# cache file the wrapper would otherwise generate.
	mkdir -p build || die
	echo "build --local_resources=gpu-memory=0" \
		> build/local-resources.bazelrc || die
}

src_configure() {
	default

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
	#
	# --//:modular_config=production is upstream's release profile
	# and the only value that disables assertions (-DNDEBUG,
	# -U_GLIBCXX_ASSERTIONS); the default profile ships with
	# assertions compiled in.  --//:release_type=production selects
	# the production telemetry endpoint and drops a dev-only run
	# wrapper.  The version stamps replace the "dev0 (deadbeef)"
	# placeholders in `mojo --version`.
	BAZEL_ARGS=(
		--compilation_mode=opt
		"--//:modular_config=production"
		"--//:release_type=production"
		"--//:mojo_base_version=$(ver_cut 1-3)"
		"--//:mojo_version_label=_${PV#*_}"
		"--//:modular_version_sha=${MY_COMMIT:0:10}"
		--jobs="$(makeopts_jobs)"
		--verbose_failures
		--color=no
		--curses=no
	)
	local flag
	for flag in ${CFLAGS}; do
		BAZEL_ARGS+=( "--conlyopt=${flag}" "--host_conlyopt=${flag}" )
	done
	for flag in ${CXXFLAGS}; do
		BAZEL_ARGS+=( "--cxxopt=${flag}" "--host_cxxopt=${flag}" )
	done
	for flag in ${LDFLAGS}; do
		BAZEL_ARGS+=( "--linkopt=${flag}" "--host_linkopt=${flag}" )
	done

	# Keep bazelisk's and Bazel's caches inside the build dir.
	export BAZELISK_HOME="${WORKDIR}/bazelisk-home"
}

# Run ./bazelw with the configured arguments.
emojo() {
	local cmd="$1"
	shift
	echo ./bazelw "${cmd}" --config=build-mojo "$@" >&2
	./bazelw --output_user_root="${WORKDIR}/bazel-root" \
		"${cmd}" --config=build-mojo "$@"
}

src_compile() {
	# --config=build-mojo builds the Mojo compiler from KGEN/
	# sources and registers it as the Mojo toolchain, so the
	# stdlib .mojoc below is compiled by the just-built compiler,
	# not by a downloaded nightly (bazel/internal/BUILD.bazel).
	local -a targets=(
		//KGEN/tools/mojo:mojo
		//KGEN/tools/mojo:docs
		//mojo/stdlib/std
		//KGEN:CompilerRT
		//KGEN/tools/mojo-lsp-server
		//KGEN/tools/mojo-repl-entry-point
		//AsyncRT:RuntimeGlobals
		//Support:Globals
	)
	# The debugger set mirrors the data deps of upstream's
	# mojo-full bundle (KGEN/tools/mojo/BUILD.bazel).
	use debug && targets+=(
		//KGEN:mojo-lldb
		//KGEN:MojoLLDB
		//KGEN:gdb-server
		//KGEN:copy-lldb-visualizers
		@llvm-project//lldb:lldb-argdumper
		@llvm-project//llvm:llvm-symbolizer
	)
	use jupyter && targets+=(
		//KGEN:MojoJupyter
		//KGEN/tools/mojo-jupyter-executor
	)
	use doc && targets+=( //mojo/stdlib/std:docs )

	emojo build "${BAZEL_ARGS[@]}" "${targets[@]}" \
		|| die "bazel build failed"
}

src_test() {
	# The stdlib test suite, run against the just-built compiler
	# (KGEN/docs/WorkingInOSRepo.md).
	emojo test "${BAZEL_ARGS[@]}" //mojo/stdlib/... \
		|| die "stdlib tests failed"
}

# Locate a unique build output under bazel-bin by trying each given
# name, dying loudly if none exist so layout changes upstream cannot
# yield broken installs.
mojo_out() {
	local name found
	for name in "$@"; do
		found="$(find -L "${S}/bazel-bin" -name "${name}" -type f -print -quit)"
		[[ -n ${found} ]] && { echo "${found}"; return; }
	done
	die "build output '$*' not found under bazel-bin"
}

src_install() {
	# Executables carry a Bazel-baked RPATH of $ORIGIN/../lib, so
	# bin/ and lib/ placement is load-bearing: the REPL entry point
	# lives in bin/ (modular.cfg overrides its default lib/ path)
	# and the shared libraries it and the driver NEED live in lib/.
	exeinto /usr/lib/mojo/bin
	doexe "$(mojo_out mojo)"
	doexe "$(mojo_out mojo-lsp-server)"
	doexe "$(mojo_out mojo-repl-entry-point)"

	# The driver resolves everything below relative to package_root
	# from /etc/modular/modular.cfg; see files/modular.cfg.
	exeinto /usr/lib/mojo/lib
	doexe "$(mojo_out libKGENCompilerRTShared.so)"
	doexe "$(mojo_out libAsyncRTRuntimeGlobals.so)"
	doexe "$(mojo_out libMSupportGlobals.so)"

	insinto /usr/lib/mojo/lib/mojo
	doins "$(mojo_out std.mojoc)"

	insinto /etc/modular
	doins "${FILESDIR}/modular.cfg"

	dosym ../lib/mojo/bin/mojo /usr/bin/mojo
	dosym ../lib/mojo/bin/mojo-lsp-server /usr/bin/mojo-lsp-server

	# Tablegen-generated man pages (FEATURES=noman filtering is
	# portage's job; we always install).
	local -a manpages
	mapfile -t manpages < \
		<(find -L "${S}/bazel-bin/KGEN/tools/mojo" -name '*.1' -type f)
	[[ ${#manpages[@]} -gt 0 ]] || die "no man pages found under bazel-bin"
	doman "${manpages[@]}"

	if use debug; then
		# lldb-server and lldb-argdumper must sit beside the
		# lldb binary to be found at runtime (KGEN/BUILD.bazel);
		# libMojoLLDB.so and the Python visualizers resolve via
		# modular.cfg defaults relative to package_root.
		exeinto /usr/lib/mojo/bin
		doexe "$(mojo_out mojo-lldb lldb)"
		doexe "$(mojo_out lldb-server gdb-server)"
		doexe "$(mojo_out lldb-argdumper)"
		doexe "$(mojo_out llvm-symbolizer)"
		exeinto /usr/lib/mojo/lib
		doexe "$(mojo_out libMojoLLDB.so)"
		insinto /usr/lib/mojo/lib
		doins "$(mojo_out lldbDataFormatters.py)"
		doins "$(mojo_out mlirDataFormatters.py)"
	fi

	if use jupyter; then
		exeinto /usr/lib/mojo/bin
		doexe "$(mojo_out mojo-jupyter-executor)"
		exeinto /usr/lib/mojo/lib
		doexe "$(mojo_out libMojoJupyter.so)"
		insinto /usr/lib/mojo/share/jupyter-mojo
		doins -r KGEN/utils/jupyter-mojo/.
	fi

	if use doc; then
		local stddocs="${S}/bazel-bin/mojo/stdlib/std/std.docs"
		[[ -d ${stddocs} ]] || die "std.docs output not found"
		insinto "/usr/share/doc/${PF}/stdlib-api"
		doins -r "${stddocs}"/.
		docompress -x "/usr/share/doc/${PF}/stdlib-api"
	fi

	if use examples; then
		insinto "/usr/share/doc/${PF}/examples"
		doins -r mojo/examples/.
		docompress -x "/usr/share/doc/${PF}/examples"
	fi

	if use python; then
		installmojopy() {
			python_domodule mojo/python/mojo
		}
		python_foreach_impl installmojopy
	fi

	dodoc README.md
	newdoc mojo/README.md README.mojo.md
}

pkg_postinst() {
	elog "Installed from source: mojo driver, standard library"
	elog "(std.mojoc), KGEN compiler runtime, mojo-lsp-server,"
	elog "and the REPL entry point."
	if ! use debug; then
		elog ""
		elog "'mojo debug' AND 'mojo repl' need the LLDB stack:"
		elog "enable USE=debug to install it."
	fi
	if use jupyter; then
		elog ""
		elog "To register the Mojo Jupyter kernel for your user:"
		elog "  python /usr/lib/mojo/share/jupyter-mojo/manage_kernel.py install"
	fi
	elog ""
	elog "'mojo format' requires mblack, which upstream only ships"
	elog "as a Python wheel with unverifiable dependencies; it is"
	elog "not installed.  The MAX platform is not built: parts of"
	elog "it are not open source."
}
