#!/bin/bash -l

module load ums/default
module load ums002/default
module load openmpi/4.1.5
module load rocm/5.3.0

conda activate amber23

subjob_number=$1
echo "START" > amber_run.log
echo "subjob number: ${subjob_number}" >> amber_run.log

dir_name=$(basename `pwd`)

prior_job=$((subjob_number-1))
prior_subjob_padded=`printf %04d $prior_job`
subjob_padded=`printf %04d $subjob_number`

input_file=$(ls *.mdin)
parm_file=$(ls *.parm7)
input_coor=$(ls *subjob${prior_subjob_padded}.rst7)

output_name=${dir_name}"_subjob"${subjob_padded}

pmemd.hip -O -i $input_file -p $parm_file -c $input_coor -o ${output_name}.mdout -r ${output_name}.rst7 -inf ${output_name}.mdinfo -x ${output_name}.nc

echo "FINISHED" >> amber_run.log
exit 
