# Running Underworld3 on Setonix

How to run. The why — what was measured and why the image is built as it is — is in
[FINDINGS.md](FINDINGS.md).

## Quick start

Image on `$MYSOFTWARE` (scratch files unused for 21 days are purged), runs on
`$MYSCRATCH` (Lustre); `$HOME` is only 1 GB.

```bash
module load singularity/4.1.0-mpi
mkdir -p $MYSOFTWARE/containers && cd $MYSOFTWARE/containers
singularity pull underworld3-setonix.sif docker://ghcr.io/underworldcode/underworld3-setonix:latest

mkdir -p $MYSCRATCH/my-run && cd $MYSCRATCH/my-run
cp /path/to/repo/setonix/container/setonix_container_job.slurm .
# edit SCRIPT=, --ntasks, --time
sbatch --account=$PAWSEY_PROJECT setonix_container_job.slurm
```

Until the first upstream release is built, pull
`docker://ghcr.io/jcgraciosa/underworld3-setonix:ci-gadi-container` instead.

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
singularity exec $MYSOFTWARE/containers/underworld3-setonix.sif \
    python3 -c "import underworld3 as uw; print(uw.__version__)"
```

## Developing Underworld3 in the container

Edit the source, build it *inside* the container on a login node (so the extensions link
against its Python and PETSc), into a directory of your own. Keep both on `$MYSOFTWARE`:

```bash
module load singularity/4.1.0-nompi        # build against the image's own MPICH, as CI does
SIF=$MYSOFTWARE/containers/underworld3-setonix.sif
mkdir -p $MYSOFTWARE/uw3-editable
singularity exec --bind $MYSOFTWARE/underworld3:/src --bind $MYSOFTWARE/uw3-editable:/editable $SIF \
    bash -c "cd /src && SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0.dev0 pip install --no-build-isolation --target=/editable ."
```

Then run with the normal job script. `EXTRA_PKGS` goes ahead of the image's own packages,
so your build shadows the installed one:

```bash
sbatch --account=$PAWSEY_PROJECT --export=ALL,EXTRA_PKGS=$MYSOFTWARE/uw3-editable,SCRIPT=/abs/path/model.py \
       setonix_container_job.slurm
```

Do not set `SINGULARITYENV_PYTHONPATH` yourself: it replaces the image's path instead of
adding to it, and petsc4py (in `/usr/local/lib`) stops importing.

Needs the C++ compiler in the image (`underworld3.ckdtree` is C++): check with
`singularity exec $SIF g++ --version`. The image has no `git`, hence the pretend
version. Changing PETSc itself is a bare-metal job.

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
