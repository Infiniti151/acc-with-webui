#!/system/bin/sh
# Copyright 2026, Infiniti151
# License: GPLv3+

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"

echo "========================================"
echo "      ACC Daemon Action Controller      "
echo "========================================"

# Initialize ACC environment if needed
test -f /dev/acca || /data/adb/vr25/acc/service.sh

# Toggle daemon
if pgrep -f accd >/dev/null 2>&1; then
    echo "[*] Daemon is currently RUNNING."
    echo "[*] Stopping accd..."
    /dev/acca -D stop
    STATUS="❌"
    echo "[*] Daemon STOPPED."
else
    echo "[*] Daemon is currently STOPPED."
    echo "[*] Starting accd..."
    nohup /dev/acca -D start >/dev/null 2>&1 &
    sleep 0.5
    pgrep -f accd | while read -r PID; do
        if [ -n "$PID" ]; then
            # 1. Force cpuset to Root (:/)
            echo $PID > /dev/cpuset/tasks 2>/dev/null || \
            echo $PID > /sys/fs/cgroup/cpuset/tasks 2>/dev/null || true

            # 2. Force schedtune / stune to Root (:/)
            echo $PID > /dev/stune/tasks 2>/dev/null || \
            echo $PID > /dev/schedtune/tasks 2>/dev/null || \
            echo $PID > /sys/fs/cgroup/schedtune/tasks 2>/dev/null || true
        fi
    done
    STATUS="✅"
    echo "[*] Daemon STARTED."
fi

# Get capacities for description update
eval "$(/dev/acc -sp capacity 2>/dev/null | grep -E '^(resume|pause|shutdown)_capacity=')"

# --- Update description (cross-compatible) ---
if [ -f "$PROP_FILE" ]; then
    sed -i "/^description=/ {
        s@^description=.*Extend@description=[accd ${STATUS}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | Extend@
    }" "$PROP_FILE"
else
    echo "[!] Error: module.prop not found at $PROP_FILE"
fi

echo "========================================"