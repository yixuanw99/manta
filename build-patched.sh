#!/usr/bin/env bash
# ==============================================================================
# build-patched.sh
#
# Build the patched Manta from this repository.
#
# Patch applied: MAX_QSCORE 70 → 93 in qscore_cache.hpp, allowing Manta to
# process BAMs where base quality scores exceed 70 (e.g. cfDNA consensus reads
# produced by fgbio CallMolecularConsensusReads).
#
# Prerequisites:
#   conda env create -f build-env.yaml   # creates manta_build_py2
#
# Usage:
#   conda activate manta_build_py2
#   bash build-patched.sh [--install-dir /path/to/install] [--jobs N]
#
# Output binaries (place all five in the target Manta libexec):
#   EstimateSVLoci  MergeSVLoci  CheckSVLoci  SummarizeSVLoci  GenerateSVCandidates
# ==============================================================================
set -eo pipefail

# ── Argument parsing ─────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${REPO_DIR}/install"
BUILD_JOBS="$(nproc)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --jobs)        BUILD_JOBS="$2";  shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

BUILD_DIR="${REPO_DIR}/_build"
LOG_FILE="${REPO_DIR}/build-patched.log"
BUILD_ENV_NAME="${MANTA_BUILD_ENV:-manta_build_py2}"

echo "============================================================" | tee "${LOG_FILE}"
echo "Build Patched Manta (MAX_QSCORE=93)"                          | tee -a "${LOG_FILE}"
echo "Time        : $(date -Iseconds)"                              | tee -a "${LOG_FILE}"
echo "Repo        : ${REPO_DIR}"                                    | tee -a "${LOG_FILE}"
echo "Install dir : ${INSTALL_DIR}"                                 | tee -a "${LOG_FILE}"
echo "Jobs        : ${BUILD_JOBS}"                                  | tee -a "${LOG_FILE}"
echo "============================================================" | tee -a "${LOG_FILE}"

# ── Verify patch is in place ─────────────────────────────────────────────────
PATCH_FILE="${REPO_DIR}/src/c++/lib/blt_util/qscore_cache.hpp"
echo ""                                                   | tee -a "${LOG_FILE}"
echo ">>> Verifying patch ..."                            | tee -a "${LOG_FILE}"

if grep -q 'MAX_QSCORE = 93' "${PATCH_FILE}"; then
    echo "  ✓ MAX_QSCORE = 93 confirmed"                 | tee -a "${LOG_FILE}"
elif grep -q 'MAX_QSCORE = 70' "${PATCH_FILE}"; then
    echo "  ✗ ERROR: source is still unpatched (MAX_QSCORE = 70)" | tee -a "${LOG_FILE}"
    echo "    Patch should already be committed in this repo."     | tee -a "${LOG_FILE}"
    exit 1
else
    echo "  ✗ ERROR: unexpected MAX_QSCORE value in ${PATCH_FILE}" | tee -a "${LOG_FILE}"
    grep 'MAX_QSCORE' "${PATCH_FILE}"                   | tee -a "${LOG_FILE}"
    exit 1
fi

# ── Activate conda build environment ─────────────────────────────────────────
echo ""                                                   | tee -a "${LOG_FILE}"
echo ">>> Activating conda env: ${BUILD_ENV_NAME} ..."   | tee -a "${LOG_FILE}"

CONDA_BASE="$(conda info --base)"
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${BUILD_ENV_NAME}"

PYTHON2_BIN="${CONDA_PREFIX}/bin/python2"
[[ ! -x "${PYTHON2_BIN}" ]] && PYTHON2_BIN="${CONDA_PREFIX}/bin/python2.7"
if [[ ! -x "${PYTHON2_BIN}" ]]; then
    echo "  ✗ ERROR: python2 not found in ${CONDA_PREFIX}/bin" | tee -a "${LOG_FILE}"
    echo "    Did you run: conda env create -f build-env.yaml ?" | tee -a "${LOG_FILE}"
    exit 1
fi

# ── Compiler setup ───────────────────────────────────────────────────────────
CONDA_BIN="${CONDA_PREFIX}/bin"

# Create standard short-name symlinks so legacy Boost bootstrap detects toolset.
for pair in "x86_64-conda-linux-gnu-cc:gcc" \
            "x86_64-conda-linux-gnu-c++:g++" \
            "x86_64-conda-linux-gnu-ar:ar" \
            "x86_64-conda-linux-gnu-ranlib:ranlib"; do
    src="${CONDA_BIN}/${pair%%:*}"
    dst="${CONDA_BIN}/${pair##*:}"
    [[ -x "${src}" && ! -f "${dst}" ]] && ln -sf "${src}" "${dst}"
