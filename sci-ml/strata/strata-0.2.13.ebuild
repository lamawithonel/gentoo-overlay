# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
# Limit AMDGPU_TARGETS to the wave32 archs upstream builds kernels for;
# defaults follow rocm.eclass (ROCm 7 official archs on).
ROCM_SKIP_GLOBALS=1
# Upstream builds Release.  cmake.eclass blanks the per-type flags for C
# and C++ only, so RelWithDebInfo would leave the HIP kernels at -O2 -g.
CMAKE_BUILD_TYPE=Release

inherit cmake python-single-r1 rocm systemd toolchain-funcs

LLAMA_CPP_COMMIT=3cf03257f219afbe7334045ff7c6a06ac68c627d

DESCRIPTION="Inference engine and OpenAI-compatible server for large language models"
HOMEPAGE="https://github.com/Niko1221/Strata"
SRC_URI="
	https://github.com/Niko1221/Strata/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/ggml-org/llama.cpp/archive/${LLAMA_CPP_COMMIT}.tar.gz
		-> llama.cpp-${LLAMA_CPP_COMMIT}.tar.gz
"
S="${WORKDIR}/Strata-${PV}"

# OFL-1.1: the web UI's font
LICENSE="MIT OFL-1.1"
SLOT="0"
KEYWORDS="~amd64"

AMDGPU_OFFICIAL=( gfx1030 gfx1100 gfx1101 gfx1200 gfx1201 )
AMDGPU_UNOFFICIAL=( gfx1031 gfx1102 gfx1151 )
AMDGPU_FLAGS=( "${AMDGPU_OFFICIAL[@]/#/amdgpu_targets_}" "${AMDGPU_UNOFFICIAL[@]/#/amdgpu_targets_}" )
ROCM_REQUIRED_USE=" || ( ${AMDGPU_FLAGS[*]} )"
ROCM_USEDEP=$(printf '%s(-)?,' "${AMDGPU_FLAGS[@]}")
ROCM_USEDEP=${ROCM_USEDEP%,}
# hipBLASLt has no gfx1030, gfx1031, or gfx1102 code; the engine calls it
# only with a tuning table, and there are none for those archs.
HIPBLASLT_USEDEP="amdgpu_targets_gfx1100(-)?,amdgpu_targets_gfx1101(-)?,amdgpu_targets_gfx1151(-)?,amdgpu_targets_gfx1200(-)?,amdgpu_targets_gfx1201(-)?"

