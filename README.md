# Table of contents:
- [Setup Environment](#setup-enviornment)
- [Pre-workflow setup](#pre-workflow-setup)
- [Amber Ensemble Workflow](#amber-ensemble-workflow)
  * [Step 1: Generate swarm directory structure](#step-1-generate-swarm-directory-structure)
  * [Step 2: Launching a swarm](#step-2-launching-a-swarm)
<!-- toc -->
---
# Setup Environment

This molecular dynamics (MD) ensemble workflow has several software dependencies: 

*  Amber22, 
*  VMD,

This software is already installed for the Weinstein lab. In this section, we describe how to setup your environment to use these installations.

Add the following to your `~.bashrc` (this should replace any currently present conda code blocks) 

```
if [[ "$(hostname -s)" == *"andes"* ]] ; then
    source /ccs/proj/bip109/rhea/gromacs/gromacs-2023.1_install/bin/GMXRC.bash
fi

if [[ "$(hostname -s)" == *"rhea"* ]] || [[ "$(hostname -s)" == *"andes"* ]] ; then
    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    __conda_setup="$('/ccs/proj/bip109/rhea/anaconda_2020_07/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "/ccs/proj/bip109/rhea/anaconda_2020_07/etc/profile.d/conda.sh" ]; then
            . "/ccs/proj/bip109/rhea/anaconda_2020_07/etc/profile.d/conda.sh"  # commented out by conda initialize
        else
            export PATH="/ccs/proj/bip109/rhea/anaconda_2020_07/bin:$PATH"
        fi
    fi
    unset __conda_setup
    # <<< conda initialize <<<
elif [[ "$(hostname -f)" == *"frontier"* ]]; then
    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    source /ccs/proj/bip109/frontier/amber22/amber22_src/dist/amber.sh
    __conda_setup="$('/ccs/proj/bip109/frontier/conda/miniconda3_py310_23.3.1-0_2023_05_10/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "/ccs/proj/bip109/frontier/conda/miniconda3_py310_23.3.1-0_2023_05_10/etc/profile.d/conda.sh" ]; then
            . "/ccs/proj/bip109/frontier/conda/miniconda3_py310_23.3.1-0_2023_05_10/etc/profile.d/conda.sh"  # commented out by conda initialize
        else
            export PATH="/ccs/proj/bip109/frontier/conda/miniconda3_py310_23.3.1-0_2023_05_10/bin:$PATH"  # commented out by conda initialize
        fi
    fi
    unset __conda_setup
    # <<< conda initialize <<<
else
    source /ccs/proj/bip109/summit/amber/amber20/amber.sh
    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    __conda_setup="$('/ccs/proj/bip109/summit/anaconda/anaconda_2021_05/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "/ccs/proj/bip109/summit/anaconda/anaconda_2021_05/etc/profile.d/conda.sh" ]; then
            . "/ccs/proj/bip109/summit/anaconda/anaconda_2021_05/etc/profile.d/conda.sh"   # commented out by conda initialize
        else
            export PATH="/ccs/proj/bip109/summit/anaconda/anaconda_2021_05/bin:$PATH"
        fi
    fi
    unset __conda_setup
    # <<< conda initialize <<<
fi
```


That's it--if everything went correctly, all dependencies needed for this workflow should now be available!

# Pre-workflow setup

**Note:** you can skip the pre-workflow setup if you are just running the test system found in this repository.

The first step in using these tools is to first clone a copy of this repository, in a directory that is appropriate for running swarms of MD simulations ('swarm' is defined in the [this section](#step-1-initial-structures)).
```
cd wherever_you_wish_to_run
git clone git@github.com:weinsteinlab/Amber-Frontier-Ensemble.git
```

Optionally, you can rename the cloned repository to something meaningful for your calculations
```
mv Amber-Frontier-Ensemble my_Amber_ensemble
```
Once this is done, go into this directory:
```
cd my_Amber_ensemble # or whatever the directory is named at this point
```

**Note: directory is hereafter referred to as the parent directory**


Next, you'll need to populate/edit files in the directory `./inputs`

**Note:** You'll see there is another directory called `./common`: do **NOT** edit anything in this directory! It contains a script that facilitate job management and should not be edited by the user.

`./inputs` should contain a separate subdirectory for each unique system you wish to run. These subdirectories MUST have 4-zero-padded, zero-indexed names (e.g., `0000`, `0001`, `0002`, etc.). Deviating from this nomenclature WILL break the scripts.

**Note:** This workflow assumes you are RESTARTING Amber simulations (i.e., you have already built/equilibrated the system with CHARMM-GUI).

Each subdirectory must contain all of the simulation system-specific files needed to simulate your system with Amber 22:
*  **parm.parm7**: this protein structure file possesses model structural information (bond connectivity, etc.). The file can be named anything, but must end in .parm7, and cannot be a binary file. Note: this file also contains toppar information, so extra toppar files are not needed.
*  **swarm0000_subjob0000.rst7**: restart coordinates for your system. Use this name.
*  **input.mdin**: this input script defines the Amber22 simulation (i.e., how it is run); it **MUST** be named input.mdin. Here, the statistical ensemble is selected (e.g. NPT), temperature, and many, many other simulation parameters. The settings are commented well, so it should be clear. Be sure to consider temperature (temp0), coordinate temporal resolution (ntwx), and other physics related-settings.
*  **numberOfReplicas.txt**: this file contains to number of replicas to run for this system. MUST be a multiple of 8.

*  **Optional**: You can also include `swarm0000_subjob0000.mdinfo`, `swarm0000_subjob0000.mdout`, `swarm0000_subjob0000.nc`, but this is just for convenience (these specific files are not used in the running of this ensemble job).

**Note:** make sure you have benchmarked each different system and have adjusted its individual `steps=` parameter accordingly. This workflow supports running an arbitrarily high number of systems (up to 9,999) with no restrictions on size differences. However, this functionality relies on adjusting each systems `nstlim=` to what can run in 2 hours. 

**Note:** Until experienced with Frontier's performance for a given set of systems, I recommend only requesting 80% of the number of steps that can be performed in 2 hours. This way, there is little risk of any of the systems running out of time, creating a mess to clean up.

**VERY IMPORTANT:** `input.mdin` only contains ensemble-related information. All descriptions of input files are automatically understood by what is present in each subdirectory. Do NOT describe input files in this file, or the scripts will break.

Finally, if you only have 1 system to run (with many replicas), just create 1 subdirectory in `inputs`.


# Amber Ensemble Workflow
---
### Step 1: Generate swarm directory structure
After populating `./inputs` your  step is to generate the directory structure for a given swarm, and all of the subdirectories for the independent trajectories that make up this swarm. 
Open ```setup_individual_swarm.sh``` in vim, and edit the following variables:

```
swarm_number=0
number_of_trajs_per_swarm=8
```

`swarm_number=0` is the swarm number you wish to run; it is zero indexed.
`number_of_trajs_per_swarm=8` is the number of MD trajectories per MD swarm. MUST be a multiple of 8

After editing this file, generate the initial structures directory with the following command:
```
./setup_individual_swarm.sh
```

**Note:** this step is so lightweight that it is currently just run on the login node (i.e. not submitted to the job queue).

This will create the directory `raw_swarms` in your repository's parent directory. In `./raw_swarms`, you'll see the directory `swarm[0-9][0-9][0-9][0-9]`, with the specific number depending on what you set `swarm_number` equal to.

Inside of `swarm[0-9][0-9][0-9][0-9]`, you'll find:
*  swarm0000_traj0000/
*  swarm0000_traj0001/
*  ...
*  swarm0000_traj[n] # where n is `number_of_trajs_per_swarm` zero padded to a width of 4.

These directories will hold all of the files related to running a given swarm's trajectory. 

---

### Step 2: Launching a swarm

To run all of the trajectories that make up the MD swarm, open `launch_swarm.sh` in vim, and edit the following variables:

```
swarmNumber=0
numberOfTrajsPerSwarm=8
number_of_jobs=1 # how many 2-hour jobs you want to run
jobName="your_job_name" # no spaces

partitionName="batch"            #Slurm partition to run job on
accountName="bip109"
```

The first 2 variables have already been described and must be consistent with whatever was set in `setup_individual_swarm.sh`.

The next 2 variables have to deal with trajectory subjobs. Because Frontier has a maximum job runtime of 2 hours, a single trajectory must be run over many subjobs to achieve the needed desired simulation time. The number of subjobs should equal: (total_simulation_time / simulation_time_per_2_hours). 

`jobName`: what you wish to name the job (this will be publically visible in the job scheduler)

Finally, submit the MD swarm to the job scheduler with the following command:

```
./launch_swarm.sh
```

The status of the MD swarm can be checked with the following command:

`squeue -u $USER`


