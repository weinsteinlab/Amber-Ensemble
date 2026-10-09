#!/bin/bash
#
# Script name:   launch_swarm.sh
# Author:        Derek M. Shore, PhD
# Purpose:       Submit AmberMD swarms in either 'alloc' or 'array' mode.
# Usage:         Edit the USER CONFIG below; then run: ./launch_swarm.sh
#                Note: this is NOT sbatch launch_swarm.sh !

set -euo pipefail

# =====================
# ===== USER CONFIG ===
# =====================
mode="array"                   # 'alloc' or 'array'
swarm_number=0                 # integer swarm ID
n_trajs_per_swarm=100          # trajectories/replicas
n_jobs_per_traj=10             # chained subjobs per trajectory
last_subjob=19                 # trajectories stop after this subjob (empty = no cap)
gpus_per_replica=1             # GPUs per subjob
job_name_base="fs"             # static prefix for job names

# Node sizing
trajectories_per_node=4        # alloc mode: nodes = ceil(n_trajs_per_swarm / trajectories_per_node)

delta_account="bbqz-delta-gpu" # Delta only (ignored elsewhere): your allocation, generally
                               # XXXX-delta-gpu, where XXXX is your group name (e.g., bbft-delta-gpu)

# Cluster-specific settings (auto-detected; names match common/run_amber.sh)
cluster="$(scontrol show config | awk '/^ClusterName/ {print $3}')"
case "$cluster" in
  delta)
    account="$delta_account"
    partition="gpuA40x4"
    ;;
  scu)
    account=""                 # use your default account
    partition="hwlab-rocky-gpu,hw-gpu-r9,scu-gpu,cryo-gpu-low,cryo-gpu-v100-low,cryo-gpu-p100-low"
    ;;
  *)
    echo "ERROR: launch_swarm.sh has no settings for cluster '$cluster' (supported: delta, scu)." >&2
    exit 2
    ;;
esac

gpus_per_node=4                # only used for alloc jobs
                               # delta: 4
                               # frontier: 8

time_limit="08:00:00"          # hh:mm:ss

email=""                       # optional
array_max_parallel=""          # e.g., 8 to throttle array concurrency; empty = unlimited
extra_sbatch_flags=( "--mem=8G" )  # e.g., ("--qos=normal" "--constraint=a100" "--mem=16G" "-c" "4")
# =====================
# == END USER CONFIG ==
# =====================

# Build sbatch flags
sbatch_flags=()
[[ -n "$account"    ]] && sbatch_flags+=( -A "$account" )
[[ -n "$partition"  ]] && sbatch_flags+=( -p "$partition" )
[[ -n "$time_limit" ]] && sbatch_flags+=( -t "$time_limit" )
[[ -n "$email"      ]] && sbatch_flags+=( --mail-user="$email" --mail-type=FAIL )
if [[ ${#extra_sbatch_flags[@]} -gt 0 ]]; then
  sbatch_flags+=( "${extra_sbatch_flags[@]}" )
fi

# Validate
if [[ "$mode" != "alloc" && "$mode" != "array" ]]; then
  echo "ERROR: mode must be 'alloc' or 'array' (got '$mode')." >&2
  exit 2
fi

swarm_padded=$(printf "%04d" "$swarm_number")
log_dir="./raw_swarms/submission_logs"
mkdir -p "$log_dir"

# ---------- Alloc-mode layout ----------
# Determine how many GPU-backed tasks we can run per node and how many nodes we need.
max_tpn_by_gpu=$(( gpus_per_node / gpus_per_replica ))
tasks_per_node=$(( trajectories_per_node < max_tpn_by_gpu ? trajectories_per_node : max_tpn_by_gpu ))
if (( tasks_per_node < 1 )); then
  echo "ERROR: gpus_per_node (${gpus_per_node}) < gpus_per_replica (${gpus_per_replica})." >&2
  exit 2
fi
nodes_alloc=$(( (n_trajs_per_swarm + tasks_per_node - 1) / tasks_per_node ))

echo "[CONFIG] mode=$mode | swarm=$swarm_number | trajs=$n_trajs_per_swarm | jobs/traj=$n_jobs_per_traj | gpus/replica=$gpus_per_replica"
echo "[CONFIG] alloc layout: nodes=${nodes_alloc}, tasks/node=${tasks_per_node}, gpus/node=$((tasks_per_node * gpus_per_replica))"
echo "[CONFIG] sbatch flags: ${sbatch_flags[*]}"

prev_job_id=""
for (( subjob=0; subjob<n_jobs_per_traj; subjob++ )); do
  subjob_padded=$(printf "%04d" "$subjob")
  full_job_name="${job_name_base}${swarm_padded}_subjob${subjob_padded}"

  if [[ "$mode" == "alloc" ]]; then
    out_pattern="${log_dir}/${full_job_name}_slurm-%A.out"
    # Reserve enough GPUs per node for 'tasks_per_node' replicas, and run one task per replica.
    new_job_id=$(sbatch --parsable "${sbatch_flags[@]}" \
                   ${prev_job_id:+--dependency=afterok:${prev_job_id}} \
                   --job-name="$full_job_name" \
                   -N "$nodes_alloc" \
                   --ntasks-per-node="$tasks_per_node" \
                   --gres=gpu:$(( tasks_per_node * gpus_per_replica )) \
                   --cpus-per-task=1 \
                   --distribution=block:block \
                   --output="$out_pattern" \
                   ./submit_swarm_subjobs.sh "$swarm_number" "$n_trajs_per_swarm" "$gpus_per_replica" "alloc" "$last_subjob")
    echo "[INFO] Submitted ${full_job_name} as job ${new_job_id}${prev_job_id:+ (depends on $prev_job_id via afterok)}"
  else
    out_pattern="${log_dir}/${full_job_name}_slurm-%A_%a.out"
    array_range="0-$((n_trajs_per_swarm-1))"
    pct=""
    if [[ -n "$array_max_parallel" ]]; then
      pct="%${array_max_parallel}"
    fi

    new_job_id=$(sbatch --parsable "${sbatch_flags[@]}" \
                   ${prev_job_id:+--dependency=afterok:${prev_job_id}} \
                   --array=${array_range}${pct} \
                   --ntasks=1 \
                   --gres=gpu:${gpus_per_replica} \
                   --job-name="$full_job_name" \
                   --output="$out_pattern" \
                   ./submit_swarm_subjobs.sh "$swarm_number" "$n_trajs_per_swarm" "$gpus_per_replica" "array" "$last_subjob")
    echo "[INFO] Submitted ${full_job_name} with array ${array_range}${pct} as job ${new_job_id}${prev_job_id:+ (depends on $prev_job_id via afterok)}"
  fi

  prev_job_id="$new_job_id"
done

exit 0
