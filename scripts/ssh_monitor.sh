#!/usr/bin/env bash
# ==============================================================================
# Sensor: ssh_monitor.sh
# Purpose: Detects SSH brute-force attempts and anomalous logins via systemd journal
# ==============================================================================

set -euo pipefail

WINDOW="15 minutes ago"
FAILED_THRESHOLD_WARN=3
FAILED_THRESHOLD_CRIT=5
LOG_FILE="/var/log/security-monitor/security_events.log"
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(hostname)"

echo "=============================================================================="
echo " SSH AUTHENTICATION AUDIT [Host: ${HOSTNAME} | Window: Last 15m]"
echo "=============================================================================="

# Extract authentication failures from journalctl
AUTH_FAILURES=$(journalctl -u ssh --since "${WINDOW}" --no-pager 2>/dev/null | grep -E "Failed password|Connection closed by authenticating user|Invalid user" || true)

# Count and group failed login attempts by IP address
IP_COUNTS=$(echo "${AUTH_FAILURES}" | grep -oE "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' | sort | uniq -c || true)

ALERT_TRIGGERED=0

if [[ -n "${IP_COUNTS}" ]]; then
    while read -r COUNT IP; do
        [[ -z "${COUNT}" ]] && continue
        if (( COUNT >= FAILED_THRESHOLD_CRIT )); then
            MSG="[${TIMESTAMP}] [SEVERITY: CRITICAL] [HOST: ${HOSTNAME}] SSH Brute Force Alert! ${COUNT} failed login attempts from ${IP} in last 15m."
            echo "🚨 ${MSG}"
            echo "${MSG}" >> "${LOG_FILE}"
            ALERT_TRIGGERED=2
        elif (( COUNT >= FAILED_THRESHOLD_WARN )); then
            MSG="[${TIMESTAMP}] [SEVERITY: WARNING] [HOST: ${HOSTNAME}] Suspicious SSH Activity: ${COUNT} failed login attempts from ${IP}."
            echo "⚠️  ${MSG}"
            echo "${MSG}" >> "${LOG_FILE}"
            [[ "${ALERT_TRIGGERED}" -eq 0 ]] && ALERT_TRIGGERED=1
        fi
    done <<< "${IP_COUNTS}"
fi

# Audit successful logins
SUCCESS_LOGINS=$(journalctl -u ssh --since "${WINDOW}" --no-pager 2>/dev/null | grep "Accepted publickey" || true)
if [[ -n "${SUCCESS_LOGINS}" ]]; then
    COUNT_OK=$(echo "${SUCCESS_LOGINS}" | wc -l)
    echo "ℹ️  [INFO] ${COUNT_OK} successful key-based login(s) recorded in the last 15m."
fi

if [[ "${ALERT_TRIGGERED}" -eq 0 ]]; then
    echo "✅ [OK] SSH authentication metrics normal. No brute-force patterns detected."
fi

echo "=============================================================================="
exit "${ALERT_TRIGGERED}"
