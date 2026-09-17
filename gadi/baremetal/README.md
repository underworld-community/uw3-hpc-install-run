# Running Underworld3 on Gadi (bare metal)

Shared pixi install at `/g/data/m18/software/uw3-pixi`:

```bash
qsub gadi_pbs_job.sh                    # edit SCRIPT= first, or -v SCRIPT=...
```

Per-user install, for modifying PETSc or UW3 itself:

```bash
source gadi_install_user.sh install     # first time
source gadi_install_user.sh             # later sessions
```

## Files

```
gadi_pbs_job.sh           PBS template
gadi_install_shared.sh    shared install to /g/data/m18/software/uw3-pixi (admin)
gadi_install_user.sh      per-user install
```