done
[[ -f "${CONDA_BIN}/gcc" && ! -f "${CONDA_BIN}/cc" ]] && \
    ln -sf "${CONDA_BIN}/gcc" "${CONDA_BIN}/cc"
[[ -f "${CONDA_BIN}/g++" && ! -f "${CONDA_BIN}/c++" ]] && \
    ln -sf "${CONDA_BIN}/g++" "${CONDA_BIN}/c++"

export CC="${CONDA_BIN}/gcc"
export CXX="${CONDA_BIN}/g++"
export PYTHON="${PYTHON2_BIN}"
export PYTHON_EXECUTABLE="${PYTHON2_BIN}"
export Python_EXECUTABLE="${PYTHON2_BIN}"
export PATH="${CONDA_BIN}:${PATH}"

# Do NOT set BOOST_ROOT or inject conda include/lib — Manta must use its own
# bundled Boost 1.58 bootstrap. Mixing conda Boost 1.85 headers causes
# "Boost.Math requires C++14" errors.
unset BOOST_ROOT

echo "  BUILD_ENV    = ${BUILD_ENV_NAME}"                  | tee -a "${LOG_FILE}"
echo "  CC           = ${CC}"                              | tee -a "${LOG_FILE}"
echo "  CXX          = ${CXX}"                             | tee -a "${LOG_FILE}"
echo "  PYTHON       = ${PYTHON2_BIN}"                     | tee -a "${LOG_FILE}"
echo "  cmake ver    = $(cmake --version | head -1)"       | tee -a "${LOG_FILE}"
echo "  gcc ver      = $(gcc --version | head -1)"         | tee -a "${LOG_FILE}"
echo "  python ver   = $(${PYTHON2_BIN} --version 2>&1)"  | tee -a "${LOG_FILE}"

# ── Configure ────────────────────────────────────────────────────────────────
echo ""                                                    | tee -a "${LOG_FILE}"
echo ">>> Configure ..."                                   | tee -a "${LOG_FILE}"

rm -rf "${BUILD_DIR}" "${INSTALL_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

PYTHON="${PYTHON2_BIN}" \
PYTHON_EXECUTABLE="${PYTHON2_BIN}" \
Python_EXECUTABLE="${PYTHON2_BIN}" \
"${REPO_DIR}/configure" \
    --prefix="${INSTALL_DIR}" \
    --jobs="${BUILD_JOBS}" \
    2>&1 | tee -a "${LOG_FILE}"

# ── Build & install ──────────────────────────────────────────────────────────
echo ""                                                    | tee -a "${LOG_FILE}"
echo ">>> make install (-j${BUILD_JOBS}) ..."              | tee -a "${LOG_FILE}"

make PREFIX="${INSTALL_DIR}" CXX="${CXX}" VERBOSE=1 \
    CXXFLAGS="${CXXFLAGS} -O3 -std=c++14" \
    -j"${BUILD_JOBS}" install \
    2>&1 | tee -a "${LOG_FILE}"

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""                                                    | tee -a "${LOG_FILE}"
echo ">>> Verifying installation ..."                      | tee -a "${LOG_FILE}"

PATCHED_BINARIES=(EstimateSVLoci MergeSVLoci CheckSVLoci SummarizeSVLoci GenerateSVCandidates)
ALL_OK=true
for bin in "${PATCHED_BINARIES[@]}"; do
    if [[ -x "${INSTALL_DIR}/libexec/${bin}" ]]; then
        echo "  ✓ ${bin}"                                 | tee -a "${LOG_FILE}"
    else
        echo "  ✗ MISSING: ${bin}"                        | tee -a "${LOG_FILE}"
        ALL_OK=false
    fi
done

echo ""                                                    | tee -a "${LOG_FILE}"
if [[ "${ALL_OK}" == true ]]; then
    echo "============================================================" | tee -a "${LOG_FILE}"
    echo "SUCCESS — install dir: ${INSTALL_DIR}/libexec/"               | tee -a "${LOG_FILE}"
    echo "Binaries to bake into Docker image:"                          | tee -a "${LOG_FILE}"
    for bin in "${PATCHED_BINARIES[@]}"; do
        echo "  ${INSTALL_DIR}/libexec/${bin}"                          | tee -a "${LOG_FILE}"
    done
    echo "============================================================" | tee -a "${LOG_FILE}"
else
    echo "FAILED — check ${LOG_FILE} for details"                       | tee -a "${LOG_FILE}"
    exit 1
fi

echo "Done at : $(date -Iseconds)" | tee -a "${LOG_FILE}"
