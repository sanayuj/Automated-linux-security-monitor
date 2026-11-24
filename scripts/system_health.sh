#!/usr/bin/env bash
# ==============================================================================
# Sensor: system_health.sh
# Purpose: Collects real-time system health metrics into structured JSON
# ==============================================================================

set -euo pipefail

HOSTNAME="$(hostname)"
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"

# 1. CPU Load
LOAD_1M=$(awk '{print $1}' /proc/loadavg)
LOAD_5M=$(awk '{print $2}' /proc/loadavg)
LOAD_15M=$(awk '{print $3}' /proc/loadavg)

# 2. RAM
TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
AVAIL_MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
USED_MEM=$(( TOTAL_MEM - AVAIL_MEM ))
MEM_PCT=$(( (USED_MEM * 100) / TOTAL_MEM ))

# 3. Disk Usage (Root partition)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

# 4. Active Users & Processes
ACTIVE_USERS=$(who | wc -l)
TOTAL_PROCS=$(ps -ef | wc -l)

# Output clean JSON
cat <<JSON
{
  "hostname": "${HOSTNAME}",
  "timestamp": "${TIMESTAMP}",
  "metrics": {
    "cpu_load_1m": ${LOAD_1M},
    "cpu_load_5m": ${LOAD_5M},
    "cpu_load_15m": ${LOAD_15M},
    "memory_used_percent": ${MEM_PCT},
    "disk_root_used_percent": ${DISK_USAGE},
    "disk_root_available": "${DISK_AVAIL}",
    "active_logged_in_users": ${ACTIVE_USERS},
    "total_running_processes": ${TOTAL_PROCS}
  }
}
JSON
