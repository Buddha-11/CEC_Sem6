from flask import Flask, request
import socket

app = Flask(__name__)

@app.route("/")
def home():
    msg = request.args.get("msg", "No input")
    hostname = socket.gethostname()
    return f"Message: {msg}<br>Served by: {hostname}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
