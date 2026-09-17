# Kaiju: Slurm memory and cgroup configuration

## What changed for you

Since 2026-09-10 Slurm enforces memory:

- **Jobs without `--mem` get ~2.6 GB per task** (`DefMemPerCPU=1300`; a task is one core =
  2 CPUs). A model that used to run may now be OOM-killed. Ask for what you need —
  `--mem=64G` for the job, or `--mem-per-cpu=4G` to scale with ranks. The container job
  script prints `Peak memory:` after every run; size from that
  ([../container/README.md](../container/README.md#memory)).
- **`--constraint=bigmem` targets n3** (376 GB, double the others).
- **Ranks are pinned to cores.** Timings are less noisy, but not comparable with anything
  measured before.

The rest is the administrator's record.

---

Changed 2026-09-10. Slurm 20.11.9, cgroup v1, Rocky 8.10, n1-n8. Backups on every node as
`/etc/slurm/{slurm,cgroup}.conf.<stamp>`.

## Why

Memory was not tracked (`RealMemory` unset, `sinfo` showed `MEMORY 1`). A 2-task job could
take all 187 GB of a shared node and trigger the kernel OOM killer, which picks a victim by
heuristic — possibly someone else's job. `task/none` meant no affinity, so co-scheduled
jobs interfered and every timing was noisy. `proctrack/pgid` let processes escape cleanup.

## Changes

`/etc/slurm/slurm.conf`:

| From | To |
|---|---|
| `ProctrackType=proctrack/pgid` | `proctrack/cgroup` |
| `TaskPlugin=task/none` | `task/affinity,task/cgroup` |
| `SelectTypeParameters=CR_Core` | `CR_Core_Memory` |
| `JobAcctGatherType=jobacct_gather/none` | `jobacct_gather/cgroup` |
| — | `DefMemPerCPU=1300` |

Nodes are not homogeneous, so the definition is split:

```
NodeName=n[1-2,5,7-8] CPUs=104 Sockets=2 CoresPerSocket=26 ThreadsPerCore=2 RealMemory=188000 State=UNKNOWN
NodeName=n3           ... RealMemory=378000 Features=bigmem State=UNKNOWN
NodeName=n4           ... RealMemory=172000 State=UNKNOWN
NodeName=n6           ... RealMemory=140000 State=UNKNOWN
```

Physical: 191572 MB (n1/2/5/7/8), 385108 (n3), 176201 (n4), 143944 (n6). `RealMemory` sits a
few GB below physical, or Slurm allocates every byte and the node OOMs anyway.

`/etc/slurm/cgroup.conf`:

```
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedSwapSpace=0
```

## Two traps

**`slurmd -C` on one node is not enough.** n1 reported 191572 MB, `RealMemory` was set
uniformly, and n4/n6 drained with "Low RealMemory". Check every node.

**`ConstrainRAMSpace` alone enforces nothing with swap present.** It caps RSS only; a job
requesting 100 MB allocated 500 MB by swapping. `ConstrainSwapSpace=yes` +
`AllowedSwapSpace=0` makes an overshoot an OOM-kill. Needs kernel swap accounting
(`/sys/fs/cgroup/memory/memory.memsw.limit_in_bytes` must exist); if absent, disabling swap
on compute nodes is cheaper than `swapaccount=1`, and better — swapping turns a fast
failure into hours of thrashing.

## Rollout

`slurm.conf` and `cgroup.conf` are copied to each node, not shared; both plugin changes
need `slurmd` restarted everywhere, so drain first.

```bash
for n in n{1..8}; do sudo scp -q /etc/slurm/{slurm,cgroup}.conf $n:/etc/slurm/; done
sudo systemctl restart slurmctld
for n in n{1..8}; do sudo ssh $n 'systemctl restart slurmd'; done
sudo scontrol update nodename=n4,n6 state=RESUME
```

Sudo is per-host: login node only. Node work goes through `sudo ssh nN '...'`.

## Verified

`sbatch --mem=100M` allocating 500 MB → `Detected 1 oom-kill event(s)`.
`--constraint=bigmem` lands on n3. All eight nodes idle with their own memory.

## Still missing

`sacct` does not work — accounting storage is disabled, so there is no `MaxRSS` history
(`sstat` works on running jobs only). `accounting_storage/filetxt` would do for 8 nodes;
`slurmdbd` + MariaDB is the full answer. Worth a separate change: `MaxRSS` is the "will
this fit on Gadi" number.
