"""
Two-rank MPI ping-pong: reports latency and bandwidth per message size.

Purpose is to tell whether a container run is actually using the fabric or has
silently fallen back to TCP. Run it with exactly 2 ranks on 2 DIFFERENT nodes —
same-node runs go through shared memory and reveal nothing about the network.

    srun --mpi=pmix -N 2 -n 2 apptainer exec <sif> python3 pingpong.py
    mpiexec -n 2 --map-by node singularity exec <sif> python3 pingpong.py

Rough expectations for the large-message plateau:
    IB FDR10 (40 Gb) RDMA   ~3-4 GB/s
    IB EDR   (100 Gb) RDMA  ~10-12 GB/s
    10 GbE / IPoIB          ~1 GB/s
    1 GbE                   ~0.1 GB/s
Latency at 8 B: ~1-2 us on RDMA, ~20-50 us over TCP.
"""

import sys

import numpy as np
from mpi4py import MPI

comm = MPI.COMM_WORLD
if comm.size != 2:
    if comm.rank == 0:
        print(f"needs exactly 2 ranks, got {comm.size}", file=sys.stderr)
    sys.exit(1)

rank = comm.rank
other = 1 - rank

# Report placement first: if both ranks name the same host, the numbers below
# measure shared memory and say nothing about the fabric.
host = MPI.Get_processor_name()
hosts = comm.gather(host, root=0)
if rank == 0:
    print(f"rank 0 on {hosts[0]}, rank 1 on {hosts[1]}")
    if hosts[0] == hosts[1]:
        print("WARNING: both ranks on one node — this measures shared memory, not the network")
    print(f"MPI: {MPI.Get_library_version().strip().splitlines()[0]}")
    print()
    print(f"{'bytes':>10} {'iters':>7} {'latency_us':>12} {'bandwidth_MB/s':>15}")

for exp in range(3, 25, 2):                      # 8 B .. 8 MB
    nbytes = 1 << exp
    buf = np.zeros(nbytes, dtype=np.uint8)
    # Fewer iterations as messages grow, so total time per size stays sane.
    iters = max(8, min(2000, (1 << 22) // nbytes))

    comm.Barrier()
    for _ in range(4):                           # warm up connection setup
        if rank == 0:
            comm.Send([buf, MPI.BYTE], dest=other)
            comm.Recv([buf, MPI.BYTE], source=other)
        else:
            comm.Recv([buf, MPI.BYTE], source=other)
            comm.Send([buf, MPI.BYTE], dest=other)

    comm.Barrier()
    t0 = MPI.Wtime()
    for _ in range(iters):
        if rank == 0:
            comm.Send([buf, MPI.BYTE], dest=other)
            comm.Recv([buf, MPI.BYTE], source=other)
        else:
            comm.Recv([buf, MPI.BYTE], source=other)
            comm.Send([buf, MPI.BYTE], dest=other)
    elapsed = MPI.Wtime() - t0

    if rank == 0:
        # One iteration is a round trip, so one-way latency is half of it.
        latency_us = (elapsed / iters / 2) * 1e6
        bandwidth = (nbytes * iters * 2) / elapsed / 1e6
        print(f"{nbytes:>10} {iters:>7} {latency_us:>12.2f} {bandwidth:>15.1f}")
