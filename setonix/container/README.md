# Running Underworld3 on Setonix

How to run. The why — what was measured and why the image is built as it is — is in
[FINDINGS.md](FINDINGS.md).

## Quick start

Everything lives under `$MYSCRATCH`; `$HOME` is 1 GB.

```bash
module load singularity/4.1.0-mpi
mkdir -p $MYSCRATCH/containers && cd $MYSCRATCH/containers
singularity pull underworld3-setonix.sif docker://ghcr.io/underworldcode/underworld3-setonix:latest

cd $MYSCRATCH/my-run
cp /path/to/repo/setonix/container/setonix_container_job.slurm .
# edit SCRIPT=, --ntasks, --time
sbatch --account=$PAWSEY_PROJECT setonix_container_job.slurm
```

`singularity/4.1.0-mpi`, not the default `-slurm` flavour: only `-mpi` bind-mounts the
host Cray MPICH, and without it the ranks would talk over TCP.

## The job script

Edit `SCRIPT=` and the `#SBATCH` lines — `--ntasks` (ranks), `--nodes`, `--time`
(Setonix nodes have 128 cores). Or override at submission:

```bash
sbatch --account=$PAWSEY_PROJECT --ntasks=128 --nodes=1 --time=02:00:00 \
       --export=ALL,SCRIPT=/abs/path/model.py setonix_container_job.slurm
```

The job prints an `MPI:` line before running. It must say `CRAY MPICH`; if it says
`MPICH Version: 3.4.3` the module is wrong and the run is on TCP.

Output: `uw3c_<jobid>.out`. Expect the same benign warnings as on Gadi and Kaiju
(`components` deprecation from old scripts, the `gamg` advisory).

## Check the version

```bash
singularity exec $MYSCRATCH/containers/underworld3-setonix.sif \
    python3 -c "import underworld3 as uw; print(uw.__version__)"
```

## Performance

The container is on the Slingshot fabric: latency and small-message bandwidth match bare
metal. Large-message bandwidth measured lower in one run (see FINDINGS); if your model is
dominated by large halo exchanges, re-measure before drawing conclusions. No scaling
study has been done on Setonix yet.

## Files

```
setonix_container_job.slurm   Slurm template
setonix_test_stokes.py        4-rank Stokes test with parallel-HDF5 checkpoint — the validation run
```

The gating experiment that preceded all this is in [../probe/](../probe/).
