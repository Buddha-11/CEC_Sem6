from flask import Flask, request
import os
import time

app = Flask(__name__)
VM_NAME = os.uname().nodename

@app.route("/work")
def work():
    n = request.args.get("n", "?")
    time.sleep(1)
    return f"hello {n} from {VM_NAME}\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
