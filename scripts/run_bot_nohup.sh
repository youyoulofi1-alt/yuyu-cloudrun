#!/usr/bin/env bash
set -euo pipefail
ENV_FILE=/etc/default/yuyu_bot
LOG_FILE=/var/log/yuyu_bot.log
PID_FILE=/var/run/yuyu_bot.pid

# Load environment if present (export all variables so child process inherits them)
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
fi

# Ensure runtime directories and last_update_id exist and are writable by the runner
RUN_UID=$(id -u)
RUN_USER=$(id -un)
mkdir -p $(dirname "$LOG_FILE")
mkdir -p /var/lib/yuyu_bot
if [ ! -f /var/lib/yuyu_bot/last_update_id ]; then
  echo 0 > /var/lib/yuyu_bot/last_update_id
  # try to set ownership to the running user if possible
  if [ "$RUN_UID" -ne 0 ]; then
    chown "$RUN_USER":"$RUN_USER" /var/lib/yuyu_bot/last_update_id 2>/dev/null || true
  fi
  chmod 644 /var/lib/yuyu_bot/last_update_id
fi
# ensure log file exists
touch "$LOG_FILE"

# start
nohup /usr/local/bin/bot_listener.sh >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "Bot listener started (pid $(cat $PID_FILE)), logs: $LOG_FILE"
