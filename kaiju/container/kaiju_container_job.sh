#!/bin/bash
#
# Slurm job script for Underworld3 on Kaiju via Apptainer.
# Counterpart to kaiju_slurm_job.sh, which uses the baremetal module.
#
# Usage:
#   sbatch kaiju_container_job.sh
#   sbatch --nodes=2 --ntasks-per-node=26 kaiju_container_job.sh
#   sbatch --export=ALL,SCRIPT=/abs/path/model.py kaiju_container_job.sh
#
# Every OMPI/PMIX setting below is load-bearing — see FINDINGS.md.
#

#SBATCH --job-name=uw3_container
#SBATCH --output=uw3c_%j.out
#SBATCH --error=uw3c_%j.err
#SBATCH --ntasks=2
##SBATCH --nodes=2
##SBATCH --ntasks-per-node=26
#SBATCH --time=01:00:00

# Resolve the symlink: UW3_SIF (from the module) moves when the container is
# updated, so record the image this job actually ran rather than a name that may
# mean something else later.
CONTAINER=${CONTAINER:-${UW3_SIF:-$HOME/containers/uw3-ci.sif}}
CONTAINER=$(readlink -f "$CONTAINER")
SCRIPT=${SCRIPT:-kaiju_test_stokes.py}

[ -r "$CONTAINER" ] || { echo "container not readable: $CONTAINER" >&2; exit 1; }
[ -r "$SCRIPT" ]    || { echo "script not readable: $SCRIPT" >&2; exit 1; }

# APPTAINERENV_ prefix is required — a plain export does not reach the ranks.
export APPTAINERENV_OMPI_MCA_btl_tcp_if_include=ib0            # ib0 not eno1: 33x bandwidth
export APPTAINERENV_OMPI_MCA_pml=ob1
export APPTAINERENV_OMPI_MCA_btl=self,vader,tcp                # openib segfaults at finalize
export APPTAINERENV_OMPI_MCA_btl_vader_single_copy_mechanism=none  # CMA breaks under userns
export APPTAINERENV_PMIX_MCA_gds=hash                          # dstore unreachable in container

echo "Job started:  $(date)"
echo "Nodes:        ${SLURM_NODELIST}"
echo "MPI ranks:    ${SLURM_NTASKS}"
echo "Container:    ${CONTAINER}"
echo "Script:       ${SCRIPT}"
echo ""

# cgroup v1 has no peak-RSS counter — memory.max_usage_in_bytes is the peak of
# rss+cache, and memory.stat is instantaneous (reads zero once ranks exit). So
# sample rss while the job runs. Short jobs may under-sample.
CG=/sys/fs/cgroup/memory/slurm/uid_$(id -u)/job_${SLURM_JOB_ID}
RSSMAX=$(mktemp)
(
    m=0
    while :; do
        # total_rss, not rss: the job cgroup holds no tasks itself — the ranks
        # are in child step cgroups, and only the total_* fields recurse.
        v=$(awk '/^total_rss /{print $2}' "$CG/memory.stat" 2>/dev/null)
        [ -n "$v" ] && [ "$v" -gt "$m" ] && { m=$v; echo "$m" > "$RSSMAX"; }
        sleep 2
    done
) &
sampler=$!
trap 'kill $sampler 2>/dev/null; rm -f "$RSSMAX"' EXIT

srun --mpi=pmix apptainer exec "${CONTAINER}" python3 "${SCRIPT}"
rc=$?

kill $sampler 2>/dev/null; wait $sampler 2>/dev/null

# accounting storage is disabled, so sacct/MaxRSS is unavailable. This node only.
# Size --mem from peak rss: the total includes the memory-mapped SIF (~1 GB),
# which is reclaimable page cache rather than a requirement.
if [ -r "$CG/memory.max_usage_in_bytes" ]; then
    tb=$(cat "$CG/memory.max_usage_in_bytes" 2>/dev/null)
    rb=$(cat "$RSSMAX" 2>/dev/null)
    echo "Peak memory:  $(( ${tb:-0} / 1048576 )) MB total," \
         "$(( ${rb:-0} / 1048576 )) MB peak rss, on $(hostname -s)"
fi

echo ""
echo "Exit status:  ${rc}"
echo "Job finished: $(date)"
exit ${rc}
