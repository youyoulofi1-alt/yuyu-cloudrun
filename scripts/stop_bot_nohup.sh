#!/usr/bin/env bash
set -euo pipefail
PID_FILE=/var/run/yuyu_bot.pid

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  echo "Bot listener stopped (pid $PID)"
else
  echo "No pid file found at $PID_FILE"
fi
