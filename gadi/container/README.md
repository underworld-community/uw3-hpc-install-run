# Running Underworld3 on Gadi (container)

How to run. The why — the transport measurement — is in [FINDINGS.md](FINDINGS.md).

## Quick start

```bash
cp /path/to/repo/gadi/container/gadi_container_job.sh .
# edit SCRIPT= and the #PBS ncpus / mem / walltime lines
qsub gadi_container_job.sh
```

Runs the current release (`latest.sif` in `/g/data/m18/software/containers/underworld3/`;
`-v SIF=.../development.sif` for the newest code) with **the host MPI injected**. Do not
simplify it to a plain `mpiexec singularity exec` for anything multi-node:

> Uninjected, the container's own OpenMPI reaches InfiniBand only through the deprecated
> `openib` driver — half the bandwidth — or misses it and lands on TCP: 8x the latency, a
> quarter of the bandwidth, exit 0, no error. Which one you get varies by run. Injected,
> the container matches bare metal exactly.

Override at submission:

```bash
qsub -v SCRIPT=/abs/path/model.py -l ncpus=96,mem=380gb,walltime=02:00:00 gadi_container_job.sh
```

Extra Python packages the image lacks — install once, then pass the directory:

```bash
pip install --target=/scratch/m18/$USER/uw3-extra-pkgs assess
qsub -v EXTRA_PKGS=/scratch/m18/$USER/uw3-extra-pkgs,SCRIPT=... gadi_container_job.sh
```

Pulling your own image (cache off `$HOME`, which is 10 GB):

```bash
export SINGULARITY_CACHEDIR=/scratch/m18/$USER/.singularity
module load singularity
singularity pull docker://ghcr.io/underworldcode/underworld3-gadi:latest
qsub -v SIF=$PWD/underworld3-gadi_latest.sif ... gadi_container_job.sh
```

## Developing Underworld3 in the container

Edit the source, build it *inside* the container on a login node (so the extensions link
against its Python and PETSc), and put the result on scratch:

```bash
module load singularity
SIF=/g/data/m18/software/containers/underworld3/development.sif
singularity exec --bind ~/underworld3:/src $SIF bash -c \
    "cd /src && SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0.dev0 \
     pip install --no-build-isolation --target=/scratch/m18/$USER/uw3-editable ."
```

Then run with the normal template — `EXTRA_PKGS` is prepended to `PYTHONPATH`, so your
build shadows the installed one:

```bash
qsub -v EXTRA_PKGS=/scratch/m18/$USER/uw3-editable,SCRIPT=/abs/path/model.py gadi_container_job.sh
```

Needs an image with a C++ compiler (`underworld3.ckdtree` is C++): check with
`singularity exec $SIF rpm -q gcc-c++`. The image has no `git`, hence the pretend
version. Changing PETSc itself is a bare-metal job.

## Shared images (admin)

```
/g/data/m18/software/containers/underworld3/
  latest.sif       -> underworld3-vX.Y.Z-<date>-<sha12>.sif
  development.sif  -> underworld3-development-<date>-<sha12>.sif
  vX.Y.Z.sif       -> (per release)
  MANIFEST          when, what, sha256, from where
```

Manual, on a login node:

```bash
gadi_container_install.sh v3.2.0      ghcr.io/underworldcode/underworld3-gadi:v3.2.0
gadi_container_install.sh development ghcr.io/underworldcode/underworld3-gadi:development
```

Pulls to scratch, refuses an image where `import underworld3` fails, names the file by
content, makes it read-only, swaps the symlink atomically, appends to `MANIFEST`, keeps the
last two per channel. One-time setup is in the script header. Releases as they appear;
`development` on request.

## Files

```
gadi_container_job.sh         PBS template, host MPI injected
gadi_container_install.sh     admin: publish an image
gadi_pingpong_transports.pbs  the measurement behind FINDINGS.md
```
