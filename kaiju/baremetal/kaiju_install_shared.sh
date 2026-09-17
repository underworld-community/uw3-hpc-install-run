#!/bin/bash
#
# Underworld3 SHARED install script for the Kaiju cluster
#
# Installs UW3 to /opt/cluster/software/ so all users can access it via:
#   module load underworld3/development
#
# Must be run as an admin with write access to /opt/cluster/software/.
#
# Usage:
#   source uw3_install_kaiju_shared.sh         # activate shared environment
#   source uw3_install_kaiju_shared.sh install # full installation (first time only)
#
# After install, the modulefile is automatically installed by install_modulefile().
#
# For per-user installs, use uw3_install_kaiju_amr.sh instead.
#
# NOTE: This script is designed to be sourced, NOT executed directly.
# Do NOT add 'set -e' here — it would cause your SSH session to close
# on any error since the script runs in your current shell.

# ============================================================
# CONFIGURATION
# ============================================================

SPACK_MPI_VERSION="openmpi@4.1.6"

export INSTALL_PATH="/opt/cluster/software"
export UW3_PATH="${INSTALL_PATH}/underworld3"
export UW3_BRANCH="development"
export UW3_REPO="https://github.com/jcgraciosa/underworld3.git"

# ============================================================
# DERIVED PATHS — do not edit below this line
# ============================================================

export PIXI_MANIFEST="${UW3_PATH}/pixi.toml"
export PETSC_DIR="${UW3_PATH}/petsc-custom/petsc"
_ver_file="${UW3_PATH}/petsc-custom/.petsc-version"
if [ -f "${_ver_file}" ]; then
    _ver=$(cat "${_ver_file}" | tr -d '[:space:]')
    export PETSC_ARCH="petsc-${_ver}-uw-openmpi"
else
    _built=$(ls -d "${PETSC_DIR}"/petsc-*-uw-openmpi 2>/dev/null | head -1)
    export PETSC_ARCH="${_built:+$(basename "${_built}")}"
    export PETSC_ARCH="${PETSC_ARCH:-petsc-324-uw-openmpi}"
fi
unset _ver_file _ver _built

# ============================================================
# ENVIRONMENT ACTIVATION
# Called automatically at script source time.
# ============================================================

