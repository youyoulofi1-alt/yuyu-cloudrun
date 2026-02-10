#!/usr/bin/env bash
set -euo pipefail
ENV_FILE=/etc/default/yuyu_bot
LOG_FILE=/var/log/yuyu_bot.log
PID_FILE=/var/run/yuyu_bot.pid

# Load environment if present
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

mkdir -p $(dirname "$LOG_FILE")
# ensure log file exists
touch "$LOG_FILE"

# start
nohup /usr/local/bin/bot_listener.sh >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "Bot listener started (pid $(cat $PID_FILE)), logs: $LOG_FILE"
