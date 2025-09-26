#!/bin/bash -l
# submit_swarm_subjobs.sh
# Used by launch_swarm.sh; not intended to be run directly.

set -euo pipefail
shopt -s nullglob

CLEAN_EXTS=(mdout mdinfo rst7 nc)

# Args from launch_swarm.sh
swarm_number="$1"
number_of_trajs_per_swarm="$2"
number_of_gpus_per_replica="$3"
mode="$4"   # "alloc" or "array"

swarm_number_padded="$(printf %04d "$swarm_number")"
CWD="$(pwd)"
swarm_path="$CWD/raw_swarms/swarm${swarm_number_padded}"

safe_cleanup_for_subjob() {
  # Move files for a given subjob id (####) to ./trash (flat)
  local padded_id="$1"
  local matches=()

  for ext in "${CLEAN_EXTS[@]}"; do
    for f in *"subjob${padded_id}"*."$ext"; do
      [[ -e "$f" ]] && matches+=("$f")
    done
  done

  ((${#matches[@]}==0)) && return 0

  mkdir -p ./trash
  # Overwrite if same-named file already exists in trash
  mv -f -t ./trash -- "${matches[@]}"
  echo "[INFO] Moved ${#matches[@]} files to ./trash"
}

process_one_traj () {
  local traj_number="$1"
  local traj_number_padded
  traj_number_padded="$(printf %04d "$traj_number")"

  local traj_path="$swarm_path/swarm${swarm_number_padded}_traj${traj_number_padded}"
  cd "$traj_path"

  # Determine next subjob number based on latest *subjob####*.mdinfo
  local subjob_number=0
  local -a mdinfos=( *subjob*.mdinfo )
  if ((${#mdinfos[@]})); then
    local full_name="${mdinfos[-1]}"   # last lexicographically (#### is zero-padded)
    if [[ "$full_name" =~ subjob([0-9]{4})\.mdinfo$ ]]; then
      local padded_subjob_number="${BASH_REMATCH[1]}"
      subjob_number=$((10#$padded_subjob_number + 1))
    else
      echo "ERROR: couldn't parse subjob id from '$full_name'." >&2
      exit 3
    fi
  else
    echo "FINISHED" >> amber_run.log
  fi

  # If previous run didn't end with FINISHED, back up one and clean safely
  local numberOfFinishedRuns
  numberOfFinishedRuns=$(tail -n1 amber_run.log 2>/dev/null | grep -c "FINISHED" || true)
  if [ "$numberOfFinishedRuns" -ne 1 ]; then
    ((subjob_number--))
    if (( subjob_number < 0 )); then
      echo "ERROR: Computed negative subjob_number; aborting." >&2
      exit 1
    fi
    echo "job ${subjob_number}_restarted"
    touch "./subjob_${subjob_number}_restarted"
    local padded_old_subjob_number
    padded_old_subjob_number="$(printf %04d "$subjob_number")"
    safe_cleanup_for_subjob "$padded_old_subjob_number"
  fi

  # Launch this subjob (blocking)
  OMP_NUM_THREADS=1 srun -u --gres=gpu:"$number_of_gpus_per_replica" --gpu-bind=closest -N1 -n1 -c1 \
    ./run_amber.sh "$subjob_number" > ./amber_log.txt
}

if [[ "$mode" == "array" ]]; then
  # Assumed present in real array jobs (we're under 'set -u' so missing var would abort)
  process_one_traj "$SLURM_ARRAY_TASK_ID"
else
  # alloc mode: run all trajectories concurrently
  pids=()
  for (( traj_number=0; traj_number<number_of_trajs_per_swarm; traj_number++ )); do
    ( process_one_traj "$traj_number" ) & pids+=("$!")
    sleep 0.1
  done

  fail=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      fail=1
    fi
  done
  exit "$fail"
fi

exit 0
