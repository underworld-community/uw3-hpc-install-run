#!/bin/bash --login
#
# Setonix parallel-IO probe. Runs the same collective MPI-IO test twice: once
# plain, once with the host library tree bound so ROMIO can find liblustreapi.
#
#   sbatch --account=<pawsey-project> setonix_probe.slurm
#
# HOST_LIB is a directory holding ONLY liblustreapi and its non-glibc
# dependencies, prepared on a login node (see README). Binding the whole host
# /usr/lib64 would put SLES glibc 2.31 ahead of the container's 2.39 and break
# every binary before the test even starts.
#
#SBATCH --job-name=uw3_ioprobe
#SBATCH --partition=work
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --output=ioprobe_%j.out

set -u

# The -mpi flavour is the one that bind-mounts the host Cray MPICH; -nompi and
# the default -slurm flavour do not, and the probe would then be testing the
# container's own MPICH instead of the host's.
module load singularity/4.1.0-mpi

IMAGE=${IMAGE:-$MYSCRATCH/containers/setonix-ioprobe.sif}
TARGET=${TARGET:-$MYSCRATCH/ioprobe/probe.bin}
HOST_LIB=${HOST_LIB:-$MYSCRATCH/hostlib}

mkdir -p "$(dirname "$TARGET")"

echo "################ variant 1: plain (expect Pawsey's failure) ################"
srun -n "$SLURM_NTASKS" singularity exec "$IMAGE" \
    python3 /opt/mpiio_probe.py "$TARGET"
echo "variant 1 exit: $?"

echo
echo "################ variant 2: liblustreapi bound in ################"
[ -r "$HOST_LIB/liblustreapi.so.1" ] || { echo "no $HOST_LIB/liblustreapi.so.1 — prepare it first (README)"; exit 1; }
ls -l "$HOST_LIB"
srun -n "$SLURM_NTASKS" singularity exec \
    --bind "${HOST_LIB}:/host-lib" \
    "$IMAGE" \
    bash -c "LD_LIBRARY_PATH=/host-lib:\${LD_LIBRARY_PATH:-} python3 /opt/mpiio_probe.py '${TARGET}'"
echo "variant 2 exit: $?"
