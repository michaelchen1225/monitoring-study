#!/usr/bin/env bash

PORT=3000

if lsof -i :$PORT > /dev/null 2>&1; then
    echo "[INFO] Port $PORT already in use."
else
    echo "[INFO] Port $PORT free. Starting port-forward..."

    nohup kubectl port-forward \
        --address 0.0.0.0 \
        -n monitoring \
        svc/grafana 3000:80 \
        > /tmp/grafana-port-forward.log 2>&1 &

    echo "[INFO] Started."
fi