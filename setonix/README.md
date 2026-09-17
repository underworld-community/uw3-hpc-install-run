# Setonix

Nothing is deployed yet. This directory holds the gating experiment — **which passed on
2026-09-17**: collective MPI-IO on `/scratch` works from inside a container under
`singularity/4.1.0-mpi`, with no extra binds. Pawsey's known issue is stale; their `-mpi`
module now bind-mounts the host `/host_lib64`, which is where `liblustreapi` comes from.

## Result (job 49382367, 4 ranks, `work` partition)

| Variant | `MPI vendor` | `liblustreapi` | Collective write |
|---|---|---|---|
| plain | CRAY MPICH 8.1.32 (ANL base 3.4a2) | loadable | **PASSED** |
| host Lustre libs bound | same | loadable | **PASSED** |

Two things learned on the way that shape the real image:

- **Build against `quay.io/pawsey/mpich-base:3.4.3_ubuntu24.04`, not the 4.2.2 tag.** Cray
  MPICH 8.1 is MPICH-3.4-based. mpi4py compiled against 4.2.2 headers failed to import
  (`undefined symbol: MPI_Buffer_iflush`, an MPI-4.1 call) once the host `libmpi` was
  bind-mounted over the container's. Same ABI, smaller API — PETSc and h5py would hit the
  same wall.
- `$PAWSEY_PROJECT`/`$MYSCRATCH` can be stale for a re-created account; check `id`.

This is raw MPI-IO, one layer below HDF5. The UW3 checkpoint through parallel HDF5 is the
remaining test, and it needs the real image — which this result says is worth building.

---

## The original question

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

If `liblustreapi` is absent from the host, the hypothesis dies for free. It is present
(`/usr/lib64/liblustreapi.so.1`, checked 2026-09-17). Stage it — and only it, plus any
non-glibc dependency `ldd` shows — into a directory to bind; binding the whole host
`/usr/lib64` would put SLES glibc ahead of the container's and break everything:

```bash
mkdir -p $MYSCRATCH/hostlib
cp -L /usr/lib64/liblustreapi.so.1 $MYSCRATCH/hostlib/
ldd /usr/lib64/liblustreapi.so.1        # copy anything here that is not libc/libm/libpthread/libdl
```

Then build and push the image from a machine with podman, pull on Setonix under
`singularity/4.1.0-mpi` (the flavour that bind-mounts host MPI), and submit
`setonix_probe.slurm` with your project as `--account`.

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
