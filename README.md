# 🚀 Container & VM Autoscaling Lab – CEC Sem 6

This repository contains multiple implementations of **autoscaling systems** built using different virtualization and containerization technologies.

Each folder demonstrates how horizontal scaling can be implemented at different infrastructure layers — from containers to virtual machines.

---

## 📂 Repository Structure

```
.
├── docker-autoscale/
├── kvm-autoscale/
├── microstack-autoscale/
└── README.md
```

---

## 🧩 1️⃣ Docker Autoscaling

📁 [`docker-autoscale/`](./docker-autoscale)

Implements:

- Docker-based service replication
- CPU-based autoscaling using `docker stats`
- Dynamic Nginx reverse proxy configuration
- Layer 7 load balancing (Round Robin)
- Horizontal container scaling

This simulates core concepts of:
- Kubernetes HPA
- Reverse proxy load balancing
- Service discovery

👉 See detailed setup and explanation inside:
**[docker-autoscale/README.md](./docker-autoscale/README.md)**

---

## 🖥️ 2️⃣ KVM + QEMU VM Autoscaling

📁 [`kvm-autoscale/`](./kvm-autoscale)

Implements:

- Virtual machine creation using KVM/QEMU
- Host-level resource monitoring
- VM lifecycle management
- Infrastructure-level autoscaling

This demonstrates scaling at the **hypervisor level**, closer to IaaS cloud providers.

👉 See detailed documentation inside:
**[kvm-autoscale/README.md](./kvm-autoscale/README.md)**

---

## ☁️ 3️⃣ MicroStack (OpenStack) Autoscaling

📁 [`microstack-autoscale/`](./microstack-autoscale)

Implements:

- Autoscaling using OpenStack (MicroStack)
- VM orchestration via OpenStack APIs
- Cloud-native infrastructure scaling
- Real cloud control-plane interaction

This represents production-style autoscaling in private cloud environments.

👉 See detailed documentation inside:
**[microstack-autoscale/README.md](./microstack-autoscale/README.md)**

---

## 🧠 Conceptual Comparison

| Layer | Technology | Scaling Level |
|-------|------------|--------------|
| Application Layer | Docker + Nginx | Container Replicas |
| Hypervisor Layer | KVM + QEMU | Virtual Machines |
| Cloud Layer | MicroStack (OpenStack) | Cloud Instances |


---



## ⚙️ Requirements

- Linux (Ubuntu recommended)
- Docker
- KVM + QEMU
- MicroStack (OpenStack)
- Bash scripting knowledge

---
