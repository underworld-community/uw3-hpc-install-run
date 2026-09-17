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

`kaiju_install_*.sh` and `kaiju_slurm_job.sh` are the retired bare-metal scripts, kept as
a record. `kaiju_test_stokes.py` is still the reference test.
