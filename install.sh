#!/bin/bash

module load miniforge

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect Slurm account membership and set ADVANCED_ACCOUNT:
SLURM_ACCOUNTS=$(sacctmgr -n -P show user $USER withassoc format=Account 2>/dev/null)
if echo "$SLURM_ACCOUNTS" | grep -qx "mit_amf_advanced_cpu"; then
    ADVANCED_ACCOUNT="advanced"
elif echo "$SLURM_ACCOUNTS" | grep -qx "mit_amf_standard_cpu"; then
    ADVANCED_ACCOUNT="standard"
else
    ADVANCED_ACCOUNT=""
fi

# Check if CRYOSPARC_LICENSE_ID is set:
if [ -z "$CRYOSPARC_LICENSE_ID" ]; then
    echo "Error: CRYOSPARC_LICENSE_ID environment variable is not set. Please set it to your CryoSPARC license ID and try again."
    exit 1
fi

# Check if CRYOSPARC_WORKDIR is set. If not, default to this script's directory:
if [ -z "$CRYOSPARC_WORKDIR" ]; then
    CRYOSPARC_WORKDIR="$SCRIPT_DIR"
    echo "CRYOSPARC_WORKDIR is not set. Defaulting to script directory: $CRYOSPARC_WORKDIR"
else
    echo "Using CRYOSPARC_WORKDIR: $CRYOSPARC_WORKDIR"
fi

# Download CryoSPARC software:
cd "$CRYOSPARC_WORKDIR"
echo "Downloading CryoSPARC master software..."
curl -L https://get.cryosparc.com/download/master-latest/$CRYOSPARC_LICENSE_ID -o cryosparc_master.tar.gz
echo "Extracting CryoSPARC master software..."
tar -xf cryosparc_master.tar.gz cryosparc_master
rm cryosparc_master.tar.gz
echo "Downloading CryoSPARC worker software..."
curl -L https://get.cryosparc.com/download/worker-latest/$CRYOSPARC_LICENSE_ID -o cryosparc_worker.tar.gz
echo "Extracting CryoSPARC worker software..."
tar -xf cryosparc_worker.tar.gz cryosparc_worker
rm cryosparc_worker.tar.gz

