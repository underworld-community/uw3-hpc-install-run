# Setonix

Nothing is deployed. This directory holds the gating experiment.

## The problem

Pawsey's [Known Issues](https://pawsey.atlassian.net/wiki/spaces/US/pages/51929082) say
MPI software using parallel IO inside a Singularity container fails:

> `Assertion failed in file ../../../../src/mpi/romio/adio/ad_cray/ad_cray_adio_open.c at line 520: liblustreapi != NULL`
>
> "There is no workaround that does not require a change in the workflow."

UW3 builds `HDF5_MPI=ON` and checkpoints through it, so at face value that rules out a
Setonix container.

## Why it may not be a blocker

That is a `liblustreapi` resolution failure — the same one `gadi_container_go.sh` works
around on Gadi by binding the host library tree so ROMIO can `dlopen` it. If that
transfers, it is a bind flag, not a workflow change.

## The probe

No HDF5: the assertion is in Cray MPICH's ROMIO layer, which `mpi4py` doing a collective
`MPI.File` write reaches directly. A one-minute `mpi4py` build instead of a parallel-HDF5
compile.

`Containerfile` builds on `quay.io/pawsey/mpich-base:mpich4.2.2-ubuntu24.04` — Pawsey's own
image, ABI-compatible with Cray MPICH. `setonix_probe.slurm` runs the test twice: plain,
then with the host library tree bound.

## Running it

First, on a login node, no container needed:

```bash
ldconfig -p | grep -i lustre
find /usr /lib64 /opt/cray -name "liblustreapi*" 2>/dev/null
```

If `liblustreapi` is absent from the host, the hypothesis dies for free. Otherwise build
and push from a machine with podman, pull on Setonix under `singularity/4.1.0-mpi` (the
flavour that bind-mounts host MPI), and submit `setonix_probe.slurm` with your project as
`--account`.

Three lines decide it: `MPI vendor:` must say Cray MPICH (else the `-mpi` module is not
binding and the test is invalid); `liblustreapi:` loadable or not, per variant; `PASSED`
or the ROMIO assertion. Plain failing and bound passing means the bind fixes it. Both
failing means Pawsey are right and the options are a no-parallel-HDF5 build or bare metal.

## Why Setonix needs its own image

| | Gadi / Kaiju | Setonix |
|---|---|---|
| Base OS | Rocky 8.10 | Ubuntu 24.04 |
| MPI | OpenMPI, `libmpi.so.40` | Cray MPICH, `libmpi.so.12` |

The OS constraint is glibc: Cray MPICH is built against SLES 15 (glibc 2.31) and the `-mpi`
flavour binds those host libraries in, so a Rocky 8 container (glibc 2.28) fails on
missing symbols.
