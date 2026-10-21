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
`--nodes`/`--ntasks-per-node` for placement (52 cores per node; Slurm counts hyperthreads and
reports 104 CPUs, so `--ntasks-per-node=52` is one rank per core). Or override at submission:

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

## Running a branch of Underworld3

Any branch whose PETSc matches the image can run without a new container: build it inside
the image, on the login node, into a directory of your own, and the job script puts it
ahead of the image's copy. Verified 2026-10-21 with `bugfix/backward-nodes-snapshot-order`:
a 226 s build, then its tests passed serially and on 2 ranks across 2 nodes.

**1. Get an image with a C++ compiler.** `underworld3.ckdtree` is C++. The shared images
installed in 2026-09 predate `gcc-c++` in the runtime layer (added 2026-09-17), so until
they are refreshed, pull the current image into your home. This needs no admin rights;
it took 111 s and is 1.09 GB:

```bash
mkdir -p ~/uw3/images && cd ~/uw3/images
apptainer pull --name uw3-gadi-development-$(date +%Y%m%d).sif \
    docker://ghcr.io/underworldcode/underworld3-gadi:development
apptainer exec uw3-gadi-development-*.sif rpm -q gcc-c++      # must not say "not installed"
```

**2. Build the branch into an overlay** (never `pip install -e`). The image has no `git`,
hence the pretend version:

```bash
git clone https://github.com/underworldcode/underworld3 ~/uw3/src
cd ~/uw3/src && git checkout <branch>
apptainer exec ~/uw3/images/uw3-gadi-development-<date>.sif bash -c \
    "cd ~/uw3/src && SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0.dev0 \
     pip install --no-build-isolation --no-deps --target=$HOME/uw3/overlay-<branch> ."
```

`--no-deps` keeps pip from pulling anything into the overlay; a branch that needs a newer
Python package than the image has will then fail at import, which is the signal to use a
newer image rather than to add packages.

**3. Run it** with the job script from this repository. The site copy in
`/opt/cluster/software/containers/underworld3/` predates `EXTRA_PKGS`. Pass the image as
`CONTAINER=`, which overrides `UW3_SIF` from the module. Load the module anyway for its MPI
settings:

```bash
module load underworld3-container/development
sbatch --export=ALL,CONTAINER=$HOME/uw3/images/uw3-gadi-development-<date>.sif,\
EXTRA_PKGS=$HOME/uw3/overlay-<branch>,SCRIPT=/abs/path/model.py kaiju_container_job.sh
```

The job log's `Container:` line records what ran. To check that the overlay is in use,
`python3 -c "import underworld3 as uw; print(uw.__file__)"` should print
`/uw3-extra/underworld3/__init__.py`. To run a branch's tests, make `SCRIPT` a two-line
file that calls `pytest.main(["tests/test_NNNN_name.py", "-q", "-p", "no:cacheprovider"])`
from the checkout. (The 2026-10-21 runs used a pytest variant of the job script; this
wrapper does the same job but has not been run on Kaiju yet.)

Do not set `APPTAINERENV_PYTHONPATH` yourself: it replaces the image's path instead of
adding to it, and petsc4py (in `/usr/local/lib`) stops importing.

**If the branch needs a different PETSc** or new Python dependencies, build a branch image
instead: the `GHCR: HPC Underworld3 images` workflow in `underworldcode/underworld3`
(`hpc-uw3-image.yml`) takes `uw3_branch` and `image_tag` on a manual run and publishes
`ghcr.io/underworldcode/underworld3-gadi:<tag>`, which you pull as in step 1.

## Files and I/O

- Submit from under your home directory. `/tmp` is node-local: a job submitted from
  `/tmp` runs, but its output never reaches the login node.
- `/home` lives on the login node and the compute nodes mount it over NFS, so all job I/O
  goes through the login node (20 cores, 92 GB). Heavy checkpointing from several nodes at
  once contends there. There is no scratch filesystem.
- `/home` is a single disk on a single machine, not a backup: copy results that matter
  elsewhere.

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
