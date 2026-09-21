# Setonix

Use the container. Validated 2026-09-21: correctness, parallel HDF5 on Lustre, host Cray
MPICH. No scaling study yet.

```bash
module load singularity/4.1.0-mpi
sbatch --account=$PAWSEY_PROJECT container/setonix_container_job.slurm
```

- [container/README.md](container/README.md) — user guide.
  [container/FINDINGS.md](container/FINDINGS.md) — measurements and why the image is Ubuntu + MPICH 3.4.3.
- [probe/](probe/) — the parallel-IO experiment that decided whether to build for Setonix at
  all. Pawsey's known issue says MPI-IO cannot work in a container; it passed.

Two surprises: `$PAWSEY_PROJECT`/`$MYSCRATCH` can point at a stale project — check `id`;
and `$HOME` is 1 GB, so everything goes under `$MYSCRATCH`.