IUSE="
	${AMDGPU_OFFICIAL[*]/#/+amdgpu_targets_} ${AMDGPU_UNOFFICIAL[*]/#/amdgpu_targets_}
	cpu_flags_x86_avx cpu_flags_x86_avx2 cpu_flags_x86_bmi2 cpu_flags_x86_f16c
	cpu_flags_x86_fma3 cpu_flags_x86_popcnt cpu_flags_x86_sse4_2
	default-offline hipblaslt +rocm selinux test vision
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
		dev-python/truststore[${PYTHON_USEDEP}]
	')
"
DEPEND="
	rocm? (
		dev-util/hip:=
		sci-libs/hipBLAS:=[${ROCM_USEDEP}]
		sci-libs/rocBLAS:=[${ROCM_USEDEP}]
		hipblaslt? ( sci-libs/hipBLASLt:=[${HIPBLASLT_USEDEP}] )
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
	"${FILESDIR}"/${PN}-0.2.13-packaged-mode.patch
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

src_prepare() {
	# gguf-py and the image reader's LLAMA_DIR expect llama.cpp here
	mv "${WORKDIR}"/llama.cpp-${LLAMA_CPP_COMMIT} third_party/llama.cpp || die
	# A non-portable image reader would build with -march=native; take CFLAGS.
	sed -i 's/set(GGML_NATIVE ON CACHE BOOL "" FORCE)/set(GGML_NATIVE OFF CACHE BOOL "" FORCE)/' \
		tools/vision/CMakeLists.txt || die
	cmake_src_prepare
}

# Configure the image reader (tools/vision) in its own build dir.
# Usage: _strata_vision_configure <build dir> [cmake args...]
_strata_vision_configure() {
	local BUILD_DIR=${1} CMAKE_USE_DIR="${S}"/tools/vision
	shift
	local mycmakeargs=(
		-DLLAMA_DIR="${S}"/third_party/llama.cpp
		-DSTRATA_VISION_CUDA=OFF
		-DSTRATA_PORTABLE=$([[ $(_strata_isa_floor) == portable ]] && echo ON || echo OFF)
		"${@}"
	)
	cmake_src_configure
}

src_configure() {
	local floor=$(_strata_isa_floor)
	local archs=$(get_amdgpu_flags)
	# upstream's HIP flags (setup.py build_engine_hip)
	local mycmakeargs=(
		-DGGML_NATIVE=OFF
		-DSTRATA_ENABLE_CUDA=OFF
		-DSTRATA_ENABLE_HIP=$(usex rocm)
		-DSTRATA_BUILD_TESTS=OFF
		-DSTRATA_PREFILL_MMQ=ON
		-DSTRATA_Q6K_EXPERTS=ON
		-DSTRATA_MMQ_KQUANTS=ON
		-DCMAKE_HIP_ARCHITECTURES="${archs%;}"
		-DCMAKE_HIP_COMPILER="$(tc-getHIPCXX)"
		$(cmake_use_find_package hipblaslt hipblaslt)
	)
	if [[ ${floor} == portable ]]; then
		mycmakeargs+=( -DSTRATA_PORTABLE=ON )
	else
		mycmakeargs+=( -DSTRATA_ISA_FLOOR=${floor} )
	fi
	cmake_src_configure

	if use vision; then
		# setup.py builds both: the CPU reader is the HIP reader's fallback
		_strata_vision_configure "${WORKDIR}"/vision-cpu
		_strata_vision_configure "${WORKDIR}"/vision-hip \
			-DSTRATA_VISION_HIP=ON \
			-DSTRATA_VISION_HIP_ARCHS="${archs%;}" \
			-DCMAKE_HIP_COMPILER="$(tc-getHIPCXX)"
	fi
}

src_compile() {
	cmake_src_compile strata
	if use vision; then
		local d
		for d in cpu hip; do
			BUILD_DIR="${WORKDIR}/vision-${d}" cmake_src_compile strata-vision
		done
	fi
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
		# Races the download it kills: it can finish first (fails on unpatched trees too)
		tools/test_setup_download.py::Resume::test_a_killed_download_continues
	)
	epytest -p no:cacheprovider serve/test_*.py tools/test_setup_*.py
}

src_install() {
	local root=/usr/lib/strata archs=$(get_amdgpu_flags)

	insinto ${root}
	# strata_control imports strata_cli in places; the terminal itself is not installed
	doins -r data serve setup.py strata_cli strata_control
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
	archs=\"${archs//;/\", \"}\"
	local vision=
	if use vision; then
		doexe "${WORKDIR}"/vision-{cpu/bin/strata-vision,hip/bin/strata-vision-hip}
		vision=", \"vision\": \"gpu\", \"vision_archs\": [${archs}]"
		vision+=", \"vision_gpu\": \"strata-vision-hip\", \"vision_cpu\": \"strata-vision\""
	fi
	cat > "${T}"/BUILD.json <<-EOF || die
		{"backend": "hip", "archs": [${archs}], "isa_floor": "$(_strata_isa_floor)", "version": "${PV}"${vision}}
	EOF
	insinto ${root}/engine
	doins "${T}"/BUILD.json
	if use hipblaslt; then
		# The engine picks the table for its GPU and the running hipBLASLt.
		insinto ${root}/engine/tuning
		doins tools/hip/*-hipblaslt-*.txt
	fi

	# upstream starts server.py through setup; the unit execs it directly
	fperms +x ${root}/{setup.py,serve/server.py}
	python_fix_shebang "${ED}"${root}/{setup.py,serve/server.py}
	python_optimize "${ED}"${root}

	cp "${FILESDIR}"/strata_at.service "${T}"/ || die
	if use default-offline; then
		sed -i 's/^Environment=STRATA_OFFLINE_FLAG=$/&--offline/' "${T}"/strata_at.service || die
	fi
	systemd_newunit "${T}"/strata_at.service 'strata@.service'
	dobin "${FILESDIR}"/strata-setup
	exeinto /usr/libexec
	doexe "${FILESDIR}"/strata-hugepages

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
