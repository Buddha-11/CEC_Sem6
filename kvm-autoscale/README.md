# Hypervisor-Level VM Autoscaler using KVM + QEMU + libvirt (Ubuntu 24.04)

## 📌 Project Overview

This project implements a lightweight hypervisor-level autoscaling system using:

- KVM + QEMU (Virtualization)
- libvirt / virsh (VM management)
- Alpine Linux (Minimal VM OS)
- Bash (Autoscaler + Live Dashboard)
- stress-ng (CPU load simulation)

The autoscaler:

- Monitors CPU usage of each VM from the host
- Automatically creates new VMs when load is high
- Automatically deletes extra VMs when load drops
- Displays a live colored dashboard in the terminal

This simulates a simplified cloud autoscaling system similar to AWS Auto Scaling Groups.

---

# 🖥 Host System Setup

## Install Required Packages

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst
sudo apt install cloud-image-utils
sudo usermod -aG libvirt $USER
newgrp libvirt
```

Verify libvirt:

```bash
virsh list --all
```

---

# 💿 Step 1 — Download Alpine ISO

Download:

Alpine Linux → Virtual → x86_64

Example:

```
alpine-virt-3.23.3-x86_64.iso
```

---

# 🧱 Step 2 — Create Base Template VM

```bash
virt-install \
--name base-template \
--ram 256 \
--vcpus 1 \
--disk path=/var/lib/libvirt/images/base-template.qcow2,size=1 \
--cdrom /path/to/alpine-virt-3.23.3-x86_64.iso \
--network network=default \
--graphics none \
--console pty,target_type=serial \
--osinfo linux2022
```

## Inside Alpine Installation

Login as root and run:

```bash
setup-alpine
```

During setup:

- Hostname: base-template
- Network: dhcp
- Disk: sda
- Mode: sys
- Enable OpenSSH

After installation:

```bash
apk update
apk add stress-ng
rm -rf /var/cache/apk/*
poweroff
```

⚠ Do NOT boot base-template again after this.

---

# 🧬 Step 3 — Create Linked Clone (Backing File)

## Create qcow2 Backing Image

```bash
sudo qemu-img create -f qcow2 \
-b /var/lib/libvirt/images/base-template.qcow2 \
-F qcow2 \
/var/lib/libvirt/images/autoscale-1.qcow2
```

## Create VM from Backing Image

```bash
virt-install \
--name autoscale-1 \
--ram 256 \
--vcpus 1 \
--disk path=/var/lib/libvirt/images/autoscale-1.qcow2 \
--import \
--network network=default \
--graphics none \
--noautoconsole \
--osinfo linux2022
```

Start VM:

```bash
virsh start autoscale-1
```

---

# 📊 CPU Monitoring Concept

CPU stats collected via:

```bash
virsh domstats autoscale-1 --cpu-total
```

CPU usage calculation formula:

```
CPU% = (delta_cpu_time / delta_real_time) * 100
```

---

# 🚀 Step 4 — Autoscaler Script (Full Code)

Create file:

```bash
nano autoscaler.sh
```

Paste the following:

```bash
#!/bin/bash

BASE_IMAGE="/var/lib/libvirt/images/base-template.qcow2"
IMAGE_DIR="/var/lib/libvirt/images"

UPPER=70
LOWER=20
MAX_VMS=5
MIN_VMS=1

declare -a VM_LIST
VM_COUNTER=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

create_vm() {
    NAME="autoscale-$VM_COUNTER"

    sudo qemu-img create -f qcow2 \
    -b $BASE_IMAGE -F qcow2 \
    $IMAGE_DIR/$NAME.qcow2

    virt-install \
    --name $NAME \
    --ram 256 \
    --vcpus 1 \
    --disk path=$IMAGE_DIR/$NAME.qcow2 \
    --import \
    --network network=default \
    --graphics none \
    --noautoconsole \
    --osinfo linux2022

    virsh start $NAME

    VM_LIST+=($NAME)
    ((VM_COUNTER++))
}

destroy_vm() {
    NAME=${VM_LIST[-1]}

    virsh destroy $NAME
    virsh undefine $NAME
    sudo rm -f $IMAGE_DIR/$NAME.qcow2

    unset VM_LIST[-1]
}

get_cpu_usage() {
    NAME=$1

    BEFORE=$(virsh domstats $NAME --cpu-total | awk -F= '/cpu.time/ {print $2}')
    T1=$(date +%s%N)

    sleep 1

    AFTER=$(virsh domstats $NAME --cpu-total | awk -F= '/cpu.time/ {print $2}')
    T2=$(date +%s%N)

    CPU_DELTA=$((AFTER - BEFORE))
    TIME_DELTA=$((T2 - T1))

    CPU=$((100 * CPU_DELTA / TIME_DELTA))

    if [ $CPU -gt 100 ]; then
        CPU=100
    fi

    echo $CPU
}

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
```

Make executable:

```bash
chmod +x autoscaler.sh
```

Run:

```bash
./autoscaler.sh
```

---

# 🧪 Step 5 — Simulate Load

Inside any running VM:

```bash
stress-ng --cpu 1
```

Stop load:

```bash
Ctrl + C
```

Autoscaler will:

- Scale up when CPU > 70%
- Scale down when CPU < 20%

---

# 🏗 Final Architecture

Host:
- autoscaler.sh
- libvirt
- base-template.qcow2

VMs:
- autoscale-1.qcow2
- autoscale-2.qcow2
- autoscale-3.qcow2
- autoscale-4.qcow2

All clones use qcow2 backing file for minimal disk usage.

---

# 🎯 Demonstration Flow

1. Run autoscaler
2. Observe 1 VM running
3. Apply CPU load
4. New VMs auto-created
5. Stop load
6. Extra VMs auto-deleted

---

# 🏆 Project Complete

This system demonstrates:

- Hypervisor-level autoscaling
- Dynamic VM provisioning
- Resource-aware scaling decisions
- Infrastructure automation
- Real-time monitoring dashboard
