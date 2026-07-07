#!/bin/bash
########################################
# T4-1 STATUS EXPORT
########################################
STATUS_JSON="/var/lib/monitoring/t4-1-status.json"
mkdir -p /var/lib/monitoring
HOSTNAME=$(hostname)
SSH_KEY="/root/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no"
# Primary path (VPN)
REMOTE_USER="mysta"
REMOTE_HOST_VPN="10.10.10.30"
REMOTE_PORT_VPN="443"
# Fallback path (Internet)
REMOTE_HOST_DIRECT="78.45.157.107"
REMOTE_PORT_DIRECT="44443"

########################################
# CPU TEMP
########################################
TEMP=0
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(awk '{printf("%.0f", $1/1000)}' /sys/class/thermal/thermal_zone0/temp)
fi

########################################
# RAM
########################################
RAM=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2*100}')

########################################
# UPTIME
########################################
UPTIME=$(uptime -p)

########################################
# DISK
########################################
DISK=$(df / | awk 'NR==2 {gsub("%",""); print $5}')

########################################
# VPN
########################################
VPN=false
VPN_STATE=$(/usr/local/bin/t4-monitor/vpn_health_check.sh 2>/dev/null)
if [[ "$VPN_STATE" == "VPN_OK" ]]; then
    VPN=true
fi

########################################
# STATE
########################################
STATE=$(cat /var/lib/t4-monitor/last_state 2>/dev/null || echo "UNKNOWN")

########################################
# FAN (rk3399-fanctl)
########################################
FAN_JSON="null"
if command -v rk3399-fanctl >/dev/null 2>&1; then
    FAN_JSON=$(rk3399-fanctl --export-json 2>/dev/null) || FAN_JSON="null"
fi

########################################
# WRITE JSON
########################################
cat > "$STATUS_JSON" <<EOF
{
  "hostname": "$HOSTNAME",
  "vpn": $VPN,
  "state": "$STATE",
  "disk": $DISK,
  "ram": $RAM,
  "temp": $TEMP,
  "uptime": "$UPTIME",
  "fan": $FAN_JSON,
  "timestamp": $(date +%s)
}
EOF

########################################
# PUSH – VPN (primary)
########################################
scp $SSH_OPTS -P "$REMOTE_PORT_VPN" \
    "$STATUS_JSON" \
    "${REMOTE_USER}@${REMOTE_HOST_VPN}:/var/lib/monitoring/t4-1-status.json" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "$(date +%s) t4-1-status.json pushed to Pi5 via VPN"
    exit 0
fi

########################################
# PUSH – Internet (fallback)
########################################
scp $SSH_OPTS -P "$REMOTE_PORT_DIRECT" \
    "$STATUS_JSON" \
    "${REMOTE_USER}@${REMOTE_HOST_DIRECT}:/var/lib/monitoring/t4-1-status.json" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "$(date +%s) t4-1-status.json pushed to Pi5 via direct Internet"
else
    echo "$(date +%s) WARNING: push to Pi5 failed – both VPN and direct path unavailable"
fi
