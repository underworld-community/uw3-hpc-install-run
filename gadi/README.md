# Running Underworld3 on Gadi

Container (recommended) or bare-metal pixi install. Same performance; see
[FINDINGS.md](FINDINGS.md).

## Container

```bash
cp /path/to/repo/gadi/gadi_container_job.sh .
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

## Bare metal

Shared pixi install at `/g/data/m18/software/uw3-pixi`:

```bash
qsub gadi_pbs_job.sh                    # edit SCRIPT= first, or -v SCRIPT=...
```

Per-user install, for modifying PETSc or UW3 itself:

```bash
source gadi_install_user.sh install     # first time
source gadi_install_user.sh             # later sessions
```

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
gadi_container_job.sh         PBS template, container, host MPI injected
gadi_container_install.sh     admin: publish an image
gadi_pbs_job.sh               PBS template, bare metal
gadi_install_shared.sh        shared bare-metal install (admin)
gadi_install_user.sh          per-user bare-metal install
gadi_test_stokes.py           the test either template runs by default
gadi_pingpong_transports.pbs  the measurement behind FINDINGS.md
```
