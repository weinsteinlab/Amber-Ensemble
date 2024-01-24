#!/bin/bash -l
#
# Script name:   launch_swarm.sh
# Author:        Derek M. Shore, PhD
#
# This script launches a swarm of trajectories, with each trajectory consisting of 
# potentially many subjobs (to enable sampling that would not be possible within a 2-
# hour run limit).

# use: ./launch_swarm.sh

swarmNumber=0
numberOfTrajsPerSwarm=6
jobName="benchmarking" # no spaces
number_of_jobs=2

# do not edit below this line

firstIteration=0
numberOfNodes=`expr $numberOfTrajsPerSwarm / 6`
swarmNumber_padded=`printf %04d $swarmNumber`
fullJobName=${jobName}_swarm${swarmNumber_padded}

for (( this_job=0; this_job<$number_of_jobs; this_job++ ))
do
  if [ $firstIteration -eq 0 ]
  then
    jobSchedulerOutput="$(bsub -P BIP109 -W 2:00 -nnodes $numberOfNodes -J ./raw_swarms/submission_logs/${fullJobName} -alloc_flags "smt4" -alloc_flags gpumps ./submit_swarm_subjobs.sh $swarmNumber $numberOfTrajsPerSwarm)"
  else
    jobSchedulerOutput="$(bsub -P BIP109 -W 2:00 -nnodes $numberOfNodes -J ./raw_swarms/submission_logs/${fullJobName} -alloc_flags "smt4" -alloc_flags gpumps -w $job_scheduler_number ./submit_swarm_subjobs.sh $swarmNumber $numberOfTrajsPerSwarm)"
  fi

  job_scheduler_number=$(echo $jobSchedulerOutput | awk '{print $2}' | sed -e 's/<//' | sed -e 's/>//')
  let firstIteration=1
done 

exit

