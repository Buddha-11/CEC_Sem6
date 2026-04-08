# 🧪 Systems Lab: Overlay Storage & Overlay Networking Experiments

This document describes three experiments demonstrating modern virtualization concepts:

1. Experiment 1.1 – Copy-on-Write (CoW) Overlay Storage
2. Experiment 1.2 – Performance Impact of Overlay Chains
3. Experiment 2.1 – VXLAN Overlay Networking (L2 over L3)

These experiments replicate real-world mechanisms used in:
- Virtual Machines (QEMU/KVM snapshots)
- Docker overlay storage
- Kubernetes networking (Flannel, OVN)

====================================================================

# 🧪 Experiment 1.1: Manual Overlay (Copy-on-Write)

## 🎯 Objective
To understand how qcow2 overlay disks isolate changes and allow instant rollback of a VM.

## 🧠 Theory

qcow2 supports **Copy-on-Write (CoW)**:
- Base image → immutable reference disk
- Overlay → stores only modified blocks
- Reads → check overlay first, fallback to base
- Writes → stored only in overlay

This allows:
- Fast snapshots
- Safe experimentation
- Instant reset

--------------------------------------------------------------------

## ⚙️ Step-by-Step Procedure

### 1. Create Base Disk

qemu-img create -f qcow2 -o preallocation=metadata,lazy_refcounts=on base-vm.qcow2 10G

Explanation:
- qcow2 = supports snapshots and CoW
- preallocation=metadata = improves performance
- lazy_refcounts = faster metadata updates

--------------------------------------------------------------------

### 2. Install OS on Base

Using virt-manager:
- Select "Custom storage"
- Choose base-vm.qcow2
- Install minimal Ubuntu Server
- Install basic tools (vim, fio, etc.)
- Shutdown immediately

IMPORTANT:
Base must remain clean (golden image)

--------------------------------------------------------------------

### 3. Protect Base Image

chmod -w base-vm.qcow2

Ensures:
- Base is not accidentally modified
- All writes go to overlay

--------------------------------------------------------------------

### 4. Create Overlay Disk

qemu-img create -f qcow2 -b base-vm.qcow2 -F qcow2 overlay-1.qcow2

Explanation:
- -b → sets backing file
- overlay stores only differences

--------------------------------------------------------------------

### 5. Run VM Using Overlay

qemu-system-x86_64 -hda overlay-1.qcow2 -m 2048 -cpu host -enable-kvm

OR via virt-manager:
- Import existing disk → overlay-1.qcow2

--------------------------------------------------------------------

### 6. Perform Destructive Operation

Inside VM:

sudo rm -rf /

Result:
- System becomes unusable
- Base remains untouched

--------------------------------------------------------------------

### 7. Reset System

rm overlay-1.qcow2

qemu-img create -f qcow2 -b base-vm.qcow2 -F qcow2 overlay-1.qcow2

Result:
- Fresh system instantly restored

--------------------------------------------------------------------

## 🎯 Result

- Overlay captured all changes
- Base remained unchanged
- VM restored instantly by deleting overlay

--------------------------------------------------------------------

## 🧠 Key Insight

Overlay depends on base, but base never depends on overlay.

====================================================================

# 🧪 Experiment 1.2: Performance Analysis of Overlays

## 🎯 Objective
To analyze how multiple overlay layers affect disk performance.

## 🧠 Theory

In Copy-on-Write systems:

READ:
overlay → check → base → fetch

WRITE:
read → modify → write (RMW cycle)

With multiple overlays:

overlay5 → overlay4 → overlay3 → overlay2 → overlay1 → base

More layers ⇒ more lookup ⇒ higher latency

--------------------------------------------------------------------

## ⚙️ Setup

### Install Benchmark Tool

sudo apt update
sudo apt install -y fio

--------------------------------------------------------------------

### Create Benchmark Script

nano test.sh

#!/bin/bash

echo "===== WRITE TEST ====="
fio --name=write_test \
  --ioengine=libaio \
  --rw=randwrite \
  --bs=4k \
  --size=512M \
  --runtime=30 \
  --time_based \
  --group_reporting

echo "===== READ TEST ====="
fio --name=read_test \
  --ioengine=libaio \
  --rw=randread \
  --bs=4k \
  --size=512M \
  --runtime=30 \
  --time_based \
  --group_reporting

chmod +x test.sh

--------------------------------------------------------------------

### Disable Cache (CRITICAL)

In virt-manager:
- Open VM settings
- Select Disk
- Set Cache mode = none

