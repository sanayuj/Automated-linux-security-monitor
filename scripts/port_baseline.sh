#!/usr/bin/env bash
# ==============================================================================
# Script: port_baseline.sh
# Purpose: Manages the approved network port baseline for the cluster
# ==============================================================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BASE_DIR}/config"
BASELINE_FILE="${CONFIG_DIR}/approved_ports.txt"
REPORTS_DIR="${BASE_DIR}/reports/scans"
LATEST_SUMMARY="${REPORTS_DIR}/latest_scan_summary.txt"

mkdir -p "${CONFIG_DIR}"

usage() {
    echo "Usage: $0 [generate|view|approve]"
    echo "  generate : Runs a scan and generates an initial baseline file"
    echo "  view     : Displays the currently approved baseline"
    echo "  approve  : Interactively approve latest scan results into the baseline"
    exit 1
}

ACTION="${1:-}"

case "${ACTION}" in
    view)
        if [[ ! -f "${BASELINE_FILE}" ]]; then
            echo "[-] No baseline file found at ${BASELINE_FILE}. Run '$0 generate' first."
            exit 1
        fi
        echo "=============================================================================="
        echo " CURRENT APPROVED PORT BASELINE (${BASELINE_FILE})"
        echo " Format: HOST:IP:PORT:APPROVED_SERVICE"
        echo "=============================================================================="
        cat "${BASELINE_FILE}"
        echo "=============================================================================="
        ;;

    generate)
        echo "[*] Running comprehensive discovery scan to build initial baseline..."
        "${BASE_DIR}/scripts/port_scanner.sh"

        if [[ ! -f "${LATEST_SUMMARY}" || ! -s "${LATEST_SUMMARY}" ]]; then
            echo "[-] Scan produced no open ports to baseline."
            exit 1
        fi

        echo "# Approved Port Baseline - Generated on $(date)" > "${BASELINE_FILE}"
        echo "# Format: HOST:IP:PORT:SERVICE" >> "${BASELINE_FILE}"
        cat "${LATEST_SUMMARY}" >> "${BASELINE_FILE}"

        echo "[+] Baseline successfully generated at ${BASELINE_FILE}:"
        cat "${BASELINE_FILE}"
        ;;

    approve)
        if [[ ! -f "${LATEST_SUMMARY}" ]]; then
            echo "[-] No latest scan found. Run scripts/port_scanner.sh first."
            exit 1
        fi
        echo "[*] Appending latest scan ports to ${BASELINE_FILE}..."
        sort -u "${BASELINE_FILE}" "${LATEST_SUMMARY}" -o "${BASELINE_FILE}"
        echo "[+] Baseline updated."
        ;;

    *)
        usage
        ;;
esac
