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

# Connected users: detect listener process on :443 and count ESTABLISHED sessions for that process, fallback to xray access log
CONNECTED="0"
LISTENER=""
# Allow overriding detected listener via environment variable LISTENER_PROCESS
if [ -n "${LISTENER_PROCESS:-}" ]; then
  LISTENER="${LISTENER_PROCESS}"
fi

if command -v ss >/dev/null 2>&1; then
  # try to detect common listener names in ss output (nginx, haproxy, caddy, xray, traefik, envoy)
  if [ -z "$LISTENER" ]; then
    LIST_LINE=$(ss -ltnp '( sport = :443 )' 2>/dev/null | tail -n +2 | head -n1 || true)
    if echo "$LIST_LINE" | grep -qiE 'nginx|haproxy|caddy|xray|traefik|envoy'; then
      LISTENER=$(echo "$LIST_LINE" | grep -oEi 'nginx|haproxy|caddy|xray|traefik|envoy' | head -n1 | tr '[:upper:]' '[:lower:]')
    fi
  fi

  if [ -n "$LISTENER" ]; then
    # count established connections associated with the listener process
    CONNECTED=$(ss -4ntp state established '( sport = :443 or dport = :443 )' 2>/dev/null | grep -i "$LISTENER" || true)
    CONNECTED=$(echo "$CONNECTED" | wc -l | tr -d '[:space:]' || echo 0)
  else
    CONNECTED=$(ss -4nt state established '( sport = :443 or dport = :443 )' 2>/dev/null | tail -n +2 | wc -l | tr -d '[:space:]' || echo 0)
  fi
fi

# If /var/log/xray/access.log exists, prefer counting "accepted" or "upgraded"
if [ -f "/var/log/xray/access.log" ]; then
  LOG_CONN=$(grep -c -E "accepted|upgraded" /var/log/xray/access.log || true)
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
