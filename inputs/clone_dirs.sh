#!/bin/bash 

for i in `seq 13 23`; do
    dirName=`printf %04d $i`
    echo $dirName
    cp -rp 0012 $dirName
done
