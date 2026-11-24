#!/usr/bin/env bash
# ==============================================================================
# Sensor: config_integrity.sh
# Purpose: Cryptographic SHA-256 file integrity checker for critical system configs
# ==============================================================================

set -euo pipefail

# Auto-elevate to sudo if not root (required to read /etc/sudoers and sshd_config)
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BASE_DIR}/config"
HASH_FILE="${CONFIG_DIR}/config_hashes.sha256"
LOG_FILE="/var/log/security-monitor/security_events.log"
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
HOSTNAME="$(hostname)"

CRITICAL_FILES=(
    "/etc/hosts"
    "/etc/passwd"
    "/etc/sudoers"
    "/etc/sudoers.d/automation"
    "/etc/ssh/sshd_config.d/99-security-hardening.conf"
)

mkdir -p "${CONFIG_DIR}"

# 1. Generate or update baseline
if [[ ! -f "${HASH_FILE}" || "${1:-}" == "--generate" ]]; then
    echo "[*] Generating SHA-256 cryptographic baseline for critical files..."
    > "${HASH_FILE}"
    for FILE in "${CRITICAL_FILES[@]}"; do
        if [[ -f "${FILE}" ]]; then
            sha256sum "${FILE}" >> "${HASH_FILE}"
        fi
    done
    chmod 644 "${HASH_FILE}"
    echo "[+] Stored cryptographic hashes in ${HASH_FILE}:"
    cat "${HASH_FILE}"
    exit 0
fi

echo "=============================================================================="
echo " CONFIGURATION FILE INTEGRITY AUDIT [Host: ${HOSTNAME}]"
echo "=============================================================================="

INTEGRITY_FAILURES=0

while read -r EXPECTED_HASH FILE_PATH; do
    [[ -z "${FILE_PATH}" ]] && continue
    if [[ ! -f "${FILE_PATH}" ]]; then
        MSG="[${TIMESTAMP}] [SEVERITY: CRITICAL] [HOST: ${HOSTNAME}] Monitored file MISSING: ${FILE_PATH}!"
        echo "🚨 ${MSG}"
        echo "${MSG}" >> "${LOG_FILE}"
        INTEGRITY_FAILURES=$(( INTEGRITY_FAILURES + 1 ))
        continue
    fi

    CURRENT_HASH=$(sha256sum "${FILE_PATH}" | awk '{print $1}')
    if [[ "${CURRENT_HASH}" != "${EXPECTED_HASH}" ]]; then
        MSG="[${TIMESTAMP}] [SEVERITY: CRITICAL] [HOST: ${HOSTNAME}] INTEGRITY COMPROMISE! File '${FILE_PATH}' has been modified!"
        echo "🚨 ${MSG}"
        echo "   -> Expected SHA256: ${EXPECTED_HASH}"
        echo "   -> Detected SHA256: ${CURRENT_HASH}"
        echo "${MSG} Expected: ${EXPECTED_HASH}, Detected: ${CURRENT_HASH}" >> "${LOG_FILE}"
        INTEGRITY_FAILURES=$(( INTEGRITY_FAILURES + 1 ))
    fi
done < "${HASH_FILE}"

if (( INTEGRITY_FAILURES > 0 )); then
    echo "------------------------------------------------------------------------------"
    echo "Recommended Action: Investigate file tampering immediately."
    exit 2
else
    echo "✅ [OK] All critical system files match their cryptographic SHA-256 baselines."
    exit 0
fi
