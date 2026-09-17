#!/bin/bash
#
# PBS job script for Underworld3 on NCI Gadi via the Singularity container.
# Counterpart to gadi_pbs_job.sh, which uses the bare-metal pixi install.
#
# Usage:
#   qsub gadi_container_job.sh
#   qsub -v SCRIPT=/abs/path/model.py gadi_container_job.sh
#   qsub -v SIF=/abs/path/other.sif,SCRIPT=/abs/path/model.py gadi_container_job.sh
#
# Runs the container with the HOST MPI injected (see FINDINGS.md): measured identical
# to bare metal. Without the injection the container's own OpenMPI reaches InfiniBand
# only through the deprecated openib BTL, at half the bandwidth.

#PBS -P m18
#PBS -N uw3_container
#PBS -q normal
#PBS -l walltime=01:00:00
#PBS -l ncpus=4
#PBS -l mem=16gb
#PBS -l storage=gdata/m18+scratch/m18
#PBS -l wd

# latest.sif follows the current release; development.sif the newest code. Both
# are symlinks that move when an image is installed, so resolve now and print
# below, and the job log records exactly what ran.
SIF=${SIF:-/g/data/m18/software/containers/underworld3/latest.sif}
SIF=$(readlink -f "$SIF")
SCRIPT=${SCRIPT:-gadi_test_stokes.py}

# Extra Python packages not in the image, installed once with
#   pip install --target=/scratch/<proj>/<user>/uw3-extra-pkgs <pkg>
# Prepended to PYTHONPATH inside the container; leave empty if unused.
EXTRA_PKGS=${EXTRA_PKGS:-}

[ -r "$SIF" ]    || { echo "container not readable: $SIF" >&2; exit 1; }
[ -r "$SCRIPT" ] || { echo "script not readable: $SCRIPT" >&2; exit 1; }

module load singularity
module load openmpi/4.1.7

# Host OpenMPI 4.1.7 and everything it links: same SONAME (libmpi.so.40) as the
# container's, so it takes over once first on LD_LIBRARY_PATH. Pinned to the module
# version above — update both together.
HOST_LIBS=/apps/openmpi/4.1.7/lib:/apps/openmpi-mofed5.8-pbs2021.1/4.1.7/lib
HOST_LIBS=$HOST_LIBS:/apps/ucx/1.17.0/lib:/apps/ucc/1.3.0/lib:/apps/hcoll/4.8.3228/lib
HOST_LIBS=$HOST_LIBS:/opt/pbs/default/lib:/half-root/usr/lib64:/half-root/lib64

echo "Job started:  $(date)"
echo "Job ID:       ${PBS_JOBID}"
echo "MPI ranks:    ${PBS_NCPUS}"
echo "Container:    ${SIF}"
echo "Script:       ${SCRIPT}"
echo ""

# /half-root holds Gadi's real system libraries (/lib64/*.so are symlinks into it);
# /opt/pbs/default/lib because the host MPI is linked against libpbs.
# BLAS threads pinned to 1: MPI already owns every core.
# PYTHONPATH is extended, not replaced — the image keeps petsc4py in a prefix that
# only its own PYTHONPATH knows about.
mpiexec -n "${PBS_NCPUS}" singularity exec \
    --bind /half-root \
    --bind /opt/pbs/default/lib \
    "${SIF}" \
    bash -c "LD_LIBRARY_PATH=${HOST_LIBS}:\${LD_LIBRARY_PATH} \
             PYTHONPATH=${EXTRA_PKGS:+${EXTRA_PKGS}:}\${PYTHONPATH} \
             OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
             python3 ${SCRIPT}"
rc=$?

echo ""
echo "Job finished: $(date)  (exit $rc)"
exit $rc
