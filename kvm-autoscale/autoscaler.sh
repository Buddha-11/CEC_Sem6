#!/bin/bash

BASE_IMAGE="/var/lib/libvirt/images/base-template.qcow2"
IMAGE_DIR="/var/lib/libvirt/images"

UPPER=70
LOWER=30
MAX_VMS=5
MIN_VMS=1

declare -a VM_LIST
VM_COUNTER=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

create_vm() {
    NAME="autoscale-$VM_COUNTER"

    sudo qemu-img create -f qcow2 \
    -b $BASE_IMAGE -F qcow2 \
    $IMAGE_DIR/$NAME.qcow2 > /dev/null

    virt-install \
    --name $NAME \
    --ram 256 \
    --vcpus 1 \
    --disk path=$IMAGE_DIR/$NAME.qcow2 \
    --import \
    --network network=default \
    --graphics none \
    --noautoconsole \
    --osinfo linux2022 > /dev/null 2>&1

    VM_LIST+=($NAME)
    ((VM_COUNTER++))
}

destroy_vm() {
    NAME=${VM_LIST[-1]}

    virsh destroy $NAME > /dev/null 2>&1
    virsh undefine $NAME > /dev/null 2>&1
    sudo rm -f $IMAGE_DIR/$NAME.qcow2

    unset VM_LIST[-1]
}

get_cpu_usage() {
    NAME=$1

    # Get number of vCPUs
    VCPUS=$(virsh vcpucount $NAME | awk '/current/ {print $3; exit}')
    if ! [[ "$VCPUS" =~ ^[0-9]+$ ]]; then
        VCPUS=1
    fi


    BEFORE=$(virsh domstats $NAME --cpu-total | awk -F= '/cpu.time/ {print $2}')
    T1=$(date +%s%N)

    sleep 1

    AFTER=$(virsh domstats $NAME --cpu-total | awk -F= '/cpu.time/ {print $2}')
    T2=$(date +%s%N)

    CPU_DELTA=$((AFTER - BEFORE))
    TIME_DELTA=$((T2 - T1))

    if [ "$TIME_DELTA" -eq 0 ]; then
        echo 0
        return
    fi

    CPU=$((100 * CPU_DELTA / TIME_DELTA / VCPUS))

    # Clamp values
    if [ $CPU -lt 0 ]; then
        CPU=0
    fi

    if [ $CPU -gt 100 ]; then
        CPU=100
    fi

    echo $CPU
}


# Create initial VM
create_vm

while true
do
    clear
    echo "================ AUTOSCALER DASHBOARD ================"
    echo ""

    COUNT=${#VM_LIST[@]}
    TOTAL=0

    printf "%-15s %-10s\n" "VM Name" "CPU Usage"
    echo "----------------------------------------"

    for VM in "${VM_LIST[@]}"
    do
        CPU=$(get_cpu_usage $VM)
        TOTAL=$((TOTAL + CPU))

        if [ $CPU -gt 70 ]; then
            COLOR=$RED
        elif [ $CPU -gt 30 ]; then
            COLOR=$YELLOW
        else
            COLOR=$GREEN
        fi

        printf "%-15s ${COLOR}%-10s${NC}\n" "$VM" "$CPU%"
    done

    if [ $COUNT -gt 0 ]; then
        AVG=$((TOTAL / COUNT))
    else
        AVG=0
    fi

    echo ""
    echo "Running VMs: $COUNT"
    echo "Average CPU: $AVG%"

    # Scaling Logic
    if [ $AVG -gt $UPPER ] && [ $COUNT -lt $MAX_VMS ]; then
        echo -e "${RED}Scaling Up...${NC}"
        create_vm
    elif [ $AVG -lt $LOWER ] && [ $COUNT -gt $MIN_VMS ]; then
        echo -e "${GREEN}Scaling Down...${NC}"
        destroy_vm
    else
        echo -e "${YELLOW}Stable${NC}"
    fi

    sleep 3
done
