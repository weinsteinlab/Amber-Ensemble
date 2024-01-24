#!/bin/bash -l

subjob_number=$1
gpu_number=$2

export CUDA_VISIBLE_DEVICES=${gpu_number}
echo "START" > current_log.txt

dir_name=$(basename `pwd`)

prior_job=$((subjob_number-1))
prior_subjob_padded=`printf %04d $prior_job`
subjob_padded=`printf %04d $subjob_number`

input_file=$(ls *.mdin)
parm_file=$(ls *.parm7)
input_coor=$(ls *subjob${prior_subjob_padded}.rst7)

output_name=${dir_name}"_subjob"${subjob_padded}

pmemd.cuda -O -i $input_file -p $parm_file -c $input_coor -o ${output_name}.mdout -r ${output_name}.rst7 -inf ${output_name}.mdinfo -x ${output_name}.nc

echo "FINISHED" >> current_log.txt
exit 
