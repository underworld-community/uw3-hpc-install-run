# Kaiju container: findings

The why behind [README.md](README.md). Read before changing any MPI setting.

Validated 2026-09-10 with `ghcr.io/jcgraciosa/underworld3-gadi:ci-gadi-container`. The
Gadi image runs as-is; everything here is launch configuration.

## Working configuration

```bash
export APPTAINERENV_OMPI_MCA_pml=ob1
export APPTAINERENV_OMPI_MCA_btl=self,vader,tcp
export APPTAINERENV_OMPI_MCA_btl_tcp_if_include=ib0
export APPTAINERENV_OMPI_MCA_btl_vader_single_copy_mechanism=none
export APPTAINERENV_PMIX_MCA_gds=hash

srun --mpi=pmix -N 2 -n 2 apptainer exec uw3-ci.sif python3 model.py
```

`APPTAINERENV_` is required — a plain export does not reach the ranks.

| Variable | Why |
|---|---|
| `btl_tcp_if_include=ib0` | 33x bandwidth; otherwise OpenMPI may pick `eno1` |
| `btl_vader_single_copy_mechanism=none` | unprivileged Apptainer breaks CMA (below) |
| `btl=self,vader,tcp` | excludes `openib`, which segfaults on teardown (below) |
| `PMIX_MCA_gds=hash` | silences per-rank PMIX dstore errors; cosmetic |

## Measured performance (2 ranks, 2 nodes)

| Interface | 8 B latency | 4 MiB bandwidth |
|---|---|---|
| `ib0` (IPoIB) | 14.7 us | 3817 MB/s |
| `eno1` (ethernet) | 53.2 us | 117 MB/s |
| RDMA, if it worked | ~1-2 us | ~4000 MB/s |

Bandwidth is fine; latency is the cost. Krylov solves are latency-bound (halo exchange,
`allreduce` per dot product), so large per-rank problems lose little and strong scaling to
many ranks is transport-limited.

## Why RDMA does not work

The fabric is healthy (`mlx4_0`, `PORT_ACTIVE`, 40 Gb FDR10). Both routes to verbs are closed:

- **UCX**: `ucx_info -d` lists only `self`, `sysv`, `posix`, `tcp` — identical on host and
  in the container. UCX dropped ConnectX-3 around 1.12; Kaiju has 1.15.
- **openib**: works with `btl_openib_allow_ib=true`, then a background thread segfaults at
  `MPI_Finalize` — nonzero exit after the work completes, which breaks `afterok` chains.
  Reproducible with bare `mpi4py`; `btl_openib_use_async_event_thread=0` does not help.
  Deprecated in OpenMPI 4.x, gone in 5.x.

Fixing it means a Kaiju-specific image with UCX <= 1.11. Not worth it unless strong scaling
on Kaiju becomes important.

## CMA and user namespaces

Without `single_copy_mechanism=none`, ranks abort in `MatAssemblyEnd`:

```
Reading from remote process' memory failed. Disabling CMA support
Assertion failure at prov/psm3/psm3/ptl_am/ptl.c:184
```

CMA (`process_vm_readv`) needs matching credentials. Unprivileged Apptainer gives each
process its own user namespace, so `srun -n 4 apptainer exec` = 4 namespaces = EPERM.
(`apptainer exec IMG mpirun -n 4 …` puts all ranks in one container and CMA works — the
launch pattern decides it.) `apptainer-suid` would fix it at the cost of a setuid binary on
every node; the IPoIB path does not need it.

## Shared container

`/opt/cluster/software/containers/underworld3`, NFS-shared, group `uw3admin`, mode 2775.
`apptainer pull` is unprivileged, so publishing needs no sudo.

| Channel | Source | Retention |
|---|---|---|
| `development.sif` | UW3 `development` branch | last 2 |
| `latest.sif`, `vX.Y.Z.sif` | release tags | last 2 |

Local SIFs are a cache, not an archive: releases live under immutable GHCR tags and can be
re-pulled and checked against the sha256 in `MANIFEST`. Updates are manual, on request —
no cron, so a rolling tag never changes under an overnight job.

**Never overwrite a SIF in place.** Apptainer memory-maps it; rewriting one gives SIGBUS to
any job holding it. A symlink swap is safe — running jobs keep their inode — and so is
deleting an old SIF. The installer enforces this: content-addressed names, atomic symlink
swap, refuses images where `import underworld3` fails.

Version strings that look wrong: `release` reports `0.99.0b` because the image predates
upstream PR #358 (merged 2026-07-23), which removed a committed `_version.py` shadowing
setuptools-scm; `development` reports `0.0.0.dev0+g<sha>` because a branch build has no
tag. Both resolve at the next CI-built release.

## Memory: the SIF counts against your allocation

Slurm enforces memory via cgroups ([../slurm/README.md](../slurm/README.md)), and SIF pages
are charged to the job as page cache. Res-16, 2 ranks:

```
Peak memory:  1216 MB total, 614 MB peak rss
```

~600 MB is page cache — the shared libraries actually touched, not the whole 1.07 GB image.
Cache is reclaimable, so size `--mem` from rss plus headroom; provisioning for the total
over-requests ~600 MB per job, which matters on Gadi where memory is charged. A container
job still needs a few hundred MB more than bare metal.

The launcher reads the cgroup directly (`total_rss`, sampled every 2 s, batch node only)
because `sacct` is unavailable — accounting storage is disabled. `sstat -j <id> -o MaxRSS`
works on running jobs only.

## Setup notes

- Rocky 8.10 host, same as the image. Container OpenMPI 4.1.1, host 4.1.6.
- `dnf install -y apptainer` (1.5.3) was enough; EPEL and user namespaces were already on.
  `/usr` is not shared — install on every node. `/home` is NFS.
- Sudo only on the login node; nodes are reached with `sudo ssh nN '...'`.
- `srun --mpi=pmix` works (`pmix_v2`, `pmix`, `pmi2` offered).
- n1-n8, 104 CPUs each (2 x 26 cores x 2 threads).

## Benign noise

- `Ignoring PCI device with non-16bit domain` — hwloc.
- `mlx4_0` OpenFabrics warnings — openib being refused.
- `components` DeprecationWarning — `kaiju_test_stokes.py` predates the `conds=` API; left
  so it stays comparable to the bare-metal reference.
- `gamg` fallback RuntimeWarning (#625) — solver configuration. Real advice: build meshes
  with `refinement>=1` for production.
