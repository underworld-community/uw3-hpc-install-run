# uw3-hpc-install-run

Running [Underworld3](https://github.com/underworldcode/underworld3) on our HPC clusters.

## Kaiju

Use the container:

```bash
module load underworld3-container/release        # or /development for the newest code
cp /opt/cluster/software/containers/underworld3/kaiju_container_job.sh .
# edit SCRIPT=, --ntasks, --time, --mem
sbatch kaiju_container_job.sh
```

Jobs without `--mem` get ~2.6 GB per task, and Kaiju has no RDMA — do not benchmark on it.
Guide: [kaiju/container/README.md](kaiju/container/README.md).

## Gadi

Container (recommended) or bare metal; same performance. Edit `SCRIPT=` and the `#PBS`
lines, then:

```bash
qsub gadi/gadi_container_job.sh     # container, host MPI injected
qsub gadi/gadi_pbs_job.sh           # bare metal, shared pixi install
```

Keep the MPI injection in the container template: without it multi-node runs get half the
bandwidth, or worse. Guide: [gadi/README.md](gadi/README.md).

## Setonix

Nothing deployed — blocked on a Pawsey account and one experiment. See [setonix/](setonix/).

---

## About

| Cluster | Scheduler | Container | Bare metal |
|---|---|---|---|
| Kaiju | Slurm | recommended | retired 2026-09-11 |
| NCI Gadi | PBS Pro | recommended | supported |
| Pawsey Setonix | Slurm | blocked | — |

The Containerfiles and the CI that builds them live in the Underworld3 repo under
`docs/developer/gadi_singularity/`. This repo is site operations: what to run where, and why.

```
kaiju/container/    user guide, job template, installer, FINDINGS.md
kaiju/slurm/        memory enforcement / cgroup configuration
kaiju/modulefiles/  underworld3-container/{development,release}; tombstone for the retired module
kaiju/kaiju_*.sh    retired bare-metal scripts, kept as a record
gadi/               job templates (container, bare metal), installers, FINDINGS.md
setonix/            parallel-IO probe, not yet run
common/             pingpong.py (is the container on the fabric?), sbatch_retry.sh
```
