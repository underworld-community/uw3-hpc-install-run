# Kaiju bare metal — retired

The shared install at `/opt/cluster/software/underworld3` was removed on 2026-09-11 and
the `underworld3/*` modules replaced with tombstones that point to the container. These
scripts are kept as a record; Gadi's bare-metal install follows the same pattern.

```
kaiju_install_shared.sh   shared install (was /opt/cluster/software/underworld3)
kaiju_install_user.sh     per-user install
kaiju_slurm_job.sh        Slurm template for the retired module
```
