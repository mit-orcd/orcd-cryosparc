# CryoSPARC workflow for Engaging

<!-- 
TODO:
- Check if the time limit is set when you run jobs from the GUI or if it should be set in cluster_script.sh
- Tell users to just create the symlink if they've installed cryosparc already
-->

## Installation

You will need to obtain a CryoSPARC license ID [here](https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/obtaining-a-license-id). Licenses are free for academic use. Once you have received your licence ID, save it as an environment variable in your `.bash_profile`:

```bash
echo 'export CRYOSPARC_LICENSE_ID="your_license_id"' >> ~/.bash_profile
source ~/.bash_profile
```

CryoSPARC takes up ~16GB of storage once installed. By default, the installation script will install CryoSPARC to the same directory where the script lives. You can change this by setting the `CRYOSPARC_WORKDIR` environment variable:

```bash
echo 'export CRYOSPARC_WORKDIR="/path/to/cryosparc/workdir"' >> ~/.bash_profile
source ~/.bash_profile
```

*Note: On Engaging, a good place for this would be in `~/orcd/scratch`.*

You will need to run the installation on a compute node. To do this, request an interactive job:

```bash
salloc -N 1 -n 4 --mem-per-cpu=4G -p mit_normal
```

Next, run the installation script:

```bash
sh install.sh
```

The installation script will download and extract the `cryosparc_master` and `cryosparc_worker` software. You will be prompted to configure a few settings:

```
Are the above settings correct?
1) Yes
2) No
#? 
```
*Review everything looks OK, then enter `1`.*

```
Add bin directory to your ~/.bashrc ?
1) Yes
2) No
#? 
```
*Optional, but should not be needed given this setup.*

Then, you will be asked to enter your name and create a password. This is the password you will use when you sign in to the CryoSPARC portal:

```
Creating initial CryoSPARC user...
Username: secorey
Email: secorey@mit.edu
First name: Sam
Last name: Corey
Create a new password to use CryoSPARC: 
Confirm password: 
```

### Lane configuration

Finally, the script will ask you if you want to add additional partitions as lanes or select a different partition for the master software:

```
Enter any additional Slurm partitions to add as lanes (space-separated, leave blank for none):  
Available partitions for CryoSPARC master job: mit_normal
Which partition should be used for the CryoSPARC master job? [mit_normal]: 
```

**Lanes**

CryoSPARC lanes correspond directly to Slurm partitions. When you submit a job from the CryoSPARC GUI, it gets dispatched to whichever lane you select, which then submits a `sbatch` job to that partition using the lane's `cluster_script.sh`.

Three lanes are always created by default: `mit_normal`, `mit_normal_gpu`, and `mit_preemptable`. The GPU lane is where most CryoSPARC compute jobs should run. The install script also detects whether your account belongs to an AMF (Account Maintenance Fee) allocation group (`mit_amf_advanced_*` or `mit_amf_standard_*`). If you do, the appropriate `--account` and `--qos` directives are automatically injected into the lane's `cluster_script.sh` so your jobs get the correct priority and billing. For the GPU lane specifically, the time limit is also set based on your tier — 48 hours for advanced, 24 hours for standard, and 6 hours for no AMF account — since the cluster enforces different wall-time limits per allocation.

If you have access to another partition (e.g., for your lab or group), then feel free to add this as a lane as well.

**Master partition**

The CryoSPARC master process (the web server and database) runs as its own persistent Slurm job, separate from compute jobs. This is necessary because the master needs to stay alive the entire time you are working — it serves the GUI and tracks job state — while compute jobs come and go on whatever lane you choose.

The master only needs CPU resources, so the GPU partition is intentionally excluded from the list of choices. The default is `mit_normal`, but you can point it at any other CPU partition you have access to (e.g., a lab-specific partition with a longer wall-time limit), which is why you are prompted during installation.

The chosen partition is saved to `config.sh` so the `cryosparc` start script can reuse it on every launch. At startup, if the master is assigned to `mit_normal`, the start script also re-detects your AMF account membership and adds the corresponding `--account` and `--qos` flags to the `sbatch` call — the same logic as the lanes — so the master job gets the right priority without you having to configure it manually.
