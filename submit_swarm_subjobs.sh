#!/bin/bash -l

# use: this script is used by ./launch_swarm.sh and is not
# meant to be run directly.

swarm_number=$1
number_of_trajs_per_swarm=$2
number_of_gpus_per_replica=$3

# do not edit below this line

swarm_number_padded=`printf %04d $swarm_number`
CWD=`pwd`
swarm_path=$CWD/raw_swarms/swarm${swarm_number_padded}

for ((traj_number=0; traj_number<$number_of_trajs_per_swarm; traj_number++)); do
    traj_number_padded=`printf %04d $traj_number`
    traj_path=$swarm_path/swarm${swarm_number_padded}_traj$traj_number_padded

    cd $traj_path 

    subjob_number=0
    isPriorRun=$(ls *subjob*.mdinfo 2> /dev/null | tail -n1 | wc -l)

    if [ $isPriorRun -eq 1 ]; then
        full_name=$(ls *subjob*.mdinfo 2> /dev/null | tail -n1)
        padded_subjob_number=${full_name: -11:-7}
        subjob_number=$((10#$padded_subjob_number))
        ((subjob_number++))
    else
        echo "FINISHED" >> amber_run.log
    fi

    numberOfFinishedRuns=$(find . -name 'amber_run.log' -exec tail -n1 {} \; | grep FINISHED | wc -l)

    if [ $numberOfFinishedRuns -ne 1 ]; then
        ((subjob_number--))
        pwd
        echo "job ${subjob_number}_restarted"
        touch ./subjob_${subjob_number}_restarted

        padded_old_subjob_number=`printf %04d $subjob_number`
        find . -name "*subjob${padded_old_subjob_number}*" -exec rm {} \;
    fi

    OMP_NUM_THREADS=1 srun -u --gpus-per-task=$number_of_gpus_per_replica --gpu-bind=closest -N1 -n1 -c1 ./run_amber.sh $subjob_number > ./amber_log.txt &

    sleep 0.1
done

wait

exit 
