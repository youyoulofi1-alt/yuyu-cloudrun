#!/usr/bin/env bash
set -euo pipefail

# Detect interactive mode (has a TTY). When non-interactive (e.g. `curl | bash`),
# the script will read configuration from environment variables or use defaults.
if [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# Non-interactive usage examples:
#  PROTO=vmess WSPATH=/ws DOMAIN=example.com SERVICE=my-service IDX=3 bash install.sh
#  PROTO=vmess WSPATH=/ws DOMAIN=example.com SERVICE=my-service IDX=3 curl -fsSL https://... | bash

echo "=========================================="
echo "  XRAY Cloud Run (VLESS / VMESS / TROJAN)"
echo "=========================================="

# -------- Preset Configurations --------
declare -A PRESETS=(
  [production]="memory=2048|cpu=1|instances=16|concurrency=60|timeout=3600"
  [budget]="memory=2048|cpu=1|instances=16|concurrency=60|timeout=3600"
)

apply_preset() {
  local preset=$1
  if [[ -v PRESETS[$preset] ]]; then
    local config="${PRESETS[$preset]}"
    IFS='|' read -ra settings <<< "$config"
    for setting in "${settings[@]}"; do
      IFS='=' read -r key value <<< "$setting"
      case "$key" in
        memory) MEMORY="$value" ;;
        cpu) CPU="$value" ;;
        instances) MAX_INSTANCES="$value" ;;
        concurrency) CONCURRENCY="$value" ;;
        timeout) TIMEOUT="$value" ;;
      esac
    done
  fi
}

# Suggested short list of regions (user will choose by index)
SUGGESTED_REGIONS=(
  us-central1
  us-east1
  us-west1
  europe-west1
  europe-west4
  asia-northeast1
  asia-southeast1
  asia-south1
  australia-southeast1
)

show_regions() {
  echo ""
  echo "🌍 Suggested Cloud Run Regions (pick one):"
  echo ""
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${SUGGESTED_REGIONS[@]}"; do
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (available)\n" "$i" "$r"
    else
      printf "%2d) %s\n" "$i" "$r"
    fi
    ((i++))
  done
}

# -------- Preset Selection --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PRESET:-}" ]; then
  echo ""
  echo "⚡ Quick Start with Presets:"
  echo "1) production (2048MB, 1 CPU, 16 instances, 60 concurrency)"
  echo "2) custom (configure everything manually)"
  read -rp "Select preset [1-2] (default: 1): " PRESET_CHOICE
fi
PRESET_CHOICE="${PRESET_CHOICE:-1}"

case "$PRESET_CHOICE" in
  1)
    apply_preset "production"
    PRESET_MODE="production"
    ;;
  *)
    PRESET_MODE="custom"
    ;;
esac

# -------- Telegram Bot --------
if [ "${INTERACTIVE}" = true ] && [ -z "${BOT_TOKEN:-}" ]; then
  read -rp "🤖 Telegram Bot Token (optional, press Enter to skip): " BOT_TOKEN
fi
BOT_TOKEN="${BOT_TOKEN:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CHAT_ID:-}" ] && [ -n "${BOT_TOKEN}" ]; then
  read -rp "💬 Telegram Chat ID (optional): " CHAT_ID
fi
CHAT_ID="${CHAT_ID:-}"

