#!/bin/bash --login
#
# Setonix parallel-IO probe. Runs the same collective MPI-IO test twice: once
# plain, once with the host library tree bound so ROMIO can find liblustreapi.
#
#   sbatch --account=<pawsey-project> setonix_probe.slurm
#
# Set HOST_LIB to whatever the login-node search actually found before running
# the second variant (see the README in this directory).
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
HOST_LIB=${HOST_LIB:-/usr/lib64}

mkdir -p "$(dirname "$TARGET")"

echo "################ variant 1: plain (expect Pawsey's failure) ################"
srun -n "$SLURM_NTASKS" singularity exec "$IMAGE" \
    python3 /opt/mpiio_probe.py "$TARGET"
echo "variant 1 exit: $?"

echo
echo "################ variant 2: host library tree bound ################"
# Bound to a side path rather than over /usr/lib64, so the container's own
# Ubuntu libraries keep priority and only the missing Lustre bits are added.
srun -n "$SLURM_NTASKS" singularity exec \
    --bind "${HOST_LIB}:/host-lib" \
    "$IMAGE" \
    bash -c "LD_LIBRARY_PATH=/host-lib:\${LD_LIBRARY_PATH:-} python3 /opt/mpiio_probe.py '${TARGET}'"
echo "variant 2 exit: $?"
