#!/bin/bash

# Function to get a list of storage pools
get_storage_pools() {
    pvesm status | awk 'NR>1 {print $1}'
}

# Function to allow the user to select a storage pool
select_storage_pool() {
    echo "Scanning for available storage pools..."
    readarray -t storage_pools < <(get_storage_pools)

    if [ "${#storage_pools[@]}" -eq 0 ]; then
        echo "No storage pools found. Please ensure you have storage pools available."
        exit 1
    fi

    echo "Please select a storage pool for the VM images:"
    for i in "${!storage_pools[@]}"; do
        echo "$((i+1))) ${storage_pools[i]}"
    done

    while :; do
        read -rp "Enter number (1-${#storage_pools[@]}): " pool_num
        if [[ "$pool_num" -ge 1 ]] && [[ "$pool_num" -le ${#storage_pools[@]} ]]; then
            STORAGE_POOL="${storage_pools[$((pool_num-1))]}"
            echo "Selected storage pool: $STORAGE_POOL"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Declare associative array with VM information.
declare -A VMs=(
    [1001]='https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2 debian11'
    [1002]='https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 debian12'
    [1003]='https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img ubuntu20'
    [1004]='https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img ubuntu22'
    [1005]='https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2 almalinux8'
    [1006]='https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 almalinux9'
    [1007]='https://download.rockylinux.org/pub/rocky/8/images/Rocky-8-GenericCloud.latest.x86_64.qcow2 rocky8'
    [1008]='https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2 rocky9'
)

# Allow user to select a storage pool
select_storage_pool

# Allow user to select whether to download all distro images or just one
echo "Do you want to download images for all distributions or select one?"
echo "1) Download all"
echo "2) Select from list"

read -p "Enter your choice (1 or 2): " download_choice

if [[ "$download_choice" -eq 1 ]]; then
    selected_vmids=("${!VMs[@]}")
elif [[ "$download_choice" -eq 2 ]]; then
    echo "Select the distribution you want to download:"
    select vmid in "${!VMs[@]}"; do
        if [[ -n "$vmid" ]]; then
            selected_vmids=("$vmid")
            break
        else
            echo "Invalid selection."
        fi
    done
else
    echo "Invalid selection. Exiting."
    exit 1
fi

# Perform downloading and setup of VMs
for VMID in "${selected_vmids[@]}"; do
    IFS=' ' read -r IMAGE_URL OS_TYPE <<< "${VMs[$VMID]}"
    FILENAME=$(basename "$IMAGE_URL")

    # Download the cloud image for each VM if it doesn't already exist
    if [ ! -f "/var/lib/vz/template/qemu/$FILENAME" ]; then
        wget -O "/var/lib/vz/template/qemu/$FILENAME" "$IMAGE_URL"
    else
        echo "Image $FILENAME for VM $VMID already exists, skipping download."
    fi

    # Additional VM setup commands like 'qm create', 'qm importdisk', etc. go here
    # Please replace the following comment with your actual VM setup commands
    # ...
done

echo "All selected VMs have been processed."