# Telegram send function
send_telegram() {
  if [ -z "${BOT_TOKEN}" ] || [ -z "${CHAT_ID}" ]; then
    return 0
  fi

  build_telegram_message() {
    local body="$1"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S %Z")
    local speed_text
    if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
      local mbps
      mbps=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
      speed_text="${SPEED_LIMIT} KB/s (~${mbps} Mbps)"
    else
      speed_text="${SPEED_LIMIT}"
    fi
    # Try to get public IP and country (non-blocking with short timeout)
    local ip_info
    local public_ip="unknown"
    local public_country="unknown"
    ip_info=$(curl -s --max-time 3 https://ipapi.co/json || true)
    if [ -n "$ip_info" ]; then
      public_ip=$(echo "$ip_info" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')
      public_country=$(echo "$ip_info" | sed -n 's/.*"country_name"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')
      [ -z "$public_ip" ] && public_ip="unknown"
      [ -z "$public_country" ] && public_country="unknown"
    fi

    local msg="<b>📌 XRAY Deployment</b>
    "
    msg+="<b>Date:</b> ${ts}
    "
    msg+="<b>Service:</b> ${SERVICE}
    "
    msg+="<b>Protocol:</b> ${PROTO^^}
    "
    msg+="<b>Region:</b> ${REGION}
    "
    msg+="<b>Host:</b> ${HOST}
    "
    msg+="<b>Public IP:</b> ${public_ip}
    "
    msg+="<b>Country:</b> ${public_country}
    "
    msg+="<b>Network:</b> ${NETWORK_DISPLAY}
    "
    msg+="<b>Speed Limit:</b> ${speed_text}
    "
    msg+="${body}"
    echo "$msg"
  }

  local raw="$1"
  local message
  message=$(build_telegram_message "$raw")
  # URL encode the message properly and send as HTML
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${message}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1
}

# -------- Protocol --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PROTO_CHOICE:-}" ]; then
  echo ""
  echo "🔐 Choose Protocol:"
  echo "1) VLESS"
  echo "2) VMESS"
  echo "3) TROJAN"
  read -rp "Select protocol [1-3] (default: 1): " PROTO_CHOICE
fi
PROTO_CHOICE="${PROTO_CHOICE:-1}"

case "$PROTO_CHOICE" in
  1)
    PROTO="vless"
    ;;
  2)
    PROTO="vmess"
    ;;
  3)
    PROTO="trojan"
    ;;
  *)
    echo "❌ Invalid protocol selection"
    exit 1
    ;;
esac

# -------- Network Type --------
# Cloud Run supports WebSocket (ws) reliably; gRPC has compatibility issues
NETWORK="ws"
NETWORK_DISPLAY="WebSocket"

# -------- WebSocket Path --------
if [ "${INTERACTIVE}" = true ] && [ -z "${WSPATH:-}" ]; then
  read -rp "📡 WebSocket Path (default: /ws): " WSPATH
fi
WSPATH="${WSPATH:-/ws}"

# Custom hostname is not supported reliably by this script; always use Cloud Run default
CUSTOM_HOST=""

# -------- Service Name --------
if [ "${INTERACTIVE}" = true ] && [ -z "${SERVICE:-}" ]; then
  read -rp "🪪 Cloud Run Service Name (default: xray-ws): " SERVICE
fi
SERVICE="${SERVICE:-xray-ws}"

# Validate service name format
if ! [[ "$SERVICE" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
  echo "❌ Invalid service name. Use lowercase alphanumeric and hyphens only (1-63 chars)."
  exit 1
fi

# -------- Optional Link Parameters --------
if [ "${INTERACTIVE}" = true ] && [ -z "${SNI_CHOICE:-}" ]; then
  echo ""
  echo "🔒 SNI (Server Name Indication):"
  echo "1) m.youtube.com"
  echo "2) www.google.com"
  echo "3) www.facebook.com"
  echo "4) Leave blank (no SNI)"
  read -rp "Select SNI or custom [1-4] (default: 4): " SNI_CHOICE
fi
SNI_CHOICE="${SNI_CHOICE:-4}"

case "$SNI_CHOICE" in
  1)
    SNI="m.youtube.com"
    ;;
  2)
    SNI="www.google.com"
    ;;
  3)
    SNI="www.facebook.com"
    ;;
  4)
    SNI=""
    ;;
  *)
    SNI="$SNI_CHOICE"
    ;;
esac

