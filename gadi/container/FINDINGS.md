# Gadi container: findings

## MPI transport (measured 2026-09-11)

`gadi_pingpong_transports.pbs`: 2 ranks on 2 `normal` nodes, `common/pingpong.py`.

Hand-built `v3.1.0` image (job 178789211):

| | 8 B latency | 8 MB bandwidth | MPI seen by the ranks |
|---|---|---|---|
| A bare metal `openmpi/4.1.7` | 1.54 us | 13.6 GB/s | host 4.1.7, UCX |
| B container, plain | 2.26 us | 6.3 GB/s | container 4.1.1, `openib` |
| C container, host-MPI injection | 1.55 us | 13.6 GB/s | host 4.1.7, UCX |

CI-built image `ci-gadi-container` (job 178790720):

| | 8 B latency | 8 MB bandwidth | MPI seen by the ranks |
|---|---|---|---|
| A bare metal | 1.44 us | 13.6 GB/s | host 4.1.7, UCX |
| B container, plain | **11.8 us** | **3.2 GB/s** | container 4.1.1, **tcp** |
| C container, host-MPI injection | 1.53 us | 13.6 GB/s | host 4.1.7, UCX |

Refactored-layout image (`hpc_containers/`, job 179479794, 2026-09-21): A 1.44 us / 13.6 GB/s,
B 2.20 us / 6.2 GB/s (`openib` this time), C 1.51 us / 13.6 GB/s — unchanged.

**Injected, the container is indistinguishable from bare metal** on all images, at every
message size. CI images are fit to publish. This is the form `gadi_container_go.sh` used
throughout the scaling campaign.

**Plain is a lottery.** The container's UCX has no IB transports (`ucx_info -d`: `posix,
self, sysv, tcp`), so its own OpenMPI can only reach InfiniBand through the deprecated
`openib` BTL. On one node pair it did (half the bandwidth, +50% latency); on another both
`openib` and OFI failed device init and it fell to TCP over IPoIB — 8x latency, a quarter
of the bandwidth, exit 0, no error. Not a fallback to rely on for multi-node work.

Full tables, hand-built image (us, MB/s):

```
bytes        A lat/bw            B lat/bw            C lat/bw
     8    1.54      5.2       2.26      3.5       1.55      5.2
    32    1.65     19.4       2.55     12.5       1.64     19.5
   128    1.83     70.0       3.13     40.9       1.77     72.3
   512    2.80    182.6       3.12    164.1       2.58    198.7
  2048    2.88    710.7       3.61    567.0       2.83    722.9
  8192    4.75   1724.4       5.66   1447.1       4.58   1790.3
 32768    8.17   4009.4       8.98   3647.4       7.97   4108.9
131072   17.36   7549.2      21.14   6201.5      17.17   7631.7
524288   44.05  11903.1      77.54   6761.5      43.74  11986.3
  2 MB  159.62  13138.1     316.20   6632.3     159.81  13122.5
  8 MB  618.46  13563.8    1321.42   6348.2     618.00  13573.8
```

## What injection is

The container's `libmpi.so.40` (Rocky 8 OpenMPI 4.1.1) has the same SONAME as Gadi's
`openmpi/4.1.7`, so putting the host library tree first on `LD_LIBRARY_PATH` makes
Python/PETSc/h5py load the host MPI, UCX and hcoll. Two binds are needed: `/half-root`
(Gadi's real system libraries; `/lib64/*.so` are symlinks into it) and
`/opt/pbs/default/lib` (the host MPI links `libpbs`).

```bash
HOST_LIBS=/apps/openmpi/4.1.7/lib:/apps/openmpi-mofed5.8-pbs2021.1/4.1.7/lib
HOST_LIBS=$HOST_LIBS:/apps/ucx/1.17.0/lib:/apps/ucc/1.3.0/lib:/apps/hcoll/4.8.3228/lib
HOST_LIBS=$HOST_LIBS:/opt/pbs/default/lib:/half-root/usr/lib64:/half-root/lib64

mpiexec -n $PBS_NCPUS singularity exec --bind /half-root --bind /opt/pbs/default/lib $SIF \
    bash -c "LD_LIBRARY_PATH=$HOST_LIBS:\$LD_LIBRARY_PATH python3 model.py"
```

The paths pin `openmpi/4.1.7`; a module upgrade means updating them.

## Open question

One 3-rank single-node injected run (job 178499359, 2026-09-09) hung in
`mesh.petsc_save_checkpoint()` with `TL_UCP ERROR … Message truncated` / `UCC ERROR`, and
passed when rerun plain. The same injection ran 192 campaign jobs, including 8- and
27-rank partial-node ones, clean. n=1, not understood; if it recurs, drop `hcoll`/`ucc`
from `HOST_LIBS` rather than going plain.

## Noise

`help-mpi-btl-openib.txt / error in device init`, `fi_endpoint` (plain form) and the
`mlx5_0` / `OpenFabrics` banners are harmless. `LOG_CAT_ML … ucx_p2p is not available` is
hcoll choosing another hierarchy; also harmless.
