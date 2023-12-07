#!/bin/bash

# Function to get a list of storage pools
get_storage_pools() {
    pvesm status | awk 'NR>1 {print $1}'
}

# Function to allow the user to select a storage pool
select_storage_pool() {
    echo "Scanning for available storage pools..."
    readarray -t storage_pools <<< "$(get_storage_pools)"

    if [ ${#storage_pools[@]} -eq 0 ]; then
        echo "No storage pools found. Please ensure you have storage pools available."
        exit 1
    fi

    echo "Please select a storage pool for the VM images:"
    for i in "${!storage_pools[@]}"; do
        echo "$((i+1))) ${storage_pools[$i]}"
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

# Initialize VMs associative array
declare -A VMs=(
    [1001]=('https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2' 'debian11')
    [1002]=('https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2' 'debian12')
    [1003]=('https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img' 'ubuntu20')
    [1004]=('https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img' 'ubuntu22')
    [1005]=('https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2' 'almalinux8')
    [1006]=('https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2' 'almalinux9')
    [1007]=('https://download.rockylinux.org/pub/rocky/8/images/Rocky-8-GenericCloud.latest.x86_64.qcow2' 'rocky8')
    [1008]=('https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2' 'rocky9')
)

# Allow user to select a storage pool
select_storage_pool

# Ask the user if they want to download all distros or select one
echo "Do you want to download images for all distributions or select one?"
echo "1) Download all"
echo "2) Select from list"

read -p "Enter your choice (1 or 2): " download_choice

selected_vms=()

if [[ "$download_choice" -eq 1 ]]; then
    selected_vms=("${!VMs[@]}")
elif [[ "$download_choice" -eq 2 ]]; then
    echo "Select the distribution you want to download:"
    i=1
    for VMID in "${!VMs[@]}"; do
        echo "$i) VMID $VMID - ${VMs[$VMID][1]}"
        ((i++))
    done
    read -p "Enter number (1-${#VMs[@]}): " distro_num

    selected_vmids=("${!VMs[@]}")
    selected_vms=("${selected_vmids[$((distro_num-1))]}")
else
    echo "Invalid selection. Exiting."
    exit 1
fi

# Loop through the selected VMs array and set up each VM
for VMID in "${selected_vms[@]}"; do
    vm_info=("${VMs[$VMID]}")
    IMAGE_URL="${vm_info[0]}"
    OS_TYPE="${vm_info[1]}"
    FILENAME=$(basename "$IMAGE_URL")

    # Download the cloud image for each VM if it doesn't already exist
    if [ ! -f "/var/lib/vz/template/qemu/$FILENAME" ]; then
        echo "Downloading image for VM $VMID"
        wget -O "/var/lib/vz/template/qemu/$FILENAME" "$IMAGE_URL"
    else
        echo "Image $FILENAME for VM $VMID already exists, skipping download."
    fi

    # Create a new VM with the specified VMID, but do not start it
    echo "Creating VM $VMID"
    qm create $VMID --memory 2048 --net0 virtio,bridge=vmbr0 --cores 2 --name "vm$VMID-$OS_TYPE" --ostype l26

    # Import the downloaded disk to the VM using the specified storage pool
    echo "Importing disk to VM $VMID"
    qm importdisk $VMID "/var/lib/vz/template/qemu/$FILENAME" $STORAGE_POOL --format qcow2

    # Attach the imported disk to the VM as a scsi drive
    echo "Attaching disk to VM $VMID"
    qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:vm-$VMID-disk-0

    # Configure the CD-ROM to use the cloud-init image
    echo "Configuring cloud-init for VM $VMID"
    qm set $VMID --ide2 $STORAGE_POOL:cloudinit

    # Enable serial console and set boot order
    echo "Setting boot options for VM $VMID"
    qm set $VMID --serial0 socket --boot c --bootdisk scsi0

    # Set the VM to start on boot
    echo "Configuring VM $VMID to start on boot"
    qm set $VMID --onboot 1

    # Set the VM to use a tablet device, which is typical for cloud images
    echo "Configuring input device for VM $VMID"
    qm set $VMID --tablet 0

    echo "VM $VMID is now configured with image: $FILENAME"
done

echo "Configuration of all selected VMs is complete."