# -------- ALPN --------
if [ "${INTERACTIVE}" = true ] && [ -z "${ALPN:-}" ]; then
  echo ""
  echo "📡 Choose ALPN (Application Layer Protocol):"
  echo "1) default"
  echo "2) h2,http/1.1"
  echo "3) h2"
  echo "4) http/1.1"
  read -rp "Select ALPN [1-4] (default: 1): " ALPN_CHOICE
fi
ALPN_CHOICE="${ALPN_CHOICE:-1}"

case "$ALPN_CHOICE" in
  1)
    ALPN="default"
    ;;
  2)
    ALPN="h2,http/1.1"
    ;;
  3)
    ALPN="h2"
    ;;
  4)
    ALPN="http/1.1"
    ;;
  *)
    echo "❌ Invalid ALPN selection"
    exit 1
    ;;
esac

# Use region name as the default identifier for links
# CUSTOM_ID is set after region selection to the chosen region
CUSTOM_ID=""

# -------- UUID --------
UUID=$(cat /proc/sys/kernel/random/uuid)

# -------- Region Select --------
echo ""
if [ "${INTERACTIVE}" = true ] && [ -z "${REGION:-}" ]; then
  show_regions
  read -rp "Select region [1-${#SUGGESTED_REGIONS[@]}] (default: 1): " REGION_IDX
  REGION_IDX="${REGION_IDX:-1}"
  if [[ ! "$REGION_IDX" =~ ^[0-9]+$ ]] || [ "$REGION_IDX" -lt 1 ] || [ "$REGION_IDX" -gt ${#SUGGESTED_REGIONS[@]} ]; then
    echo "❌ Invalid region selection"
    exit 1
  fi
  REGION="${SUGGESTED_REGIONS[$((REGION_IDX-1))]}"
  # set custom identifier to region name
  CUSTOM_ID="$REGION"
fi
REGION="${REGION:-us-central1}"
echo "✅ Selected region: $REGION"

# -------- Performance Settings --------
echo ""
if [ "$PRESET_MODE" = "custom" ]; then
  echo "⚙️  Performance Configuration (optional, press Enter to skip):"
else
  echo "⚙️  Performance Configuration (preset: $PRESET_MODE - press Enter to keep)"
fi

if [ "${INTERACTIVE}" = true ] && [ -z "${MEMORY:-}" ]; then
  read -rp "💾 Memory (MB) [e.g., 512, 1024, 2048]: " MEMORY
fi
MEMORY="${MEMORY:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CPU:-}" ]; then
  read -rp "⚙️  CPU cores [e.g., 0.5, 1, 2]: " CPU
fi
CPU="${CPU:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${TIMEOUT:-}" ]; then
  read -rp "⏱️  Request timeout (seconds) [e.g., 300, 1800, 3600]: " TIMEOUT
fi
TIMEOUT="${TIMEOUT:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${MAX_INSTANCES:-}" ]; then
  read -rp "📊 Max instances [e.g., 5, 10, 20, 50]: " MAX_INSTANCES
fi
MAX_INSTANCES="${MAX_INSTANCES:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CONCURRENCY:-}" ]; then
  read -rp "🔗 Max concurrent requests per instance [e.g., 50, 100, 500, 1000]: " CONCURRENCY
fi
CONCURRENCY="${CONCURRENCY:-}"

# Speed Limit: قيمة ثابتة (لا تؤثر حالياً على السرعة الفعلية)
SPEED_LIMIT="${SPEED_LIMIT:-3000}"

# Show what was selected
echo ""
echo "✅ Selected configuration:"
[ -n "${MEMORY}" ] && echo "   Memory: ${MEMORY}MB" || echo "   Memory: (will use Cloud Run default)"
[ -n "${CPU}" ] && echo "   CPU: ${CPU} cores" || echo "   CPU: (will use Cloud Run default)"
[ -n "${TIMEOUT}" ] && echo "   Timeout: ${TIMEOUT}s" || echo "   Timeout: (will use Cloud Run default)"
[ -n "${MAX_INSTANCES}" ] && echo "   Max instances: ${MAX_INSTANCES}" || echo "   Max instances: (will use Cloud Run default)"
[ -n "${CONCURRENCY}" ] && echo "   Max concurrency: ${CONCURRENCY}" || echo "   Max concurrency: (will use Cloud Run default)"

