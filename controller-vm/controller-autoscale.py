import subprocess
import json
import time
import threading
import requests
from flask import Flask, Response

app = Flask(__name__)

# ================= CONFIG =================
BASE_SERVICE_IP = "192.168.222.247"   # service-vm-1
SERVICE_PORT = 5000
SCALE_AT = 10

IMAGE = "service-golden"
FLAVOR = "m1.small"
NETWORK = "test"
# ==========================================

# ================= STATE ===================
counter = 0
scaling = False
scaled = False
active_ip = BASE_SERVICE_IP
lock = threading.Lock()
# ==========================================


# ---------- OpenStack helpers ----------

def run(cmd):
    print("\n[CMD]", " ".join(cmd))
    out = subprocess.check_output(cmd).decode()
    print("[CMD OUT]\n", out)
    return out


def wait_for_active(vm_name):
    print(f"[WAIT] Waiting for {vm_name} to become ACTIVE")
    while True:
        raw = run(["openstack", "server", "show", vm_name, "-f", "json"])
        data = json.loads(raw)
        status = data.get("status")
        print("[STATUS]", status)

        if status == "ACTIVE":
            print("[STATUS] VM is ACTIVE")
            return

        time.sleep(2)


def get_ip(vm_name):
    print(f"[WAIT] Fetching IP for {vm_name}")
    while True:
        raw = run(["openstack", "server", "show", vm_name, "-f", "json"])
        data = json.loads(raw)

        addresses = data.get("addresses", {})
        print("[ADDRESSES]", addresses)

        if addresses:
            # {"test": ["192.168.222.8"]}
            ip = list(addresses.values())[0][0]
            print("[IP FOUND]", ip)
            return ip

        time.sleep(2)


def wait_for_service(ip):
    print("[WAIT] Waiting for service on", ip)
    for attempt in range(40):
        try:
            r = requests.get(
                f"http://{ip}:{SERVICE_PORT}/work?n=TEST",
                timeout=2
            )
            if r.status_code == 200:
                print("[SERVICE UP]", ip)
                return True
        except Exception as e:
            print(f"[SERVICE WAIT] attempt={attempt+1}", e)

        time.sleep(2)

    return False


# ---------- Scaling thread ----------

def scale_out(start_counter):
    global active_ip, scaling, scaled

    vm_name = f"service-auto-{int(time.time())}"
    print("\n[SCALING] START")
    print("[SCALING] VM NAME:", vm_name)
    print("[SCALING] start_counter:", start_counter)

    try:
        run([
            "openstack", "server", "create",
            "--image", IMAGE,
            "--flavor", FLAVOR,
            "--network", NETWORK,
            vm_name
        ])

        wait_for_active(vm_name)
        ip = get_ip(vm_name)

        if not wait_for_service(ip):
            raise RuntimeError("Service never came up")

        with lock:
            active_ip = ip
            scaled = True
            scaling = False

        print("[SCALING DONE] Traffic switched to", ip)

    except Exception as e:
        print("[SCALING ERROR]", e)
        with lock:
            scaling = False

    print("[SCALING] END")


# ---------- Flask route ----------

@app.route("/")
def route():
    global counter, scaling

    print("\n[REQUEST ENTERED]")

    with lock:
        print(f"[STATE] counter={counter} scaling={scaling} scaled={scaled}")

        if scaling:
            print("[BLOCK] Scaling in progress")
            return Response("Scaling in progress\n", status=503)

        counter += 1
        n = counter

        if counter == SCALE_AT:
            print("[SCALE] Triggered at", counter)
            scaling = True
            threading.Thread(
                target=scale_out,
                args=(counter,),
                daemon=True
            ).start()
            return Response("Scaling started\n", status=503)

        target_ip = active_ip

    url = f"http://{target_ip}:{SERVICE_PORT}/work?n={n}"
    print("[FORWARD]", url)

    r = requests.get(url)
    return f"Routed to http://{target_ip}:{SERVICE_PORT}\n{r.text}"


# ---------- Main ----------

if __name__ == "__main__":
    print("[Controller] Autoscaler started")
    app.run(host="0.0.0.0", port=8000)
