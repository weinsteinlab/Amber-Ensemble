# Amber Ensemble

Utilities to set up and launch **Amber MD** “swarms” (many independent trajectories) on Slurm-based clusters.  
Two launch modes are supported:

- **array** — one job array with `N` array tasks (one trajectory per task).
- **alloc** — allocate nodes and launch `N` per-trajectory tasks yourself (one srun per trajectory).

The scripts auto-detect the cluster via Slurm’s `ClusterName` and load the right Amber stack. Supported clusters are **scu**, **cayuga**, **delta**, and **frontier**. If the cluster is *not* one of these, the run will **abort** (no silent fallback).

> You run `./launch_swarm.sh` (not `sbatch`). It submits the real jobs and wires up dependencies for chained subjobs per trajectory.


---

## Table of Contents

1. [Repository layout](#repository-layout)  
2. [Prerequisites](#prerequisites)  
3. [Cluster autodetect & Amber backends](#cluster-autodetect--amber-backends)  
4. [Quick start](#quick-start)  
5. [Configuration — `launch_swarm.sh`](#configuration--launch_swarmsht)  
6. [Run modes](#run-modes)  
   - [Array mode](#array-mode)  
   - [Alloc mode](#alloc-mode)  
7. [How chaining & restarts work](#how-chaining--restarts-work)  
8. [Directory conventions & inputs](#directory-conventions--inputs)  
9. [Logs & outputs](#logs--outputs)  
10. [Safe cleanup (trash) behavior](#safe-cleanup-trash-behavior)  
11. [Setting wall time](#setting-wall-time)  
12. [Troubleshooting](#troubleshooting)  
13. [FAQ](#faq)

---

## Repository layout

```
Amber-Frontier-Ensemble/
├─ launch_swarm.sh              # submit orchestrator (array or alloc)
├─ submit_swarm_subjobs.sh      # per-trajectory runner (does safe cleanup & srun)
├─ setup_individual_swarm.sh    # helper to make per-traj directory scaffolding
├─ run_amber.sh                 # cluster-aware wrapper that runs pmemd.{cuda,hip}
├─ inputs/                      # your input bundles (topology, mdin, rst7, etc.)
└─ raw_swarms/                  # generated swarms + logs
   ├─ submission_logs/          # Slurm stdout for submission steps
   └─ swarm0000/                # one directory per swarm
      ├─ swarm0000_traj0000/    # one directory per trajectory
      ├─ swarm0000_traj0001/
      └─ ...
```

---

## Prerequisites

- A Slurm cluster with GPUs and a working Amber install that provides one of:
  - **`pmemd.cuda`** (NVIDIA backends) or
  - **`pmemd.hip`** (AMD ROCm backends).
- Your account / allocation and partition names.
- The `run_amber.sh` script has module and environment setup for the supported clusters (see below). If your site differs, edit that script’s case block.

> **No `~/.bashrc` edits are required**. All environment is set inside the job via `run_amber.sh`.

---

## Cluster autodetect & Amber backends

`run_amber.sh` calls `scontrol show config | awk -F= '/ClusterName/ {print $2}'` to detect the cluster and then loads site-specific modules / Amber env:

- **frontier**  
  ```bash
  module load ums/default
  module load ums002/default
  module load openmpi/4.1.5
  module load rocm/5.3.0
  source /ccs/proj/bip109/frontier/amber22_gcc11.2/amber22_src/dist/amber.sh
  # Uses: pmemd.hip
  ```

- **scu**  
  ```bash
  source /software/apps/amber/amber24/pmemd24/amber.sh
  module load cuda/12.2.1-gcc-8.2.0-23runmx
  module load openmpi/4.1.5
  # Uses: pmemd.cuda
  ```

- **cayuga**  
  ```bash
  module load amber/24
  # Uses: pmemd.cuda
  ```

- **delta**  
  (Set according to your A100/MI100 partition; default is **CUDA** path.)  
  ```bash
  # Typical CUDA stack on A100 partitions
  module load cuda
  module load openmpi/4.1.x
  # Uses: pmemd.cuda
  ```

If the cluster name is not one of the above, the script **exits with an error**. Add a new case to `run_amber.sh` if you need another site.

---

## Quick start

0. **Download code**
   
   Clone a copy of this repository, in a directory that is appropriate for running swarms of MD simulations.
   ```
   cd wherever_you_wish_to_run
   git clone git@github.com:weinsteinlab/Amber-Ensemble.git
   ```

   Optionally, you can rename the cloned repository to something meaningful for your calculations
   ```
   mv Amber-Frontier-Ensemble my_Amber_ensemble
   ```
   Once this is done, go into this directory:
   ```
   cd my_Amber_ensemble # or whatever the directory is named at this point 
   ```
   **Note: directory is hereafter referred to as the parent directory**
   

2. **Stage inputs**  
  **Note:** You'll see there is another directory called `./common`: do **NOT** edit anything in this directory! It contains a script that facilitate job management and should not be edited by the user.

  `./inputs` should contain a separate subdirectory for each unique system you wish to run. These subdirectories MUST have 4-zero-padded, zero-indexed names (e.g., `0000`, `0001`, `0002`, etc.). Deviating from this nomenclature WILL break the scripts.

  **Note:** This workflow assumes you are RESTARTING Amber simulations (i.e., you have already built/equilibrated the system with CHARMM-GUI).

  Each subdirectory must contain all of the simulation system-specific files needed to simulate your system with Amber 22:
*  **parm.parm7**: this protein structure file possesses model structural information (bond connectivity, etc.). The file can be named anything, but must end in .parm7, and cannot be a binary file. Note: this file also contains toppar information, so extra toppar files are not needed.
*  **swarm0000_subjob0000.rst7**: restart coordinates for your system. Use this name.
*  **input.mdin**: this input script defines the Amber22 simulation (i.e., how it is run); it **MUST** be named input.mdin. Here, the statistical ensemble is selected (e.g. NPT), temperature, and many, many other simulation parameters. The settings are commented well, so it should be clear. Be sure to consider temperature (temp0), coordinate temporal resolution (ntwx), and other physics related-settings.
*  **numberOfReplicas.txt**: this file contains to number of replicas to run for this system. MUST be a multiple of 8.

*  **Optional**: You can also include `swarm0000_subjob0000.mdinfo`, `swarm0000_subjob0000.mdout`, `swarm0000_subjob0000.nc`, but this is just for convenience (these specific files are not used in the running of this ensemble job).

  **Note:** make sure you have benchmarked each different system and have adjusted its individual `steps=` parameter accordingly. This workflow supports running an arbitrarily high number of systems (up to 9,999) with no restrictions on size differences. However, this functionality relies on adjusting each systems `nstlim=` to what can run in the job's time limit.

  **Note:** I recommend only requesting 80% of the number of steps that can be performed in the job time limit. This way, there is little risk of any of the systems running out of time, creating a mess to clean up.

  **VERY IMPORTANT:** `input.mdin` only contains ensemble-related information. All descriptions of input files are automatically understood by what is present in each subdirectory. Do NOT describe input files in this file, or the scripts will break.
 
  Finally, if you only have 1 system to run (with many replicas), just create 1 subdirectory in `inputs`.


2. **Build the swarm directory**  
   Use `setup_individual_swarm.sh` to scaffold `raw_swarms/swarm0000/` and its `traj####` subdirs from `inputs/`. (Edit its top few variables if needed.)

3. **Edit `launch_swarm.sh` (user config at top)**  
   - `mode` — `array` (recommended) or `alloc`
   - `swarm_number` — integer (e.g., 0)
   - `n_trajs_per_swarm` — number of trajectories
   - `n_jobs_per_traj` — subjobs chained per trajectory
   - `gpus_per_replica` — GPUs per trajectory
   - `trajectories_per_node` (alloc mode only) — packing factor per node
   - `account`, `partition`, `time_limit`, optional `array_max_parallel`, `extra_sbatch_flags`

4. **Launch**  
   ```bash
   ./launch_swarm.sh
   ```
   Watch the ID(s) and monitor with `squeue -u $USER`.

---

## Configuration — `launch_swarm.sh`

Most behavior is set in the **USER CONFIG** block at the top of `launch_swarm.sh`:

- `mode="array"| "alloc"`  
- `swarm_number=0`  
- `n_trajs_per_swarm=4`  
- `n_jobs_per_traj=2`  
- `gpus_per_replica=1`  
- `trajectories_per_node=8`  (alloc only; `nodes = ceil(trajs / trajectories_per_node)`)
- `account`, `partition`, `time_limit="HH:MM:SS"`  
- `gpus_per_node` (needed for array mode on some clusters to ensure full-node allocation)  
- `array_max_parallel=""` (e.g., `8` to throttle a big array)  
- `extra_sbatch_flags=( )` (add site-specific flags here)

> The **wall clock** for each submitted job is `time_limit` (see [Setting wall time](#setting-wall-time)).

`launch_swarm.sh` writes submission logs to `raw_swarms/submission_logs/` (one per sbatch call).

---

## Run modes

### Array mode

- Submits **one** sbatch with `--array=0-(N-1)%P` (if `array_max_parallel` is set).  
- Each array task runs **one trajectory**, and `submit_swarm_subjobs.sh` determines the next subjob index for that trajectory, then calls `run_amber.sh` under `srun`.

**Pros**: simplest scheduling; Slurm handles per-trajectory placement.  
**Note**: This is not an option for Frontier; use alloc mode instead. All other clusters currently supported (scu-login01, cayuga, delta-gpu) support array mode.


### Alloc mode

- Submits **one** sbatch per chained subjob, asking for a multi-node allocation sized by:
  ```text
  nodes = ceil(n_trajs_per_swarm / trajectories_per_node)
  tasks_per_node ≈ trajectories_per_node  (bounded by n_trajs_per_swarm)
  ```
- Inside the allocation, the script launches **one `srun` per trajectory** concurrently.

If sbatch returns `Requested node configuration is not available`, see [Troubleshooting](#troubleshooting).


---

## How chaining & restarts work

Within each trajectory directory (`raw_swarms/swarm####/swarm####_traj####/`), the runner:

1. **Detects the next subjob index** by scanning for the last `*subjob####*.mdinfo` file.  
   - If none exist yet, it initializes bookkeeping to start at **subjob 0000**.
2. **Restart guard**: if the previous attempt **did not end with** `FINISHED` on the last line of `amber_run.log`, it will:
   - decrement to the previous subjob index,
   - write a marker file `subjob_####_restarted`,
   - **safely move** any files from that subjob (see next section) to `./trash/`,
   - then re-run that subjob cleanly.
3. **Runs** the current subjob via `srun` calling `run_amber.sh`.  
   Amber standard out goes to `amber_log.txt` in the trajectory dir.


---

## Directory conventions & inputs

Each `swarm####_traj####/` directory is expected to contain at least:

- `*.parm7`
- `*.mdin` (your production or staged input)
- a restart/coordinate file whose name matches the subjob naming used by your workflow (e.g., `*subjob0000.rst7` for the very first run).

`run_amber.sh` names outputs with the convention that includes `_subjob####` in the basename, so the subsequent detection of `*.mdinfo` works automatically.


---

## Logs & outputs

- **Submission logs**: `raw_swarms/submission_logs/${jobname}_slurm-<jobid>.out`
- **Per-trajectory**: `amber_log.txt` (stdout of the current `run_amber.sh`), `*.mdout`, `*.mdinfo`, `*.rst7`, `*.nc`, etc.
- **Restart markers**: `subjob_####_restarted`
- **Bookkeeping**: `amber_run.log` (last line `FINISHED` indicates a clean end)

---

## Safe cleanup (trash) behavior

When a subjob needs to be re-run, the script **moves** all files for that subjob index with extensions in:

```
mdout, mdinfo, rst7, nc
```

…into a flat `./trash/` folder **inside the trajectory directory**. Subsequent moves **overwrite** any same-named files already in `trash`. Nothing is permanently deleted by this script. To reclaim space, **manually remove** files from `trash` when you’re ready. The use of a trash folder is to guard against unforseen edge cases (i.e., to prevent the scripts from actually deleting files when restarting bad subjobs).

---

## Setting wall time

Edit `time_limit="HH:MM:SS"` near the top of `launch_swarm.sh`. That value is passed directly to `sbatch -t` for every job launch (both array and alloc modes).

---

## Troubleshooting

### `sbatch: Requested node configuration is not available`
Your `-N`, `--ntasks(-per-node)`, `--gpus-per-node`, and partition constraints don’t match what that partition can deliver. Fixes:
- Try the **array mode** first — it’s the least restrictive.
- For **alloc mode**, ensure `trajectories_per_node × gpus_per_replica <= GPUs per node` on that partition, and that `nodes = ceil(n_trajs / trajectories_per_node)` is legal for the chosen partition/QOS.
- Some “interactive” partitions disallow multi-node or certain shapes. Use the standard batch GPU partition for queued work.

---

## FAQ

**Q: How do I throttle a giant job array?**  
Set `array_max_parallel=8` (or your limit). You’ll get `--array=0-(N-1)%8`.

**Q: How many nodes are requested in alloc mode?**  
`nodes = ceil(n_trajs_per_swarm / trajectories_per_node)`. Example: 20 trajectories with `trajectories_per_node=8` → 3 nodes.

**Q: Where do amber stdout/stderr go?**  
To `amber_log.txt` in each trajectory dir. Slurm submission output goes to `raw_swarms/submission_logs/`.

**Q: Which Amber engine is used?**  
Per-cluster in `run_amber.sh`: `pmemd.cuda` on NVIDIA sites; `pmemd.hip` on Frontier (ROCm).

---

### Attribution
Scripts by **Derek M. Shore, PhD**.
