#!/usr/bin/env bash
# ==============================================================================
# Script: port_change_detector.sh
# Purpose: Compares live network state against the approved baseline and alerts
# Exit codes: 0 = OK (Baseline Match), 1 = Warning (Closed Port), 2 = Critical (Unauthorized Port)
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BASE_DIR}/config"
BASELINE_FILE="${CONFIG_DIR}/approved_ports.txt"
REPORTS_DIR="${BASE_DIR}/reports/scans"
LATEST_SUMMARY="${REPORTS_DIR}/latest_scan_summary.txt"
LOG_FILE="/var/log/security-monitor/port_changes.log"
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"

if [[ ! -f "${BASELINE_FILE}" ]]; then
    echo "[-] Baseline file missing! Run 'scripts/port_baseline.sh generate' first."
    exit 3
fi

# Run fresh scan
"${BASE_DIR}/scripts/port_scanner.sh"

echo ""
echo "=============================================================================="
echo " PORT BASELINE VERIFICATION AUDIT: ${TIMESTAMP}"
echo "=============================================================================="

# Temporary working files
APPROVED_SORTED=$(mktemp)
CURRENT_SORTED=$(mktemp)
trap 'rm -f "${APPROVED_SORTED}" "${CURRENT_SORTED}"' EXIT

grep -v '^#' "${BASELINE_FILE}" | sort -u > "${APPROVED_SORTED}"
sort -u "${LATEST_SUMMARY}" > "${CURRENT_SORTED}"

# 1. Detect Newly Opened (Unapproved) Ports
UNAPPROVED=$(comm -13 "${APPROVED_SORTED}" "${CURRENT_SORTED}")

# 2. Detect Closed Ports (Were in baseline, but not detected today)
CLOSED=$(comm -23 "${APPROVED_SORTED}" "${CURRENT_SORTED}")

EXIT_CODE=0

if [[ -n "${UNAPPROVED}" ]]; then
    echo "🚨 [CRITICAL ALERT] UNAUTHORIZED OPEN PORTS DETECTED!"
    echo "------------------------------------------------------------------------------"
    while IFS= read -r LINE; do
        [[ -z "${LINE}" ]] && continue
        HOST=$(echo "${LINE}" | cut -d':' -f1)
        IP=$(echo "${LINE}" | cut -d':' -f2)
        PORT=$(echo "${LINE}" | cut -d':' -f3)
        SERVICE=$(echo "${LINE}" | cut -d':' -f4)
        
        MSG="[${TIMESTAMP}] [SEVERITY: CRITICAL] [HOST: ${HOST}] [IP: ${IP}] Unauthorized Port ${PORT}/TCP (${SERVICE}) detected!"
        echo "  -> ${MSG}"
        echo "${MSG}" >> "${LOG_FILE}"
    done <<< "${UNAPPROVED}"
    echo "------------------------------------------------------------------------------"
    echo "Recommended Action: Investigate process listening on the port and terminate if unauthorized."
    EXIT_CODE=2
fi

if [[ -n "${CLOSED}" ]]; then
    echo "⚠️  [WARNING] EXPECTED APPROVED PORTS ARE CURRENTLY CLOSED/UNREACHABLE:"
    echo "------------------------------------------------------------------------------"
    while IFS= read -r LINE; do
        [[ -z "${LINE}" ]] && continue
        HOST=$(echo "${LINE}" | cut -d':' -f1)
        PORT=$(echo "${LINE}" | cut -d':' -f3)
        SERVICE=$(echo "${LINE}" | cut -d':' -f4)
        
        MSG="[${TIMESTAMP}] [SEVERITY: WARNING] [HOST: ${HOST}] Approved Port ${PORT}/TCP (${SERVICE}) is CLOSED or service down!"
        echo "  -> ${MSG}"
        echo "${MSG}" >> "${LOG_FILE}"
    done <<< "${CLOSED}"
    echo "------------------------------------------------------------------------------"
    [[ "${EXIT_CODE}" -eq 0 ]] && EXIT_CODE=1
fi

if [[ -z "${UNAPPROVED}" && -z "${CLOSED}" ]]; then
    echo "✅ [OK] All detected ports match the approved security baseline perfectly."
    echo "[${TIMESTAMP}] [SEVERITY: OK] All ports match approved baseline." >> "${LOG_FILE}"
    EXIT_CODE=0
fi

echo "=============================================================================="
exit "${EXIT_CODE}"