# Install CryoSPARC master:
cd cryosparc_master
echo "Installing CryoSPARC master..."
DB_PATH=$CRYOSPARC_WORKDIR/cryosparc_database
PORT=$(python -c '
import socket, random
for p in random.sample(range(10000, 32757), 500):
    try:
        s = socket.socket()
        s.bind(("", p))
        s.close()
        print(p)
        break
    except OSError:
        pass
')
echo "Port: $PORT"
./install.sh --license $CRYOSPARC_LICENSE_ID \
             --hostname $(hostname) \
             --dbpath $DB_PATH \
             --port $PORT

# Start CryoSPARC master:
# Add cryosparc_master to path:
export PATH=$CRYOSPARC_WORKDIR/cryosparc_master/bin:$PATH
# Ensure that CryoSPARC recognizes the master node you are using:
echo 'export CRYOSPARC_FORCE_HOSTNAME=true' >> "$CRYOSPARC_WORKDIR/cryosparc_master/config.sh"
# Start cryosparc:
cryosparcm start

# Create initial user:
echo "Creating initial CryoSPARC user..."
echo "Username: $USER"
echo "Email: ${USER}@mit.edu"
# Have the user enter their password and name:
read -p "First name: " FIRST_NAME
read -p "Last name: " LAST_NAME
while true; do
    read -s -p "Create a new password to use CryoSPARC: " PASSWORD
    echo
    read -s -p "Confirm password: " PASSWORD_CONFIRM
    echo
    if [ "$PASSWORD" = "$PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done
# Create the user in CryoSPARC:
cryosparcm user create --email "${USER}@mit.edu" \
                       --password "$PASSWORD" \
                       --username $USER \
                       --firstname "$FIRST_NAME" \
                       --lastname "$LAST_NAME"

# Helper to set up a single lane directory:
setup_lane() {
    local lane="$1"
    local lane_dir="$CRYOSPARC_WORKDIR/cryosparc_master/lanes/$lane"
    mkdir -p $lane_dir
    cp "$SCRIPT_DIR/templates/cluster_script.sh" "$lane_dir/cluster_script.sh"
    cp "$SCRIPT_DIR/templates/cluster_info.json" "$lane_dir/cluster_info.json"
    sed -i "s/#SBATCH -p .*/#SBATCH -p $lane/" "$lane_dir/cluster_script.sh"
    sed -i "s|\"name\": \"\"|\"name\": \"$lane\"|" "$lane_dir/cluster_info.json"
    sed -i "s|\"worker_bin_path\": \"\"|\"worker_bin_path\": \"$CRYOSPARC_WORKDIR/cryosparc_worker/bin/cryosparcw\"|" "$lane_dir/cluster_info.json"
    if [ -n "$ADVANCED_ACCOUNT" ]; then
        if [ "$lane" = "mit_normal" ]; then
            ACCT="mit_amf_${ADVANCED_ACCOUNT}_cpu"
            sed -i "/#SBATCH -p $lane/a #SBATCH --qos=$ACCT\n#SBATCH --account=$ACCT" "$lane_dir/cluster_script.sh"
        elif [ "$lane" = "mit_normal_gpu" ]; then
            ACCT="mit_amf_${ADVANCED_ACCOUNT}_gpu"
            sed -i "/#SBATCH -p $lane/a #SBATCH --qos=$ACCT\n#SBATCH --account=$ACCT" "$lane_dir/cluster_script.sh"
        fi
    fi
    if [ "$lane" = "mit_normal_gpu" ]; then
        if [ "$ADVANCED_ACCOUNT" = "advanced" ]; then
            GPU_TIME="48:00:00"
        elif [ "$ADVANCED_ACCOUNT" = "standard" ]; then
            GPU_TIME="24:00:00"
        else
            GPU_TIME="6:00:00"
        fi
        sed -i "/#SBATCH -p $lane/a #SBATCH --time=$GPU_TIME" "$lane_dir/cluster_script.sh"
    fi
    cd "$lane_dir"
    cryosparcm cluster connect
    cd ../..
}

# Set up default lanes:
mkdir -p $CRYOSPARC_WORKDIR/cryosparc_master/lanes
lanes=("mit_normal" "mit_normal_gpu" "mit_preemptable")
for lane in "${lanes[@]}"; do
    setup_lane "$lane"
done

# Prompt for additional partitions:
read -p "Enter any additional Slurm partitions to add as lanes (space-separated, leave blank for none): " EXTRA_PARTITIONS_INPUT
EXTRA_PARTITIONS=()
if [ -n "$EXTRA_PARTITIONS_INPUT" ]; then
    read -ra EXTRA_PARTITIONS <<< "$EXTRA_PARTITIONS_INPUT"
    for lane in "${EXTRA_PARTITIONS[@]}"; do
        setup_lane "$lane"
    done
fi

# Prompt for which partition to use for the CryoSPARC master job:
ALL_PARTITIONS=("mit_normal" "${EXTRA_PARTITIONS[@]}")
echo "Available partitions for CryoSPARC master job: ${ALL_PARTITIONS[*]}"
read -p "Which partition should be used for the CryoSPARC master job? [mit_normal]: " MASTER_PARTITION
MASTER_PARTITION="${MASTER_PARTITION:-mit_normal}"
echo "export CRYOSPARC_MASTER_PARTITION=\"$MASTER_PARTITION\"" >> "$CRYOSPARC_WORKDIR/cryosparc_master/config.sh"

# Install CryoSPARC worker:
cd $CRYOSPARC_WORKDIR/cryosparc_worker
echo "Installing CryoSPARC worker..."
./install.sh --license $CRYOSPARC_LICENSE_ID

cryosparcm stop

# Symlink cryosparc script to desktop:
echo "Creating symlink to cryosparc script on desktop..."
ln -sf "$SCRIPT_DIR/cryosparc" ~/Desktop/cryosparc

echo "Installation complete."