# -------- Sanity checks --------
if ! command -v gcloud >/dev/null 2>&1; then
  echo "❌ gcloud CLI not found. Install and authenticate first."
  exit 1
fi

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "${PROJECT:-}" ]; then
  echo "❌ No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
  exit 1
fi

# -------- APIs --------
echo "⚙️ Enabling required APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet
echo "🚀 Deploying XRAY to Cloud Run..."

# Get PROJECT_NUMBER early (needed for HOST env var)
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project 2>/dev/null) --format="value(projectNumber)" 2>/dev/null)

# Build deploy command with optional parameters
DEPLOY_ARGS=(
  "--source" "."
  "--region" "$REGION"
  "--platform" "managed"
  "--allow-unauthenticated"
)

[ -n "${MEMORY}" ] && DEPLOY_ARGS+=("--memory" "${MEMORY}Mi")
[ -n "${CPU}" ] && DEPLOY_ARGS+=("--cpu" "${CPU}")
[ -n "${TIMEOUT}" ] && DEPLOY_ARGS+=("--timeout" "${TIMEOUT}")
[ -n "${MAX_INSTANCES}" ] && DEPLOY_ARGS+=("--max-instances" "${MAX_INSTANCES}")
[ -n "${CONCURRENCY}" ] && DEPLOY_ARGS+=("--concurrency" "${CONCURRENCY}")

# Speed limit is now configured interactively or via environment variable

# Use Cloud Run service URL as WebSocket host header
# Format: service-projectnumber.region.run.app
DEPLOY_ARGS+=("--set-env-vars" "PROTO=${PROTO},USER_ID=${UUID},WS_PATH=${WSPATH},NETWORK=${NETWORK},SPEED_LIMIT=${SPEED_LIMIT},HOST=${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app")
DEPLOY_ARGS+=("--quiet")

# -------- Get URL --------
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

# -------- Get URL and Host --------

# Use custom hostname if provided, otherwise use Cloud Run default
if [ -n "${CUSTOM_HOST}" ]; then
  HOST="${CUSTOM_HOST}"
  echo "Service URL: https://${HOST}"
  echo "✅ Using custom hostname: ${HOST}"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
  echo "Service URL: https://${HOST}"
  echo "✅ Using Cloud Run default: ${HOST}"
fi

# -------- Output --------
echo "=========================================="
echo "✅ DEPLOYMENT SUCCESS"
echo "=========================================="
echo "Protocol : $PROTO"
echo "Address  : $HOST"
echo "Port     : 443 (Cloud Run HTTPS)"
echo "UUID/PWD : $UUID"
if [ "$NETWORK" = "ws" ]; then
  echo "Path     : $WSPATH"
elif [ "$NETWORK" = "grpc" ]; then
  echo "Service  : $WSPATH"
fi
echo "Network  : $NETWORK_DISPLAY"
echo "TLS      : ON"
if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
  MBPS=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
  echo "Speed Limit: ${SPEED_LIMIT} KB/s (~${MBPS} Mbps) per connection"
else
  echo "Speed Limit: ${SPEED_LIMIT}"
fi
if [ -n "${MEMORY}${CPU}${TIMEOUT}${MAX_INSTANCES}${CONCURRENCY}" ]; then
  echo ""
  echo "⚙️  Configuration Applied:"
  [ -n "${MEMORY}" ] && echo "Memory      : ${MEMORY}MB"
  [ -n "${CPU}" ] && echo "CPU         : ${CPU} cores"
  [ -n "${TIMEOUT}" ] && echo "Timeout     : ${TIMEOUT}s"
  [ -n "${MAX_INSTANCES}" ] && echo "Max Instances: ${MAX_INSTANCES}"
  [ -n "${CONCURRENCY}" ] && echo "Concurrency : ${CONCURRENCY} requests/instance"
