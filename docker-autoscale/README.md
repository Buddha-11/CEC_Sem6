# Docker-Based Autoscaling with Nginx Load Balancer

## 📌 Project Overview

This project implements a **custom container autoscaling system** using Docker, Bash, and Nginx.

The system:

- Runs a Flask-based web service in Docker containers
- Monitors container CPU usage from the host
- Automatically scales containers up/down based on CPU thresholds
- Dynamically updates an Nginx reverse proxy configuration
- Performs Layer 7 load balancing across running replicas

This simulates core functionality of **Kubernetes Horizontal Pod Autoscaler (HPA)** using only Docker and Bash.

---

## 🏗️ Architecture

Client (Browser)  
&nbsp;&nbsp;&nbsp;&nbsp;↓  
Nginx (Reverse Proxy & Load Balancer)  
&nbsp;&nbsp;&nbsp;&nbsp;↓  
Flask Containers (flask_1, flask_2, flask_3...)  
&nbsp;&nbsp;&nbsp;&nbsp;↑  
Autoscaler Script (Host OS)

---

## 🧠 Key Concepts Implemented

- Horizontal scaling (replica-based scaling)
- CPU-based autoscaling
- Reverse proxy (Layer 7 load balancing)
- Round-robin request distribution
- Dynamic Nginx upstream configuration
- Docker internal DNS service discovery
- Cooldown stabilization logic

---

## 📂 Project Structure

```
docker-autoscale/
│
├── app.py
├── Dockerfile
├── requirements.txt
├── autoscaler.sh
└── README.md
```

---

## 🚀 Setup Instructions

### 1️⃣ Create Docker Network

```bash
docker network create autoscale-net
```

---

### 2️⃣ Build Flask Image

```bash
docker build -t flask-demo .
```

---

### 3️⃣ Run Initial Flask Container

```bash
docker run -d \
  --name flask_1 \
  --network autoscale-net \
  flask-demo
```

---

### 4️⃣ Start Nginx Load Balancer

```bash
docker run -d \
  --name nginx-lb \
  --network autoscale-net \
  -p 8080:80 \
  nginx
```

---

### 5️⃣ Start Autoscaler

```bash
chmod +x autoscaler.sh
./autoscaler.sh
```

---

## 🧪 Testing Autoscaling

### Trigger CPU Load

```bash
docker exec -it flask_1 sh
stress --cpu 1
```

When CPU exceeds threshold:

- New container (flask_2, flask_3...) is created
- Nginx configuration is regenerated
- Traffic is distributed across containers

---

## 🌐 Access the Service

Open in browser:

```
http://localhost:8080/?msg=hello
```

Refresh multiple times to observe:

```
Served by: flask_1
Served by: flask_2
Served by: flask_3
```

This confirms:

- Load balancing is active
- Round-robin distribution works
- Autoscaling is functional

---

## ⚙️ Autoscaling Logic

The autoscaler:

1. Reads CPU usage using `docker stats`
2. Computes average CPU across replicas
3. If CPU > threshold → scales up
4. If CPU < threshold → scales down
5. Regenerates Nginx upstream configuration
6. Reloads Nginx gracefully

Scaling constraints:

- Minimum containers: 1
- Maximum containers: 5
- Cooldown period: 15 seconds

---



## 📌 Conclusion

This project demonstrates a simplified container orchestration system built from scratch using Docker, Bash, and Nginx. It replicates fundamental cloud-native concepts including autoscaling, reverse proxying, and load balancing without using Kubernetes.

---
