"""
Setonix parallel-IO probe.

Pawsey document that MPI parallel IO inside a Singularity container fails on
Setonix with `ad_cray/ad_cray_adio_open.c:520: liblustreapi != NULL`, and that
there is no workaround. uw3-scaling-scripts/gadi_container_go.sh fixes the same
resolution failure on Gadi by binding the host library tree. This checks whether
that also works here.

Deliberately no HDF5: the assertion is in Cray MPICH's ROMIO layer, which HDF5
only sits on top of, so a collective MPI.File write reaches it directly.

Usage:
    srun -n 4 singularity exec <image> python3 mpiio_probe.py /scratch/<proj>/<user>/probe.bin
"""

import ctypes
import ctypes.util
import os
import sys

from mpi4py import MPI

comm = MPI.COMM_WORLD
rank, size = comm.rank, comm.size


def note(msg):
    if rank == 0:
        print(msg, flush=True)


path = sys.argv[1] if len(sys.argv) > 1 else "./probe.bin"

note("=" * 66)
note(f"ranks:      {size}")
note(f"target:     {path}")

# Which libmpi actually won: the container's MPICH, or the host Cray MPICH that
# the singularity -mpi flavour bind-mounts over it. If this does not say Cray,
# the bind-mount is not happening and nothing below is a valid test.
note(f"MPI vendor: {MPI.Get_library_version().strip().splitlines()[0]}")

# The direct test of Pawsey's stated cause. If ROMIO cannot dlopen this from
# inside the container, its Lustre driver aborts on the assertion.
found = ctypes.util.find_library("lustreapi")
loaded = None
for cand in filter(None, [found, "liblustreapi.so.1", "liblustreapi.so"]):
    try:
        ctypes.CDLL(cand)
        loaded = cand
        break
    except OSError:
        continue
note(f"liblustreapi: {'LOADABLE via ' + loaded if loaded else 'NOT LOADABLE — expect the ROMIO assertion'}")
note(f"LD_LIBRARY_PATH={os.environ.get('LD_LIBRARY_PATH', '(unset)')}")
note("=" * 66)

# Collective write: every rank writes its own 1 MiB block at its own offset.
# Write_at_all is the collective call that routes through ROMIO's Lustre driver.
block = 1024 * 1024
payload = bytearray([rank % 256]) * block

note("opening for collective write...")
fh = MPI.File.Open(comm, path, MPI.MODE_CREATE | MPI.MODE_WRONLY)
try:
    fh.Set_size(0)
    fh.Write_at_all(rank * block, payload)
finally:
    fh.Close()
note("collective write returned")

# Read back on every rank and verify, so a silently-truncated or interleaved
# write is caught rather than reported as success.
fh = MPI.File.Open(comm, path, MPI.MODE_RDONLY)
try:
    buf = bytearray(block)
    fh.Read_at_all(rank * block, buf)
finally:
    fh.Close()

ok = bytes(buf) == bytes(payload)
all_ok = comm.allreduce(ok, op=MPI.LAND)

if rank == 0:
    total = os.path.getsize(path)
    expected = block * size
    note(f"file size:  {total} bytes (expected {expected})")
    if all_ok and total == expected:
        note("==> PASSED: collective MPI-IO works in this container")
    else:
        note("==> FAILED: data mismatch or short file")
    os.remove(path)

sys.exit(0 if all_ok else 1)