Reason:
- Avoids RAM caching
- Ensures real disk I/O measurement

--------------------------------------------------------------------

## 🥇 Base Test

chmod +w base-vm.qcow2

Run:
./test.sh

chmod -w base-vm.qcow2

--------------------------------------------------------------------

## 🥈 Single Overlay Test

qemu-img create -f qcow2 -b base-vm.qcow2 -F qcow2 overlay-1.qcow2

Run VM with overlay-1.qcow2:

./test.sh

--------------------------------------------------------------------

## 🥉 5-Layer Overlay Chain

rm -f overlay-*.qcow2

qemu-img create -f qcow2 -b base-vm.qcow2 -F qcow2 overlay-1.qcow2
qemu-img create -f qcow2 -b overlay-1.qcow2 -F qcow2 overlay-2.qcow2
qemu-img create -f qcow2 -b overlay-2.qcow2 -F qcow2 overlay-3.qcow2
qemu-img create -f qcow2 -b overlay-3.qcow2 -F qcow2 overlay-4.qcow2
qemu-img create -f qcow2 -b overlay-4.qcow2 -F qcow2 overlay-5.qcow2

Run VM with overlay-5.qcow2:

./test.sh

--------------------------------------------------------------------

## 📊 Observations

Base:
- IOPS ≈ 6950
- Latency ≈ 143 µs

1 Overlay:
- IOPS ≈ 6830
- Latency ≈ 145 µs

5 Overlays:
- IOPS ≈ 6420
- Latency ≈ 155 µs
- Write throughput drops significantly

--------------------------------------------------------------------

## 📉 Analysis

- Read performance degrades gradually
- Write performance degrades significantly
- Cause: Read-Modify-Write penalty

--------------------------------------------------------------------

## 🎯 Conclusion

- Single overlay → minimal overhead
- Multiple overlays → significant performance impact
- Writes are affected more than reads

====================================================================

# 🧪 Experiment 2.1: VXLAN Overlay Networking

## 🎯 Objective
To connect two VMs over a Layer 3 network so they behave as if they are on the same Layer 2 network.

## 🧠 Theory

VXLAN (Virtual Extensible LAN):
- Encapsulates Ethernet frames inside UDP
- Uses port 4789
- Enables L2 communication over L3

--------------------------------------------------------------------

## ⚙️ Setup

Host A → 192.168.122.21  
Host B → 192.168.122.46  

Overlay Network:
10.100.1.0/24

--------------------------------------------------------------------

## 🥇 Step 1: Verify Underlay Connectivity

ping 192.168.122.46

--------------------------------------------------------------------

## 🥈 Step 2: Install Tools

sudo apt update
sudo apt install -y iproute2 tcpdump

--------------------------------------------------------------------

## 🧱 Step 3: Create VXLAN Interface

### Host A

sudo ip link add vxlan0 type vxlan id 42 dstport 4789 remote 192.168.122.46 dev enp1s0
sudo ip addr add 10.100.1.1/24 dev vxlan0
sudo ip link set vxlan0 up

--------------------------------------------------------------------

### Host B

sudo ip link add vxlan0 type vxlan id 42 dstport 4789 remote 192.168.122.21 dev enp1s0
sudo ip addr add 10.100.1.2/24 dev vxlan0
sudo ip link set vxlan0 up

--------------------------------------------------------------------

## 🧪 Step 4: Test Overlay Network

ping 10.100.1.2

Result:
- Successful communication over overlay

--------------------------------------------------------------------

## 🔍 Step 5: Packet Inspection

sudo tcpdump -i enp1s0 port 4789

Observation:
- UDP packets visible
- VXLAN encapsulation confirmed

--------------------------------------------------------------------

## 🧠 Internal Working

Original packet:
10.100.1.1 → 10.100.1.2

Encapsulated as:
UDP packet:
192.168.122.21 → 192.168.122.46

--------------------------------------------------------------------

## 🎯 Result

- Overlay network successfully created
- Communication achieved across Layer 3 boundary

--------------------------------------------------------------------

# 🏁 Final Conclusion

- Overlay storage enables fast rollback using CoW
- Performance degrades with deep overlay chains
- VXLAN enables scalable overlay networking

These concepts are fundamental to:
- Cloud infrastructure
- Container orchestration systems
- Virtual networking

--------------------------------------------------------------------

# ⚡ Final Insight

Overlay systems introduce indirection, trading performance for flexibility and scalability.

