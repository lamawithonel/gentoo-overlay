# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
# Limit AMDGPU_TARGETS to the wave32 archs upstream builds kernels for;
# defaults follow rocm.eclass (ROCm 7 official archs on).
ROCM_SKIP_GLOBALS=1

inherit cmake git-r3 python-single-r1 rocm systemd toolchain-funcs

DESCRIPTION="Inference engine and OpenAI-compatible server for large language models"
HOMEPAGE="https://github.com/Niko1221/Strata"
EGIT_REPO_URI="https://github.com/Niko1221/Strata.git"

# OFL-1.1: the web UI's font
LICENSE="MIT OFL-1.1"
SLOT="0"
KEYWORDS=""

AMDGPU_OFFICIAL=( gfx1030 gfx1100 gfx1101 gfx1200 gfx1201 )
AMDGPU_UNOFFICIAL=( gfx1031 gfx1102 gfx1151 )
AMDGPU_FLAGS=( "${AMDGPU_OFFICIAL[@]/#/amdgpu_targets_}" "${AMDGPU_UNOFFICIAL[@]/#/amdgpu_targets_}" )
ROCM_REQUIRED_USE=" || ( ${AMDGPU_FLAGS[*]} )"
ROCM_USEDEP=$(printf '%s(-)?,' "${AMDGPU_FLAGS[@]}")
ROCM_USEDEP=${ROCM_USEDEP%,}

