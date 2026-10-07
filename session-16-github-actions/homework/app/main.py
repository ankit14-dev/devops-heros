"""Small Flask API that exposes the calculator over HTTP."""
import os

from flask import Flask, jsonify, request

from app.calculator import OPERATIONS

APP_VERSION = os.getenv("APP_VERSION", "dev")

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(
        message="Hello from the Session 16 CI/CD demo!",
        version=APP_VERSION,
        endpoints=["/health", "/api/<operation>?a=<num>&b=<num>"],
    )


@app.get("/health")
def health():
    return jsonify(status="ok", version=APP_VERSION)


@app.get("/api/<operation>")
def calculate(operation):
    if operation not in OPERATIONS:
        return jsonify(error=f"unknown operation '{operation}'"), 404
    try:
        a = float(request.args["a"])
        b = float(request.args["b"])
    except (KeyError, ValueError):
        return jsonify(error="query parameters a and b must be numbers"), 400
    try:
        result = OPERATIONS[operation](a, b)
    except ValueError as exc:
        return jsonify(error=str(exc)), 400
    return jsonify(operation=operation, a=a, b=b, result=result)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