load_env() {
    echo "==> Loading spack module: ${SPACK_MPI_VERSION}"
    eval "$(spack load --sh "${SPACK_MPI_VERSION}")"

    export MPI_DIR
    MPI_DIR="$(dirname "$(dirname "$(which mpicc)")")"

    # Build LD_LIBRARY_PATH from all spack transitive dep lib dirs
    _old_ifs="$IFS"
    IFS=":"
    for _prefix in $CMAKE_PREFIX_PATH; do
        case "$_prefix" in
            */spack/opt/spack/*)
                [ -d "${_prefix}/lib" ] && export LD_LIBRARY_PATH="${_prefix}/lib:${LD_LIBRARY_PATH}"
                ;;
        esac
    done
    IFS="$_old_ifs"
    unset _old_ifs _prefix

    # Activate pixi hpc environment
    if command -v pixi &>/dev/null && [ -f "${PIXI_MANIFEST}" ]; then
        if ! echo "${PATH}" | tr ':' '\n' | grep -q "\.pixi/envs/hpc/bin"; then
            eval "$(pixi shell-hook -e hpc --manifest-path "${PIXI_MANIFEST}")"
        fi
    fi

    # PETSc + petsc4py
    if [ -d "${PETSC_DIR}/${PETSC_ARCH}" ]; then
        export PYTHONPATH="${PETSC_DIR}/${PETSC_ARCH}/lib:${PYTHONPATH}"
    fi

    export PMIX_MCA_psec=native
    export OMPI_MCA_btl_tcp_if_include=eno1

    echo "==> Environment ready"
    echo "    MPI_DIR:    ${MPI_DIR}"
    echo "    UW3_PATH:   ${UW3_PATH}"
    echo "    PETSC_DIR:  ${PETSC_DIR}"
    echo "    PETSC_ARCH: ${PETSC_ARCH}"
}

# ============================================================
# INSTALLATION FUNCTIONS
# ============================================================

setup_pixi() {
    if command -v pixi &>/dev/null; then
        echo "==> pixi already installed: $(pixi --version)"
        return 0
    fi
    echo "==> Installing pixi..."
    curl -fsSL https://pixi.sh/install.sh | bash
    export PATH="${HOME}/.pixi/bin:${PATH}"
    echo "==> pixi installed: $(pixi --version)"
}

clone_uw3() {
    if [ ! -d "${UW3_PATH}" ]; then
        echo "==> Cloning Underworld3 (branch: ${UW3_BRANCH})..."
        mkdir -p "${INSTALL_PATH}"
        git clone --branch "${UW3_BRANCH}" --depth 1 "${UW3_REPO}" "${UW3_PATH}"
    else
        echo "==> Underworld3 source already present at ${UW3_PATH}"
    fi
}

install_pixi_env() {
    echo "==> Installing pixi hpc environment (~3 min)..."
    pixi install -e hpc --manifest-path "${PIXI_MANIFEST}"
    eval "$(pixi shell-hook -e hpc --manifest-path "${PIXI_MANIFEST}")"
    echo "==> pixi hpc environment ready"
}

install_mpi4py() {
    echo "==> Building mpi4py from source against spack OpenMPI..."
    pip install --no-binary :all: --no-cache-dir "mpi4py>=4,<5"
    echo "==> mpi4py installed"
}

install_petsc() {
    echo "==> Building PETSc with AMR tools (~1 hour)..."
    UW_CLUSTER=kaiju bash "${UW3_PATH}/petsc-custom/build-petsc.sh"
    # Re-derive PETSC_ARCH from the directory build-petsc.sh actually created,
    # since the version is only known after the build (no .petsc-version in fresh clone).
    _built=$(ls -d "${PETSC_DIR}"/petsc-*-uw-openmpi 2>/dev/null | head -1)
    [ -n "${_built}" ] && export PETSC_ARCH="$(basename "${_built}")"
    unset _built
    export PYTHONPATH="${PETSC_DIR}/${PETSC_ARCH}/lib:${PYTHONPATH}"
    echo "==> PETSc installed"
}

install_h5py() {
    echo "==> Building h5py against PETSc HDF5..."
    # Temporarily hide pixi env's serial HDF5 so h5py finds PETSc's parallel HDF5.
    # h5py's build system loads libhdf5.so from LD_LIBRARY_PATH to detect MPI support,
    # ignoring HDF5_DIR — same issue as Gadi.
    local pixi_lib="${UW3_PATH}/.pixi/envs/hpc/lib"
    local _hidden=()
    for _f in "${pixi_lib}"/libhdf5*.so*; do
        [ -f "${_f}" ] && mv "${_f}" "${_f}.bak" && _hidden+=("${_f}")
    done

    # --no-deps: prevent pip from replacing source-built mpi4py or pixi numpy
    CC=mpicc \
    HDF5_MPI="ON" \
    HDF5_DIR="${PETSC_DIR}/${PETSC_ARCH}" \
    pip install --no-binary=h5py --no-cache-dir --force-reinstall --no-deps h5py
    local _rc=$?

    for _f in "${_hidden[@]}"; do mv "${_f}.bak" "${_f}"; done
    unset _hidden _rc _f _pixi_lib

    [ ${_rc:-0} -ne 0 ] && echo "ERROR: h5py install failed" && return 1
    echo "==> h5py installed"
}

install_uw3() {
    echo "==> Installing Underworld3..."
    cd "${UW3_PATH}"
    pip install -e .
    echo "==> Underworld3 installed"
}

fix_permissions() {
    echo "==> Setting shared read permissions on ${UW3_PATH}..."
    chmod -R a+rX "${UW3_PATH}"
    # Directories need execute for traversal
    find "${UW3_PATH}" -type d -exec chmod a+x {} +
    echo "==> Permissions set"
}

install_modulefile() {
    local src="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/modulefiles/underworld3/development.tcl"
    local dst="/opt/cluster/modulefiles/underworld3"
    local name="development-$(date +%d%b%y)"
    echo "==> Installing modulefile to ${dst}/${name}..."
    mkdir -p "${dst}"
    cp "${src}" "${dst}/${name}"
    echo "==> Modulefile installed. Users can now run: module load underworld3/${name}"
}

verify_install() {
    echo "==> Verifying installation..."
    python3 -c "
from mpi4py import MPI
print(f'mpi4py OK   — MPI version: {MPI.Get_version()}')
from petsc4py import PETSc
print(f'petsc4py OK — PETSc version: {PETSc.Sys.getVersion()}')
import h5py
print(f'h5py OK     — HDF5 version: {h5py.version.hdf5_version}')
import underworld3 as uw
print(f'underworld3 OK — version: {uw.__version__}')
"
    echo ""
    echo "==> MPI test (4 ranks):"
    mpirun -n 4 python3 -c \
        "from mpi4py import MPI; print(f'Rank {MPI.COMM_WORLD.rank} of {MPI.COMM_WORLD.size} OK')"
    echo "==> All checks passed"
}

# ============================================================
# ENTRY POINT
# ============================================================

load_env

if [ "${1}" = "install" ]; then
    echo ""
    echo "Starting shared installation..."
    echo "  INSTALL_PATH: ${INSTALL_PATH}"
    echo "  UW3_BRANCH:   ${UW3_BRANCH}"
    echo ""
    setup_pixi
    clone_uw3
    install_pixi_env
    install_mpi4py
    install_petsc
    install_h5py
    install_uw3
    verify_install
    fix_permissions
    install_modulefile
    echo ""
    echo "=========================================="
    echo "Shared installation complete!"
    echo "Users can now activate with:"
    echo "  module load underworld3/development-$(date +%d%b%y)"
    echo "=========================================="
fi
