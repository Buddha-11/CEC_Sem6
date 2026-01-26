
# OpenStack Controller-Based Auto-Scaling Microservice (Golden Image Workflow)

---

## 1️⃣ System Requirements

- **OS:** Ubuntu 20.04 / 22.04 LTS
- **Hardware:** Virtualization (KVM) enabled
- **RAM:** ≥ 8 GB (16 GB recommended)
- **Permissions:** `sudo` privileges
- **Network:** Internet access

### Verify Virtualization Support
```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```
*Non-zero output is required.*

---

## 2️⃣ Install MicroStack (Single-Node OpenStack)

### Install MicroStack
```bash
sudo snap install microstack --classic
```

### Initialize MicroStack
```bash
sudo microstack init --auto --control
```
*Wait 5–10 minutes for completion.*

---

## 3️⃣ OpenStack CLI Setup

### Alias the CLI
```bash
sudo snap alias microstack.openstack openstack
```

### Load OpenStack Credentials
```bash
microstack config > ~/openrc
source ~/openrc
```

### Verify Installation
```bash
openstack server list
```

---

## 4️⃣ Networking Setup

### Create a Private Network
```bash
openstack network create test
```

### Create a Subnet
```bash
openstack subnet create \
  --network test \
  --subnet-range 192.168.222.0/24 \
  --gateway 192.168.222.1 \
  test-subnet
```

---

## 5️⃣ Security Groups (CRITICAL)

### Allow SSH Access
```bash
openstack security group rule create \
  --proto tcp --dst-port 22 --remote-ip 0.0.0.0/0 default
```

### Allow Service Traffic (Port 5000)
```bash
openstack security group rule create \
  --proto tcp --dst-port 5000 --remote-ip 0.0.0.0/0 default
```

### Allow Controller Traffic (Port 8000)
```bash
openstack security group rule create \
  --proto tcp --dst-port 8000 --remote-ip 0.0.0.0/0 default
```

---

## 6️⃣ SSH Keypair

### Create and Secure Keypair
```bash
openstack keypair create vm-key > vm-key.pem
chmod 600 vm-key.pem
```

---

## 7️⃣ Create Base Service VM (`service-vm-1`)

### Launch the VM
```bash
openstack server create \
  --image ubuntu \
  --flavor m1.small \
  --network test \
  --key-name vm-key \
  service-vm-1
```

### Wait for VM to be Active
```bash
openstack server list
```

### SSH into the VM
```bash
ssh -i vm-key.pem ubuntu@<SERVICE_VM_IP>
```

---

## 8️⃣ Install the Service Application

### Install Dependencies on `service-vm-1`
```bash
sudo apt update
sudo apt install -y python3 python3-pip
pip3 install flask
```

### Create the Service Application
Create `/home/ubuntu/service.py` with the following content:
```python
from flask import Flask, request
import socket
import time

app = Flask(__name__)
HOSTNAME = socket.gethostname()
counter = 0

@app.route("/work")
def work():
    global counter
    counter += 1
    time.sleep(0.2)
    return f"hello {counter} from {HOSTNAME}\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

---

## 9️⃣ Run Service via systemd

### Create the systemd Unit File
Create `/etc/systemd/system/service-app.service`:
```ini
[Unit]
Description=Service App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/ubuntu/service.py
Restart=always
User=ubuntu

[Install]
WantedBy=multi-user.target
```

### Enable and Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable service-app
sudo systemctl start service-app
```

### Test the Service
```bash
curl http://localhost:5000/work
```

---

## 🔟 Create Golden Image

### Stop the Base VM
```bash
openstack server stop service-vm-1
```

### Create the Golden Image
```bash
openstack server image create \
  --name service-golden \
  service-vm-1
```

### Restart the Base VM (Optional)
```bash
openstack server start service-vm-1
```

**IMPORTANT:** The golden image contains:
- Python 3
- Flask
- The running service
- systemd configuration
*No cloud-init required for future VMs.*

---

## 1️⃣1️⃣ Create Controller VM

### Launch the Controller VM
```bash
openstack server create \
  --image ubuntu \
  --flavor m1.small \
  --network test \
  --key-name vm-key \
  controller
```

### SSH into the Controller
```bash
ssh -i vm-key.pem ubuntu@<CONTROLLER_IP>
```

---

## 1️⃣2️⃣ Install Controller Dependencies

```bash
sudo apt update
sudo apt install -y python3 python3-pip
pip3 install flask requests
```

---

## 1️⃣3️⃣ Controller Responsibilities

The controller performs the following tasks:
1.  Accepts client traffic on port `8000`.
2.  Counts incoming requests.
3.  Triggers scaling when a defined request threshold (`N`) is reached.
4.  Creates a new VM from the golden image.
5.  Polls OpenStack for the new VM's status via its JSON API.
6.  Safely extracts the new VM's IP address.
7.  Performs health checks on the new service.
8.  Returns HTTP 503 (Service Unavailable) to clients during the scaling process.
9.  Switches traffic to the new VM **only after** its service is confirmed ready.

---

## 1️⃣4️⃣ Autoscaling Workflow

1.  **Requests 1–9:** Routed to `service-vm-1`.
2.  **Request 10:** Scaling is triggered.
    *   Traffic is blocked (HTTP 503).
    *   A new VM is created from `service-golden`.
3.  **During Scaling:** All client requests receive HTTP 503.
4.  **When New Service is Ready:** The `active_ip` is switched, and normal traffic resumes.

---

## 1️⃣5️⃣ Start the Controller

Run the controller application on the Controller VM:
```bash
python3 controller-autoscale.py
```
The controller listens on: `http://<CONTROLLER_IP>:8000`

---

## 1️⃣6️⃣ Test Autoscaling

### Run a Load Generator
```bash
while true; do
  curl http://<CONTROLLER_IP>:8000
  sleep 1
done
```

### Expected Behavior
- Initial responses come from `service-vm-1`.
- A scaling pause occurs at the request threshold.
- A new VM is created.
- Subsequent responses come from the **new VM's IP**.

---

## 1️⃣7️⃣ Why Hostname May Look Old

Golden images preserve the original hostname of the source VM. The **IP address change** is the true indicator that traffic has been correctly redirected to a new instance.

You can use `socket.gethostname()` in the service code to confirm the per-VM identity.

---

## 1️⃣8️⃣ Final Architecture

```
        Client
          |
          v
    Controller (Flask :8000)
          |
          +--> service-vm-1 (Original)
          |
          +--> service-auto-XXXXX (Golden Clone)
