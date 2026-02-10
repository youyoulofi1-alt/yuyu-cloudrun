#!/bin/bash
# status.sh - send basic server status to Telegram
# Requires: BOT_TOKEN, CHAT_ID in env or set in this file

set -eu

BOT_TOKEN=${BOT_TOKEN:-}
CHAT_ID=${CHAT_ID:-}

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "BOT_TOKEN and CHAT_ID must be set in environment"
  exit 1
fi

send_telegram() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=HTML" >/dev/null 2>&1 || true
}

# Gather info
IP=$(curl -s --max-time 5 https://ifconfig.me || echo "unknown")
UPTIME=$(uptime -p 2>/dev/null || echo "unknown")

# Connected users: try ss on port 443, fallback to xray access log
CONNECTED="0"
if command -v ss >/dev/null 2>&1; then
  CONNECTED=$(ss -ntu | grep ":443" | wc -l | tr -d '[:space:]' || echo 0)
fi

# If /var/log/xray/access.log exists, prefer counting "accepted"
if [ -f "/var/log/xray/access.log" ]; then
  LOG_CONN=$(grep -c "accepted" /var/log/xray/access.log || true)
  if [ -n "$LOG_CONN" ] && [ "$LOG_CONN" -gt 0 ]; then
    CONNECTED="$LOG_CONN"
  fi
fi

MESSAGE="<b>📊 Server Status</b>\n\n"
MESSAGE+="<b>🖥 IP:</b> ${IP}\n"
MESSAGE+="<b>⏱ Uptime:</b> ${UPTIME}\n"
MESSAGE+="<b>👥 Connected users:</b> ${CONNECTED}\n"
MESSAGE+="<b>📡 Port:</b> 443\n"
MESSAGE+="<b>🕒 Time:</b> $(date -u +"%Y-%m-%d %H:%M:%S UTC")\n"

send_telegram "$MESSAGE"

exit 0
