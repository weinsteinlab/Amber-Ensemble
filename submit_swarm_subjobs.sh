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
last_subjob="${5:-}"   # optional: stop once this subjob has finished

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

  # Determine this subjob's number. run_amber.sh records "subjob number: N"
  # in amber_run.log before starting pmemd and appends FINISHED on success,
  # so the log is the source of truth: FINISHED -> run N+1, otherwise N
  # failed (possibly before writing any output) -> clean N and rerun it.
  local subjob_number=0
  local log_subjob=""
  local restart=0
  if [[ -f amber_run.log ]]; then
    log_subjob=$(sed -n 's/^subjob number: \([0-9]\+\)$/\1/p' amber_run.log | tail -n1)
  fi

  if [[ -n "$log_subjob" ]]; then
    if [[ "$(tail -n1 amber_run.log)" == *FINISHED* ]]; then
      subjob_number=$((10#$log_subjob + 1))
    else
      subjob_number=$((10#$log_subjob))
      restart=1
    fi
  else
    # Fresh swarm (no subjob recorded yet): next after latest *subjob####*.mdinfo
    local -a mdinfos=( *subjob*.mdinfo )
    if ((${#mdinfos[@]})); then
      local full_name="${mdinfos[-1]}"   # last lexicographically (#### is zero-padded)
      if [[ "$full_name" =~ subjob([0-9]{4})\.mdinfo$ ]]; then
        subjob_number=$((10#${BASH_REMATCH[1]} + 1))
      else
        echo "ERROR: couldn't parse subjob id from '$full_name'." >&2
        exit 3
      fi
    fi
  fi

  if [[ -n "$last_subjob" ]] && (( subjob_number > last_subjob )); then
    echo "[INFO] $traj_path: subjob ${last_subjob} already finished; nothing to do."
    return 0
  fi

  # Never launch without the input restart from the previous subjob
  local -a prior_rst=( *"subjob$(printf %04d $((subjob_number - 1)))".rst7 )
  if (( subjob_number < 1 || ${#prior_rst[@]} != 1 )); then
    echo "ERROR: $traj_path: expected one restart file for subjob $((subjob_number - 1)); found ${#prior_rst[@]}. Aborting." >&2
    exit 1
  fi

  if (( restart )); then
    echo "job ${subjob_number}_restarted"
    touch "./subjob_${subjob_number}_restarted"
    safe_cleanup_for_subjob "$(printf %04d "$subjob_number")"
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