IUSE="
	${AMDGPU_OFFICIAL[*]/#/+amdgpu_targets_} ${AMDGPU_UNOFFICIAL[*]/#/amdgpu_targets_}
	cpu_flags_x86_avx cpu_flags_x86_avx2 cpu_flags_x86_bmi2 cpu_flags_x86_f16c
	cpu_flags_x86_fma3 cpu_flags_x86_popcnt cpu_flags_x86_sse4_2
	+rocm selinux test
"
# The engine's lowest CPU floor (STRATA_ISA_FLOOR=none) is SSE4.2 + POPCNT.
REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	cpu_flags_x86_popcnt cpu_flags_x86_sse4_2
	rocm ${ROCM_REQUIRED_USE}
"
RESTRICT="!test? ( test )"

PYTHON_RDEPEND="
	$(python_gen_cond_dep '
		dev-python/jinja2[${PYTHON_USEDEP}]
		dev-python/numpy[${PYTHON_USEDEP}]
		dev-python/pillow[${PYTHON_USEDEP}]
		dev-python/psutil[${PYTHON_USEDEP}]
		dev-python/pyyaml[${PYTHON_USEDEP}]
		dev-python/regex[${PYTHON_USEDEP}]
		dev-python/requests[${PYTHON_USEDEP}]
		dev-python/tqdm[${PYTHON_USEDEP}]
	')
"
DEPEND="
	rocm? (
		dev-util/hip:=
		sci-libs/hipBLAS:=[${ROCM_USEDEP}]
		sci-libs/rocBLAS:=[${ROCM_USEDEP}]
	)
"
RDEPEND="
	${DEPEND}
	${PYTHON_DEPS}
	${PYTHON_RDEPEND}
	acct-group/strata
	acct-user/strata
	sci-ml/huggingface_hub
	selinux? ( sec-policy/selinux-strata )
"
BDEPEND="
	${PYTHON_DEPS}
	test? (
		${PYTHON_RDEPEND}
		$(python_gen_cond_dep 'dev-python/pytest[${PYTHON_USEDEP}]')
	)
"

PATCHES=(
	"${FILESDIR}"/${PN}-0.1.45-packaged-mode.patch
)

EPYTEST_PLUGINS=()

# portable (AVX2 release baseline), avx, or none; recorded in BUILD.json
_strata_isa_floor() {
	if use cpu_flags_x86_avx2 && use cpu_flags_x86_fma3 &&
		use cpu_flags_x86_f16c && use cpu_flags_x86_bmi2; then
		echo portable
	elif use cpu_flags_x86_avx; then
		echo avx
	else
		echo none
	fi
}

src_unpack() {
	git-r3_src_unpack

	# setup.py pins the llama.cpp commit that CMakeLists.txt also fetches
	local uri=https://github.com/ggml-org/llama.cpp.git commit
	commit=$(sed -n 's/^LLAMA_CPP_COMMIT = "\([0-9a-f]\{40\}\)"$/\1/p' "${S}"/setup.py) || die
	[[ -n ${commit} ]] || die "LLAMA_CPP_COMMIT not found in setup.py"
	git-r3_fetch ${uri} ${commit} ${CATEGORY}/${PN}/llama.cpp
	git-r3_checkout ${uri} "${S}"/third_party/llama.cpp ${CATEGORY}/${PN}/llama.cpp
}

src_configure() {
	local floor=$(_strata_isa_floor)
	local archs=$(get_amdgpu_flags)
	# upstream's HIP flags (setup.py build_engine_hip)
	local mycmakeargs=(
		-DGGML_NATIVE=OFF
		-DSTRATA_GGML_DIR="${S}"/third_party/llama.cpp
		-DSTRATA_ENABLE_CUDA=OFF
		-DSTRATA_ENABLE_HIP=$(usex rocm)
		-DSTRATA_BUILD_TESTS=OFF
		-DSTRATA_PREFILL_MMQ=ON
		-DSTRATA_Q6K_EXPERTS=ON
		-DSTRATA_MMQ_KQUANTS=ON
		-DCMAKE_HIP_ARCHITECTURES="${archs%;}"
		-DCMAKE_HIP_COMPILER="$(tc-getHIPCXX)"
		# found automagically otherwise
		-DCMAKE_DISABLE_FIND_PACKAGE_hipblaslt=ON
	)
	if [[ ${floor} == portable ]]; then
		mycmakeargs+=( -DSTRATA_PORTABLE=ON )
	else
		mycmakeargs+=( -DSTRATA_ISA_FLOOR=${floor} )
	fi
	cmake_src_configure
}

src_compile() {
	cmake_src_compile strata
}

src_test() {
	local EPYTEST_DESELECT=(
		# These read the build host's CPU: without AVX2 the stamped engine is stale, so the compile path runs
		tools/test_setup_choices.py::HipVision::test_the_cpu_encoder_is_built_once
		tools/test_setup_choices.py::HipVision::test_without_images_nothing_changes
		tools/test_setup_choices.py::CudaVision::test_the_encoder_is_built_native
		# get_prebuilt() HEADs the live GitHub release asset
		tools/test_setup_engine_hash.py::WhatARefusalDoesToTheCaller::test_a_first_install_stops_because_there_is_nothing_to_fall_back_to
		tools/test_setup_engine_hash.py::WhatARefusalDoesToTheCaller::test_updating_keeps_the_installed_engine_instead_of_stopping
	)
	epytest -p no:cacheprovider serve/test_*.py tools/test_setup_*.py
}

src_install() {
	local root=/usr/lib/strata archs=$(get_amdgpu_flags)

	insinto ${root}
	doins -r data serve setup.py
	# Qwen Community License, not redistributable under MIT
	rm -r "${ED}"${root}/data/experimental-speed-projection || die
	rm "${ED}"${root}/serve/test_*.py || die

	insinto ${root}/tools
	doins tools/*.py
	rm "${ED}"${root}/tools/{strata_mcp,test_*}.py || die
	# rocBLAS solution tables setup points the engine at
	insinto ${root}/tools/hip
	doins tools/hip/*.txt

	insinto ${root}/third_party/llama.cpp
	doins -r third_party/llama.cpp/gguf-py
	rm -r "${ED}"${root}/third_party/llama.cpp/gguf-py/tests || die

	exeinto ${root}/engine
	doexe "${BUILD_DIR}"/strata
	archs=${archs%;}
	cat > "${T}"/BUILD.json <<-EOF || die
		{"backend": "hip", "archs": ["${archs//;/\", \"}"], "isa_floor": "$(_strata_isa_floor)", "version": "${PV}"}
	EOF
	insinto ${root}/engine
	doins "${T}"/BUILD.json

	# upstream starts server.py through setup; the unit execs it directly
	fperms +x ${root}/{setup.py,serve/server.py}
	python_fix_shebang "${ED}"${root}/{setup.py,serve/server.py}
	python_optimize "${ED}"${root}

	systemd_newunit "${FILESDIR}"/strata_at.service 'strata@.service'
	dobin "${FILESDIR}"/strata-setup

	docinto examples
	dodoc "${FILESDIR}"/dropins/*.conf
	docompress -x /usr/share/doc/${PF}/examples
	docinto .
	dodoc README.md
	newdoc "${FILESDIR}"/strata-gentoo.md README.gentoo.md
}

pkg_postinst() {
	elog "To serve a model, download one quant as the strata user at the"
	elog "revision setup.py pins, set it up, and start its unit, for example:"
	elog
	elog "  sudo -u strata HF_HOME=/var/lib/strata/huggingface hf download \\"
	elog "    unsloth/Qwen3.8-Flash-Next-GGUF --include '*UD-Q4_K_XL*' \\"
	elog "    --revision 38bb39ee97821de2c9009abb7e93950eec396e66"
	elog "  strata-setup --family unsloth --model UD-Q4_K_XL --gguf-dir \\"
	elog "    /var/lib/strata/huggingface/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots/38bb39ee97821de2c9009abb7e93950eec396e66/UD-Q4_K_XL"
	elog "  systemctl enable --now strata@unsloth-ud-q4_k_xl"
	elog
	elog "--gguf-dir names the folder that holds the .gguf shards (this repository"
	elog "keeps each quant in a subfolder), and the unit instance is the <tag> of"
	elog "the /var/lib/strata/strata-<tag>.json config setup writes.  strata-setup"
	elog "never starts the server; systemctl does."
	elog "See ${EPREFIX}/usr/share/doc/${PF}/README.gentoo.md"
	elog "for your own Hugging Face cache, a data directory elsewhere, allowed"
	elog "host names, and SELinux."
}
