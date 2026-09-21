# Setonix container: findings

The why behind [README.md](README.md). Image: `underworld3-setonix` from
`docs/developer/hpc_containers/` (Ubuntu 24.04 + MPICH 3.4.3 base), first validated 2026-09-21.

## What works, measured

| Check | Result | Job |
|---|---|---|
| Host MPI bound in | `CRAY MPICH version 8.1.32.110 (ANL base 3.4a2)` reported inside the container | all |
| Collective MPI-IO on `/scratch` | PASSED, plain and with Lustre libs bound (the bind was unnecessary) | 49382367 |
| UW3 Stokes, 4 ranks, parallel HDF5 checkpoint on `/scratch` (Lustre) | PASSED, `Output saved`, 19 s wall | 49760066 |
| Transport, 2 ranks on 2 nodes | on the Slingshot fabric, not TCP — table below | 49764166 |

Pawsey's Known Issues page still says parallel IO cannot work in a container. With the
current `singularity/4.1.0-mpi` module it does: the module binds `/host_lib64`, which is
where `liblustreapi` comes from, so Cray's ROMIO Lustre driver finds it.

## Transport (2 ranks, 2 nodes, `work` partition)

| | 8 B latency | 128 KB | 8 MB bandwidth |
|---|---|---|---|
| bare metal (`cray-python`) | 3.20 us | 11.2 GB/s | 23.8 GB/s |
| container, `singularity/4.1.0-mpi` | 3.34 us | 10.3 GB/s | 15.9 GB/s |

Latency and everything up to ~128 KB match bare metal, so the container is on the fabric
(TCP would be 20+ us). From 512 KB up the container trails — 67% of bare metal at 8 MB.
n=1 each on different node pairs, so this is a note, not a finding: repeat on one node
pair before reading anything into it. For UW3 it is the wrong regime to worry about
first — Krylov solves are dominated by small messages and `allreduce` latency, which match.

```
bytes      bare metal          container
     8     3.20      2.5      3.34      2.4
    32     3.21     10.0      3.30      9.7
   128     3.75     34.1      3.84     33.3
   512     3.92    130.5      4.39    116.6
  2048     4.41    464.8      4.65    440.0
  8192     4.56   1798.2      4.86   1686.8
 32768     7.75   4229.6      8.16   4013.9
131072    11.75  11158.8     12.77  10263.3
524288    27.96  18748.7     37.45  13999.4
  2 MB    93.14  22516.3    112.24  18683.7
  8 MB   352.20  23818.1    526.38  15936.3
                 (us, MB/s)
```

Compare Gadi bare metal: 1.44 us, 13.6 GB/s. Setonix has twice the bandwidth and twice
the latency; different fabric (Slingshot-11 vs InfiniBand HDR).

## Why the image is built the way it is

- **Ubuntu, not Rocky.** The `-mpi` module bind-mounts host Cray MPICH, built against
  SLES 15 glibc 2.31. A Rocky 8 image (glibc 2.28) fails on missing symbols; Ubuntu 24.04
  has 2.39.
- **MPICH 3.4.3, not 4.2.2.** Cray MPICH 8.1 is MPICH-3.4-based. mpi4py compiled against
  MPICH 4.2.2 headers failed to import (`undefined symbol: MPI_Buffer_iflush`, MPI-4.1)
  once the host library was bound over it. Same ABI (`libmpi.so.12`), smaller API; PETSc
  and h5py would have hit the same wall.
- **No MPI tuning at launch**, unlike Kaiju (five variables) and Gadi (library injection):
  the `-mpi` module does the binding, and libfabric is included.

## Account gotchas

- `$PAWSEY_PROJECT`, `$MYSCRATCH`, `$MYSOFTWARE` can point at a stale project for a
  re-created account (they said `pawsey0407`; `id` said `pawsey1147`). Check `id` before
  filing a "my scratch does not exist" ticket. The default project is on the account
  record; override in `~/.bash_profile` until Pawsey fix it.
- Home is 1 GB. Containers, caches and output all go under `$MYSCRATCH`; a run from `$HOME`
  also writes its checkpoint to NFS rather than Lustre, which is not the path you want
  tested.

## Benign noise

Same as Gadi and Kaiju: `components` DeprecationWarning from the test script, `gamg`
fallback advisory (#625).
