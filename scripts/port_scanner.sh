#!/usr/bin/env bash
# ==============================================================================
# Script: port_scanner.sh
# Purpose: Safe, targeted TCP port auditing for authorized cluster instances
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${BASE_DIR}/reports/scans"
TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"

# Authorized Lab Targets
declare -A TARGETS=(
    ["security-monitor"]="172.31.45.42"
    ["linux-server-01"]="172.31.32.76"
    ["linux-server-02"]="172.31.35.140"
)

# Standard monitored port range
PORT_RANGE="1-10000"

mkdir -p "${REPORTS_DIR}"

echo "=============================================================================="
echo "[+] Starting Network Attack Surface Audit: ${TIMESTAMP}"
echo "=============================================================================="

LATEST_SUMMARY="${REPORTS_DIR}/latest_scan_summary.txt"
> "${LATEST_SUMMARY}"

for HOST in "${!TARGETS[@]}"; do
    IP="${TARGETS[$HOST]}"
    XML_OUTPUT="${REPORTS_DIR}/${HOST}_${TIMESTAMP}.xml"
    LATEST_XML="${REPORTS_DIR}/${HOST}_latest.xml"

    echo "[*] Scanning target: ${HOST} (${IP}) on ports ${PORT_RANGE}..."

    # -Pn: Skip host ping discovery (Crucial for firewalled servers!)
    # -sT: Safe TCP connect scan
    # -sV: Detect service versions
    nmap -Pn -sT -sV --version-light -p "${PORT_RANGE}" "${IP}" -oX "${XML_OUTPUT}" > /dev/null

    ln -sf "${XML_OUTPUT}" "${LATEST_XML}"

    OPEN_PORTS=$(xmlstarlet sel -t -m "//port[state/@state='open']" \
        -v "@portid" -o ":" -v "service/@name" -n "${XML_OUTPUT}" || true)

    if [[ -z "${OPEN_PORTS}" ]]; then
        echo "    [-] No open ports discovered."
    else
        while IFS= read -r LINE; do
            [[ -z "${LINE}" ]] && continue
            PORT=$(echo "${LINE}" | cut -d':' -f1)
            SERVICE=$(echo "${LINE}" | cut -d':' -f2)
            echo "    [+] Discovered open port: ${PORT}/TCP (${SERVICE})"
            echo "${HOST}:${IP}:${PORT}:${SERVICE}" >> "${LATEST_SUMMARY}"
        done <<< "${OPEN_PORTS}"
    fi
done

echo "=============================================================================="
echo "[+] Scan complete! Results recorded in: ${LATEST_SUMMARY}"
echo "=============================================================================="
