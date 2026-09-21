#!/bin/bash --login
#
# Slurm job script for Underworld3 on Pawsey Setonix via Singularity.
#
#   sbatch --account=<project> setonix_container_job.slurm
#   sbatch --account=<project> --export=ALL,SCRIPT=/abs/path/model.py setonix_container_job.slurm
#
# No MPI tuning here, unlike Kaiju and Gadi: the -mpi singularity flavour
# bind-mounts the host Cray MPICH and its libfabric over the container's, so
# the ranks run on the real interconnect with nothing extra from us.

#SBATCH --job-name=uw3_container
#SBATCH --partition=work
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --time=00:15:00
#SBATCH --output=uw3c_%j.out

set -u

# -mpi, not the default -slurm flavour: only -mpi binds the host MPI.
module load singularity/4.1.0-mpi

SIF=${SIF:-$MYSCRATCH/containers/underworld3-setonix.sif}
SIF=$(readlink -f "$SIF")
SCRIPT=${SCRIPT:-setonix_test_stokes.py}

[ -r "$SIF" ]    || { echo "container not readable: $SIF" >&2; exit 1; }
[ -r "$SCRIPT" ] || { echo "script not readable: $SCRIPT" >&2; exit 1; }

# MPI owns every core; a threaded BLAS would oversubscribe them.
export SINGULARITYENV_OPENBLAS_NUM_THREADS=1
export SINGULARITYENV_OMP_NUM_THREADS=1

echo "Job started:  $(date)"
echo "Job ID:       ${SLURM_JOB_ID}"
echo "MPI ranks:    ${SLURM_NTASKS}"
echo "Container:    ${SIF}"
echo "Script:       ${SCRIPT}"
# Must say Cray MPICH. If it says MPICH 3.4.3 the host MPI is not bound and
# the ranks would talk over TCP.
echo "MPI:          $(srun -n 1 singularity exec "$SIF" python3 -c 'from mpi4py import MPI; print(MPI.Get_library_version().splitlines()[0])' 2>/dev/null)"
echo ""

srun -N "$SLURM_JOB_NUM_NODES" -n "$SLURM_NTASKS" -c "$SLURM_CPUS_PER_TASK" \
    singularity exec "$SIF" python3 "$SCRIPT"
rc=$?

echo ""
echo "Job finished: $(date)  (exit $rc)"
exit $rc
