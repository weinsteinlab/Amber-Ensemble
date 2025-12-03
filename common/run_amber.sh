#!/bin/bash -l
set -euo pipefail

# Cluster-aware module loads (no GPU/partition detection).
# You can still override the engine explicitly with:
#   export PMEMD_BIN=/full/path/to/pmemd.{cuda,hip,MPI}
cluster="${SLURM_CLUSTER_NAME:-unknown}"
PMEMD_BIN="${PMEMD_BIN:-}"

case "$cluster" in
  scu)
    # SCU
    source /software/apps/amber/amber24/pmemd24/amber.sh
    module load cuda/12.2.1-gcc-8.2.0-23runmx
    module load openmpi/4.1.5
    PMEMD_BIN="${PMEMD_BIN:-pmemd.cuda}"
    ;;
  cayuga)
    # Cayuga
    module load amber/24
    PMEMD_BIN="${PMEMD_BIN:-pmemd.cuda}"
    ;;
  delta)
    # Delta (current stack)
    source /work/hdd/bbqz/des2037/software/pmemd24/amber.sh
    #module load openmpi+cuda/4.1.5+cuda
    PMEMD_BIN="${PMEMD_BIN:-pmemd.cuda}"
    ;;
  frontier)
    # Frontier
    source /ccs/proj/bip109/frontier/amber22_gcc11.2/amber22_src/dist/amber.sh
    module load ums/default
    module load ums002/default
    module load openmpi/4.1.5
    module load rocm/5.3.0
    PMEMD_BIN="${PMEMD_BIN:-pmemd.hip}"
    ;;
  *)
    echo "ERROR: Unsupported cluster '$cluster'. Supported: scu, cayuga, delta, frontier." >&2
    exit 2
    ;;
esac

# --------------------- Original run logic ---------------------
subjob_number="$1"
echo "START" > amber_run.log
echo "subjob number: ${subjob_number}" >> amber_run.log

dir_name="$(basename "$(pwd)")"

prior_job=$((subjob_number-1))
prior_subjob_padded="$(printf %04d "$prior_job")"
subjob_padded="$(printf %04d "$subjob_number")"

input_file=$(ls *.mdin)
parm_file=$(ls *.parm7)
input_coor=$(ls *subjob${prior_subjob_padded}.rst7)

output_name="${dir_name}_subjob${subjob_padded}"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

"$PMEMD_BIN" -O \
  -i "$input_file" \
  -p "$parm_file" \
  -c "$input_coor" \
  -o "${output_name}.mdout" \
  -r "${output_name}.rst7" \
  -inf "${output_name}.mdinfo" \
  -x "${output_name}.nc"

echo "FINISHED" >> amber_run.log
exit
