# Gadi

Container (recommended) or bare metal. Same performance, measured.

```bash
qsub container/gadi_container_job.sh     # container, host MPI injected
qsub baremetal/gadi_pbs_job.sh           # bare metal, shared pixi install
```

Edit `SCRIPT=` and the `#PBS` lines first. Both default to `gadi_test_stokes.py`, kept
here because either template runs it.

- [container/README.md](container/README.md) — user guide and how the shared images are
  updated. [container/FINDINGS.md](container/FINDINGS.md) — why the template injects the
  host MPI.
- [baremetal/README.md](baremetal/README.md) — the pixi install, shared and per-user.
