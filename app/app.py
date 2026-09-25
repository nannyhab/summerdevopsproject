import os

import psycopg
from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest

app = Flask(__name__)

REQUESTS = Counter("web_requests", "Requests served, by HTTP status", ["status"])
UNCOUNTED_PATHS = {"/metrics", "/healthz", "/readyz"}


def connect():
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "postgres"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "postgres"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=2,
    )


@app.get("/api")
def api():
    try:
        with connect() as conn:
            now = conn.execute("SELECT now()").fetchone()[0]
    except psycopg.Error:
        return jsonify(error="database unreachable"), 500
    return jsonify(now=now.isoformat())


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/readyz")
def readyz():
    try:
        with connect():
            pass
    except psycopg.Error:
        return "database unreachable", 503
    return "ok"


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.after_request
def count_request(response):
    if request.path not in UNCOUNTED_PATHS:
        REQUESTS.labels(status=str(response.status_code)).inc()
    return response