fi
echo "=========================================="

# -------- Generate Protocol Links --------
# Build query parameters for WebSocket (only supported on Cloud Run)
QUERY_PARAMS="type=ws&security=tls&path=${WSPATH}"
if [ -n "${SNI}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&sni=${SNI}"
fi
if [ -n "${ALPN}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&alpn=${ALPN}"
fi
# Add host parameter for WebSocket compatibility
QUERY_PARAMS="${QUERY_PARAMS}&host=${HOST}"

# Build fragment with custom ID
LINK_FRAGMENT="xray"
if [ -n "${CUSTOM_ID}" ]; then
  LINK_FRAGMENT="(${CUSTOM_ID})"
fi

if [ "$PROTO" = "vless" ]; then
  VLESS_QUERY="${QUERY_PARAMS}&host=${HOST}"
  VLESS_LINK="vless://${UUID}@${HOST}:443?${VLESS_QUERY}#${LINK_FRAGMENT}"
  echo ""
  echo "📎 VLESS LINK:"
  echo "$VLESS_LINK"
  SHARE_LINK="$VLESS_LINK"
elif [ "$PROTO" = "vmess" ]; then
  VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "$SERVICE",
  "add": "$HOST",
  "port": "443",
  "id": "$UUID",
  "aid": "0",
  "net": "$NETWORK",
  "type": "none",
  "host": "$HOST",
  "path": "$WSPATH",
  "tls": "tls"
}
EOF
)
  if [ -n "${SNI}" ]; then
    VMESS_JSON=$(echo "$VMESS_JSON" | sed "s/}/,\"sni\":\"${SNI}\"}/")
  fi
  if [ -n "${ALPN}" ]; then
    VMESS_JSON=$(echo "$VMESS_JSON" | sed "s/}/,\"alpn\":\"${ALPN}\"}/")
  fi
  VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"
  echo ""
  echo "📎 VMESS LINK:"
  echo "$VMESS_LINK"
  SHARE_LINK="$VMESS_LINK"
elif [ "$PROTO" = "trojan" ]; then
  TROJAN_LINK="trojan://${UUID}@${HOST}:443?${QUERY_PARAMS}#${LINK_FRAGMENT}"
  echo ""
  echo "📎 TROJAN LINK (PRIMARY - HOST):"
  echo "$TROJAN_LINK"
  SHARE_LINK="$TROJAN_LINK"
fi

# -------- Generate Alternative URL (short URL) --------
# Try to get the short URL from gcloud (if available)
ALT_HOST=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)" 2>/dev/null | sed 's|https://||' | sed 's|/||g' || echo "")

if [ -z "$ALT_HOST" ]; then
  ALT_HOST="$HOST"  # fallback to primary if short URL not available
fi

# Generate alternative link with short URL only if different from primary
if [ "$ALT_HOST" != "$HOST" ]; then
  if [ "$PROTO" = "vless" ]; then
    # Replace host in query params with ALT_HOST
    ALT_VLESS_QUERY=$(echo "$QUERY_PARAMS" | sed "s/&host=${HOST}/&host=${ALT_HOST}/")
    ALT_LINK="vless://${UUID}@${ALT_HOST}:443?${ALT_VLESS_QUERY}#(${REGION}-alt)"
  elif [ "$PROTO" = "vmess" ]; then
    ALT_VMESS_JSON=$(echo "$VMESS_JSON" | sed "s|\"add\": \"$HOST\"|\"add\": \"$ALT_HOST\"|")
    ALT_LINK="vmess://$(echo "$ALT_VMESS_JSON" | base64 -w 0)"
  elif [ "$PROTO" = "trojan" ]; then
    # Replace host in query params with ALT_HOST
    ALT_TROJAN_QUERY=$(echo "$QUERY_PARAMS" | sed "s/&host=${HOST}/&host=${ALT_HOST}/")
    ALT_LINK="trojan://${UUID}@${ALT_HOST}:443?${ALT_TROJAN_QUERY}#(${REGION}-alt)"
  fi
  
  echo ""
  echo "📎 ALTERNATIVE LINK (SHORT URL - HEADER):"
  echo "$ALT_LINK"
