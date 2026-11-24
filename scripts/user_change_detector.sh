#!/usr/bin/env bash
# ==============================================================================
# Sensor: user_change_detector.sh
# Purpose: Detects unauthorized local user accounts and privileged group escalations
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${BASE_DIR}/config"
APPROVED_USERS_FILE="${DATA_DIR}/approved_users.txt"
APPROVED_SUDO_FILE="${DATA_DIR}/approved_sudoers.txt"
LOG_FILE="/var/log/security-monitor/security_events.log"
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(hostname)"

mkdir -p "${DATA_DIR}"

# 1. Generate baselines if they do not exist
if [[ ! -f "${APPROVED_USERS_FILE}" ]]; then
    cut -d: -f1 /etc/passwd | sort > "${APPROVED_USERS_FILE}"
    echo "[+] Initialized approved users baseline at ${APPROVED_USERS_FILE}"
fi

if [[ ! -f "${APPROVED_SUDO_FILE}" ]]; then
    getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v '^$' | sort > "${APPROVED_SUDO_FILE}" || true
    echo "[+] Initialized approved sudoers baseline at ${APPROVED_SUDO_FILE}"
fi

CURRENT_USERS=$(mktemp)
CURRENT_SUDO=$(mktemp)
trap 'rm -f "${CURRENT_USERS}" "${CURRENT_SUDO}"' EXIT

cut -d: -f1 /etc/passwd | sort > "${CURRENT_USERS}"
getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v '^$' | sort > "${CURRENT_SUDO}" || true

NEW_USERS=$(comm -13 "${APPROVED_USERS_FILE}" "${CURRENT_USERS}")
REMOVED_USERS=$(comm -23 "${APPROVED_USERS_FILE}" "${CURRENT_USERS}")
NEW_SUDO=$(comm -13 "${APPROVED_SUDO_FILE}" "${CURRENT_SUDO}")

EXIT_CODE=0

echo "=============================================================================="
echo " USER ACCOUNT & PRIVILEGED GROUP AUDIT [Host: ${HOSTNAME}]"
echo "=============================================================================="

if [[ -n "${NEW_SUDO}" ]]; then
    echo "🚨 [CRITICAL ALERT] UNEXPECTED PRIVILEGED SUDO USER DETECTED!"
    while read -r USER; do
        [[ -z "${USER}" ]] && continue
        MSG="[${TIMESTAMP}] [SEVERITY: CRITICAL] [HOST: ${HOSTNAME}] User '${USER}' added to privileged 'sudo' group without approval!"
        echo "  -> ${MSG}"
        echo "${MSG}" >> "${LOG_FILE}"
    done <<< "${NEW_SUDO}"
    EXIT_CODE=2
fi

if [[ -n "${NEW_USERS}" ]]; then
    echo "⚠️  [WARNING] NEW UNAPPROVED USER ACCOUNTS DETECTED:"
    while read -r USER; do
        [[ -z "${USER}" ]] && continue
        MSG="[${TIMESTAMP}] [SEVERITY: WARNING] [HOST: ${HOSTNAME}] New local user account created: '${USER}'"
        echo "  -> ${MSG}"
        echo "${MSG}" >> "${LOG_FILE}"
    done <<< "${NEW_USERS}"
    [[ "${EXIT_CODE}" -eq 0 ]] && EXIT_CODE=1
fi

if [[ -n "${REMOVED_USERS}" ]]; then
    echo "ℹ️  [INFO] User accounts removed from system: $(echo ${REMOVED_USERS} | tr '\n' ' ')"
fi

if [[ -z "${NEW_SUDO}" && -z "${NEW_USERS}" ]]; then
    echo "✅ [OK] User accounts and sudo group memberships match approved baseline."
fi

echo "=============================================================================="
exit "${EXIT_CODE}"
