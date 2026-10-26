#!/system/bin/sh
#
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
TEST_FILES="/data/local/tmp/acc_test_all.log /data/local/tmp/acc_test_all.hb"

echo "========================================"
echo "      ACC Daemon Action Controller      "
echo "========================================"

# Is a charging-switch test (acc -t) running? It needs the daemon stopped.
test_running() {
    pgrep -f '/[a]cc/acc .* (-t|--test)( |$)' >/dev/null 2>&1
}

# Move accd to root cgroup
move_accd() {
    pgrep -f '[a]ccd' | while read -r PID; do
        [ -n "$PID" ] || continue
        echo $PID > /sys/fs/cgroup/cgroup.procs 2>/dev/null || echo $PID > /dev/freezer/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/freezer/tasks 2>/dev/null || true
        echo $PID > /dev/cpuset/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/cpuset/tasks 2>/dev/null || true
        echo $PID > /dev/stune/tasks 2>/dev/null || echo $PID > /dev/schedtune/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/schedtune/tasks 2>/dev/null || true
        echo -1000 > /proc/$PID/oom_score_adj 2>/dev/null || true
    done
}

# Initialize ACC environment if needed
test -f /dev/acca || /data/adb/vr25/acc/service.sh

# Toggle daemon
if pgrep -f '[a]ccd' >/dev/null 2>&1; then
    echo "[*] Daemon is currently RUNNING."
    echo "[*] Stopping accd..."
    /dev/acca -D stop
    STATUS="❌"
    echo "[*] Daemon STOPPED."
else
    echo "[*] Daemon is currently STOPPED."

    if test_running; then
        echo "[!] Test All is running and needs the daemon stopped."
        echo "[!] Wait for it to finish (or cancel it), then try again."
        echo "========================================"
        exit 0
    fi
    rm -f $TEST_FILES   # stale leftovers from an interrupted test

    echo "[*] Starting accd..."
    setsid nohup /dev/acca -D start >/dev/null 2>&1 < /dev/null &
    i=0
    while [ $i -lt 6 ]; do
        sleep 1
        move_accd
        i=$((i + 1))
    done
    STATUS="✅"
    echo "[*] Daemon STARTED."
fi

# Get capacities for description update
eval "$(/dev/acc -sp capacity 2>/dev/null | grep -E '^(resume|pause|shutdown)_capacity=')"

# Update description (cross-compatible)
if [ -f "$PROP_FILE" ]; then
    sed -i "/^description=/ {
        s@^description=.*Extend@description=[accd ${STATUS}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | Extend@
    }" "$PROP_FILE"
else
    echo "[!] Error: module.prop not found at $PROP_FILE"
fi

echo "========================================"