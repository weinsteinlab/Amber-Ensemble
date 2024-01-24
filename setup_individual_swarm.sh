#!/bin/bash
#
# Script name:   setup_individual_swarm.sh
# Author: Derek M. Shore, PhD
# 
# This script sets up the directory/file structure, for common files, 
# for an individual swarm. Here, a swarm is defined as a set of MD simulations
# that will have different starting structures after the first swarm is run.

# Use: ./setup_individual.sh 

swarm_number=0
number_of_trajs_per_swarm=6

# do not edit below this line

swarm_number_padded=`printf %04d $swarm_number`
CWD=`pwd`

swarm_path=$CWD/raw_swarms/swarm${swarm_number_padded}
mkdir -p $swarm_path
mkdir -p $CWD/raw_swarms/submission_logs
mkdir -p $CWD/progress

# we start with host_number 1 because 0 is the launch node
host_number=1

# starting with input directory '0000'
directoryNumber=0
directoryNumberPadded=`printf %04d $directoryNumber`
currentNumberOfReplicas=$(cat ./inputs/${directoryNumberPadded}/numberOfReplicas.txt)

cp ./node_submitter.sh $swarm_path/.

for (( traj_number=0; traj_number<$number_of_trajs_per_swarm; traj_number++ ))
do
  traj_number_padded=`printf %04d $traj_number`
  traj_path=$swarm_path/swarm${swarm_number_padded}_traj$traj_number_padded

  mkdir $traj_path
  cp ./common/run_python.sh $traj_path/.
  cp ./inputs/${directoryNumberPadded}/*.* $traj_path/.
  ((currentNumberOfReplicas--))

  if [ $currentNumberOfReplicas -eq 0 ] && [ $traj_number -lt $((number_of_trajs_per_swarm - 1)) ]  
  then
    ((directoryNumber++))
    directoryNumberPadded=`printf %04d $directoryNumber`
    currentNumberOfReplicas=$(cat inputs/${directoryNumberPadded}/numberOfReplicas.txt)
  fi
     
done

exit
