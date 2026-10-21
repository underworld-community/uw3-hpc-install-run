# Kaiju

Use the container. The bare-metal install was retired on 2026-09-11.

```bash
module load underworld3-container/release        # or /development
srun --mpi=pmix -n 4 apptainer exec $UW3_SIF python3 your_script.py
```

- [container/README.md](container/README.md) — user guide: job template, memory, chaining
  jobs, developing UW3 inside the container, what the warnings mean.
  [container/FINDINGS.md](container/FINDINGS.md) — why each setting is what it is.
- [slurm/README.md](slurm/README.md) — memory has been enforced since 2026-09-11. Read it
  if a job that used to work is now OOM-killed.
- [modulefiles/](modulefiles/) — what is installed under `/opt/cluster/modulefiles`.

Two surprises: jobs without `--mem` get ~2.6 GB per task, and there is no RDMA, so timings
here do not transfer to Gadi.

[baremetal/](baremetal/) holds the retired bare-metal scripts, kept as a record.
`kaiju_test_stokes.py` stays here: it is the reference test for both.

## Status (2026-10-21)

- **n1-n4 are down** ("Not responding" since 2026-09-23), n3 among them, so
  `--constraint=bigmem` cannot run. Add `--exclude='n[1-4]'` until they return.
- **The shared images are stale.** `development.sif` (2026-09-10) and `v3.1.0.sif` were
  pulled from a personal namespace (`ghcr.io/jcgraciosa/...`) and have no C++ compiler, so
  the in-container rebuild fails. A `uw3admin` member should republish from
  `ghcr.io/underworldcode/underworld3-gadi:{development,v3.2.0}` with
  `kaiju_container_install.sh`. Until then, pull your own copy
  ([container/README.md](container/README.md#running-a-branch-of-underworld3)).
- **The site copy of `kaiju_container_job.sh` is older than the one here** and lacks
  `EXTRA_PKGS`. Use this repository's copy.
