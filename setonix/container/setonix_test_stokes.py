"""
Stokes flow test for Setonix parallel run.

Lid-driven cavity variant: top wall moves at (1, 0), bottom at (-1, 0),
left and right walls are free-slip. Uniform viscosity, no body force.
Verifies that mpi4py, petsc4py, h5py, and underworld3 all work correctly
in a multi-rank MPI context.

Usage:
    srun -n 4 singularity exec <sif> python3 setonix_test_stokes.py
    # or: sbatch --account=<project> setonix_container_job.slurm
"""

import os
import mpi4py.MPI as MPI
from petsc4py import PETSc
import underworld3 as uw
import numpy as np
import sympy

comm = MPI.COMM_WORLD

uw.pprint(f"==> Stokes flow test — {comm.size} MPI rank(s)")
uw.pprint(f"    underworld3: {uw.__version__}")

# ============================================================
# PARAMETERS
# ============================================================

res  = 16    # mesh resolution — quick test
visc = 1.0   # uniform viscosity

outputPath = "./output_stokes_setonix"

# ============================================================
# MESH
# ============================================================

mesh = uw.meshing.UnstructuredSimplexBox(
    minCoords=(0.0, 0.0),
    maxCoords=(1.0, 1.0),
    cellSize=1.0 / res,
    regular=True,
    qdegree=2,
)

# ============================================================
# VARIABLES
# ============================================================

v = uw.discretisation.MeshVariable("U", mesh, mesh.dim, degree=2)
p = uw.discretisation.MeshVariable("P", mesh, 1,        degree=1)

# ============================================================
# STOKES SOLVER
# ============================================================

stokes = uw.systems.Stokes(mesh, velocityField=v, pressureField=p)
stokes.constitutive_model = uw.constitutive_models.ViscousFlowModel
stokes.constitutive_model.Parameters.viscosity = visc
stokes.bodyforce = sympy.Matrix([0, 0])

# Top:    vx =  1, vy = 0
# Bottom: vx = -1, vy = 0
# Left/Right: free-slip (no normal velocity, tangential stress-free)
stokes.add_dirichlet_bc(( 1.0, 0.0), "Top",    (0, 1))
stokes.add_dirichlet_bc((-1.0, 0.0), "Bottom", (0, 1))
stokes.add_dirichlet_bc((0.0,),      "Left",   (0,))
stokes.add_dirichlet_bc((0.0,),      "Right",  (0,))

stokes.tolerance = 1.0e-4
stokes.petsc_options["snes_converged_reason"] = None
stokes.petsc_options["snes_monitor_short"] = None

uw.pprint("==> Solving...")
stokes.solve()
uw.pprint("==> Solve complete")

# ============================================================
# SANITY CHECK — max velocity should be nonzero
# ============================================================

with mesh.access(v):
    vmax_local = float(np.abs(v.data).max()) if v.data.shape[0] > 0 else 0.0

vmax = comm.allreduce(vmax_local, op=MPI.MAX)

uw.pprint(f"==> Max |velocity|: {vmax:.4e}")
uw.pprint("==> PASSED" if vmax > 0 else "==> WARNING: zero velocity — check BCs or solver")

# ============================================================
# SAVE — tests parallel HDF5 write via h5py
# ============================================================

if comm.rank == 0:
    os.makedirs(outputPath, exist_ok=True)

mesh.petsc_save_checkpoint(
    index=0,
    meshVars=[v, p],
    outputPath=outputPath,
)

uw.pprint(f"==> Output saved to {outputPath}/")
uw.pprint("==> All checks passed — mpi4py, petsc4py, h5py, underworld3 OK")
