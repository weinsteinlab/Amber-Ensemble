#!/bin/bash -l

# use: this script is used by ./launch_swarm.sh and is not
# meant to be run directly.

module load cuda/11.0.3
conda activate amber_2020

swarm_number=$1
number_of_trajs_per_swarm=$2

swarm_number_padded=`printf %04d $swarm_number`

CWD=`pwd`
swarm_path=$CWD/raw_swarms/swarm${swarm_number_padded}

numberOfFinishedRuns=$(find ./raw_swarms/. -name 'current_log.txt' -exec tail -n1 {} \; | grep FINISHED | wc -l)

subjob_number=0
isPriorRun=$(ls ${CWD}/raw_swarms/swarm${swarm_number_padded}/swarm${swarm_number_padded}_traj0000/*subjob*.mdout 2> /dev/null | tail -n1 | wc -l)

if [ $isPriorRun == 1 ]; then
    full_name=$(ls ${CWD}/raw_swarms/swarm${swarm_number_padded}/swarm${swarm_number_padded}_traj0000/*subjob*.mdout 2> /dev/null | tail -n1)
    padded_subjob_number=${full_name: -10:-6}
    subjob_number=$((10#$padded_subjob_number))
    ((subjob_number++))
fi 

if [ $subjob_number -gt 0 ] && [ $numberOfFinishedRuns != $number_of_trajs_per_swarm ]
then
  ((subjob_number--))
  touch ./subjob_${subjob_number}_FAILED
  bkill $LSB_JOBID
  exit 1
fi

last_subjob=$((subjob_number+1))

for ((i=$subjob_number; i<$last_subjob; i++))
do 
    rm -rf $CWD/progress/*
    number_of_jsruns=$((number_of_trajs_per_swarm/6))
    cd $swarm_path

    for ((traj_number=0; traj_number<$number_of_jsruns; traj_number++))
    do
        traj_number_padded=`printf %04d $traj_number`
        jsrun --progress $CWD/progress/subjob${i}_jsrun${traj_number_padded}_progress.txt --smpiargs="none" --rs_per_host 1 --nrs 1 --cpu_per_rs 42 --gpu_per_rs 6 --tasks_per_rs 1 ./node_submitter.sh $traj_number $i &
    done

    cd $CWD
    time_waited=0

    while true; do
        finished_jobs=`grep -sR 'finished' ./progress/* | wc -l`

        if [ $number_of_jsruns -eq $finished_jobs ]; then
            break
        fi

        sleep 15

        if [ $time_waited -gt 490 ]; then
            touch ./subjob_${i}_FAILED
            bkill $LSB_JOBID
            exit 1       
        fi 

        ((time_waited++))
    done

    numberOfFinishedRuns=$(find ./raw_swarms/. -name 'current_log.txt' -exec tail -n1 {} \; | grep FINISHED | wc -l)

    if [ $numberOfFinishedRuns != $number_of_trajs_per_swarm ]; then
        ((i--))
        touch ./subjob_${subjob_number}_FAILED
        bkill $LSB_JOBID
        exit 1
    fi

done 
