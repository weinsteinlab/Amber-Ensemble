#!/bin/bash

traj_number=$1
subjob_Number=$2

cpu_ranges=(0-27 28-55 56-83 84-111 112-139 140-167)

for i in `seq 0 5`; do
    trajNumber=$(((traj_number*6)+i))

    traj_padded=`printf %04d $trajNumber`
    dirName="swarm0000_traj${traj_padded}"
    
    cd $dirName
    gpu_number=$i
    taskset -c ${cpu_ranges[i]} ./run_python.sh $subjob_Number $gpu_number & 
    cd .. 
done
