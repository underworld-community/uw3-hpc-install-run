# Running Underworld3 on Kaiju

How to run. The why — measurements and what broke — is in [FINDINGS.md](FINDINGS.md).

## Quick start

```bash
module load underworld3-container/release
cp /opt/cluster/software/containers/underworld3/kaiju_container_job.sh .
# edit SCRIPT=
sbatch kaiju_container_job.sh
```

The module sets `UW3_SIF` and the five MPI variables Kaiju needs; the job script does the
rest.

## Which container

| Module | Gets you | Use for |
|---|---|---|
| `underworld3-container/release` | current release | anything you intend to publish |
| `underworld3-container/development` | newest code | testing recent changes |

`development` moves whenever it is updated; results against it may not be reproducible
later. Check what you are about to run:

```bash
apptainer exec $UW3_SIF python3 -c "import underworld3 as uw; print(uw.__version__)"
```

Two version strings look wrong and are not: the current release reports `0.99.0b` (stale
version file in an image built before the upstream fix; the source is v3.1.0), and
`development` reports `0.0.0.dev0+g<sha>` (a branch build has no release number; the
commit is its identity).

`UW3_SIF` is a symlink that moves. The job script resolves it and prints `Container:` so
the log records exactly what ran.

## The job script

Edit `SCRIPT=` and the `#SBATCH` lines — `--ntasks` (MPI ranks), `--time`, and
`--nodes`/`--ntasks-per-node` for placement (52 cores per node). Or override at submission:

```bash
sbatch --ntasks=8 --time=02:00:00 --export=ALL,SCRIPT=/abs/path/model.py kaiju_container_job.sh
```

Do not remove the `APPTAINERENV_OMPI_*` / `PMIX_*` lines. Each prevents a specific failure:
a crash in matrix assembly, a 33x bandwidth loss, a segfault at exit.

Output: `uw3c_<jobid>.out` / `.err`. The `.err` has a few warnings on every run — see
[Errors](#errors).

## Memory

Kaiju enforces memory. Exceed the allocation and the job is killed:

```
slurmstepd: error: Detected 1 oom-kill event(s) in StepId=1982.batch cgroup.
```

Without `--mem` you get about **2.6 GB per task**. Ask for what you need:

```bash
sbatch --mem=64G ...             # whole job
sbatch --mem-per-cpu=4G ...      # scales with ranks
```

Every job prints what it used:

```
Peak memory:  1216 MB total, 614 MB peak rss, on node01
```

Size the next request from **rss plus headroom, not total**. The total includes the
container image, which is memory-mapped and counts against you but is reclaimable — the
kernel drops it under pressure rather than killing you. The figure is sampled every 2 s on
the batch node, so a very short job or a brief spike can read low.

Big models: n3 has 376 GB, double the others — `sbatch --constraint=bigmem --mem=300G`.

## Chaining jobs

`sbatch` occasionally fails with `I/O error writing script/environment to file`. Transient,
unexplained. For chains, use [`common/sbatch_retry.sh`](../../common/sbatch_retry.sh):

```bash
source /path/to/common/sbatch_retry.sh
sbatch_retry --ntasks=4 kaiju_container_job.sh     # retries transient failures only
sbatch_chain step1.sh step2.sh step3.sh             # afterok chain; cancels all if a submission fails
```

`afterok` releases the next job only on exit 0, so a job that segfaults on the way out
stalls the chain. The job script's MPI settings exist partly to prevent that.

## Developing Underworld3 in the container

Edit the source, build it *inside* the container on the login node (so the extensions
link against its Python and PETSc), into a directory of your own:

```bash
module load underworld3-container/development
apptainer exec $UW3_SIF bash -c "cd $HOME/underworld3 && SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0.dev0 \
    pip install --no-build-isolation --target=$HOME/uw3-editable ."
```

Then run with the normal job script. `EXTRA_PKGS` goes ahead of the image's own packages,
so your build shadows the installed one:

```bash
sbatch --export=ALL,EXTRA_PKGS=$HOME/uw3-editable,SCRIPT=/abs/path/model.py kaiju_container_job.sh
```

Do not set `APPTAINERENV_PYTHONPATH` yourself: it replaces the image's path instead of
adding to it, and petsc4py (in `/usr/local/lib`) stops importing.

Requires an image with a C++ compiler (`underworld3.ckdtree` is C++); check with
`apptainer exec $UW3_SIF rpm -q gcc-c++`. The image has no `git`, hence the pretend
version. If PETSc itself must change, that is a bare-metal job.

## Errors

Harmless, on every run:

| Message | Meaning |
|---|---|
| `Ignoring PCI device with non-16bit domain` | hwloc cosmetic |
| `error initializing an OpenFabrics device ... mlx4_0` | the deprecated IB driver being refused, as intended |
| `DeprecationWarning: The 'components' argument is deprecated` | old API in the test scripts |
| `Stokes: the velocity block fell back to 'gamg'` | real solver advice — use `refinement>=1` for production meshes |

Not harmless:

| Message | Do this |
|---|---|
| `Detected N oom-kill event(s)` | request more memory — see `Peak memory:` from a run that survived |
| `DependencyNeverSatisfied` in `squeue` | an upstream job failed; `scancel` the rest, or submit with `--kill-on-invalid-dep=yes` |
| `Segmentation fault` after `All checks passed` | MPI settings missing — load the module or check the job script |
| `I/O error writing script/environment to file` | transient; resubmit, or use `sbatch_retry` |

## Do not benchmark here

No RDMA: MPI runs over IPoIB, with ~10x the small-message latency of Gadi. Correctness and
convergence transfer; timings do not. Poor strong scaling here is the transport, not your
algorithm.

## Where things are

```
/opt/cluster/software/containers/underworld3/
  development.sif -> underworld3-development-<date>-<sha>.sif
  latest.sif      -> underworld3-v3.1.0-<date>-<sha>.sif
  v3.1.0.sif      -> (same)
  MANIFEST                      when, what, sha256, from where
  kaiju_container_job.sh        the template — copy it
  kaiju_container_install.sh    admin: publish a new image
```

## Updating the images (admin)

Manual, on request, by a member of `uw3admin` — no sudo:

```bash
D=/opt/cluster/software/containers/underworld3
$D/kaiju_container_install.sh v3.2.0      ghcr.io/underworldcode/underworld3-gadi:v3.2.0
$D/kaiju_container_install.sh development ghcr.io/underworldcode/underworld3-gadi:development
```

Pulls, refuses an image where `import underworld3` fails, names the file by content,
swaps the channel symlink atomically (running jobs keep their inode), appends to
`MANIFEST`, keeps the last two per channel. A release also moves `latest.sif`. One-time
setup is in the script header.