else
  ALT_LINK="$SHARE_LINK"
fi

# -------- Generate Data URIs --------
echo ""
echo "📊 DATA URIs:"
echo "=========================================="

# Prepare path/service info
PATH_INFO=""
if [ "$NETWORK" = "ws" ]; then
  PATH_INFO="Path: ${WSPATH}"
elif [ "$NETWORK" = "grpc" ]; then
  PATH_INFO="Service: ${WSPATH}"
fi

# Prepare optional params info
OPTIONAL_INFO=""
if [ -n "${SNI}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}SNI: ${SNI}\n"
fi
if [ -n "${ALPN}" ] && [ "${ALPN}" != "h2,http/1.1" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}ALPN: ${ALPN}\n"
fi
if [ -n "${CUSTOM_ID}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}Custom ID: ${CUSTOM_ID}\n"
fi

# Data URI 1: Plain text configuration
CONFIG_TEXT="✅ XRAY DEPLOYMENT SUCCESS

Protocol: ${PROTO^^}
Host: ${HOST}
Port: 443
UUID/Password: ${UUID}
${PATH_INFO}
Network: ${NETWORK_DISPLAY} + TLS
${OPTIONAL_INFO}Share Link: ${SHARE_LINK}"

DATA_URI_TEXT="data:text/plain;base64,$(echo -n "$CONFIG_TEXT" | base64 -w 0)"
echo "📋 Data URI (Text):"
echo "$DATA_URI_TEXT"
echo ""

# Data URI 2: JSON configuration
if [ "$NETWORK" = "ws" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "path": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
elif [ "$NETWORK" = "grpc" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "service_name": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
else
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
fi

# -------- Generate Alternative URL (short URL) --------
# Try to get the short URL from gcloud (if available)
ALT_HOST=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)" 2>/dev/null | sed 's|https://||' | sed 's|/||g' || echo "")

if [ -z "$ALT_HOST" ]; then
  ALT_HOST="$HOST"  # fallback to primary if short URL not available
fi

# Generate alternative link with short URL
if [ "$PROTO" = "vless" ]; then
  ALT_VLESS_QUERY="${QUERY_PARAMS}&host=${ALT_HOST}"
  ALT_LINK="vless://${UUID}@${ALT_HOST}:443?${ALT_VLESS_QUERY}#(${REGION}-alt)"
elif [ "$PROTO" = "vmess" ]; then
  ALT_VMESS_JSON=$(echo "$VMESS_JSON" | sed "s|\"add\": \"$HOST\"|\"add\": \"$ALT_HOST\"|")
  ALT_LINK="vmess://$(echo "$ALT_VMESS_JSON" | base64 -w 0)"
elif [ "$PROTO" = "trojan" ]; then
  ALT_LINK="trojan://${UUID}@${ALT_HOST}:443?${QUERY_PARAMS}#(${REGION}-alt)"
fi

DATA_URI_JSON="data:application/json;base64,$(echo -n "$CONFIG_JSON" | base64 -w 0)"
echo "📊 Data URI (JSON):"
echo "$DATA_URI_JSON"
echo "=========================================="

# -------- Send to Telegram --------
if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
  # Send primary link (primary URL in HOST)
  send_telegram "<b>🔗 PRIMARY (HOST):</b><pre>${SHARE_LINK}</pre>"
  
  # Send alternative link (short URL) if different
  #if [ "$ALT_LINK" != "$SHARE_LINK" ]; then
  #  send_telegram "<b>🔗 ALTERNATIVE (HEADER):</b><pre>${ALT_LINK}</pre>"
  #fi
fi