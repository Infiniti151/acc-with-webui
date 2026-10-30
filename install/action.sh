#!/system/bin/sh
#
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
TEST_FILES="/data/local/tmp/acc_test_all.log /data/local/tmp/acc_test_all.hb"

# Detect system language
# Detect system language strictly from cmd activity get-config
lang=$(cmd activity get-config 2>/dev/null | grep -m1 '^config:' | sed 's/^config:[[:space:]]*//' | cut -d',' -f1 | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]' | cut -c1-2)

[ -z "$lang" ] && lang=$(getprop persist.sys.locale | cut -c1-2)
[ -z "$lang" ] && lang=$(getprop ro.product.locale | cut -c1-2)

# Fallback to default if translation doesn't exist
if [ -n "$lang" ] && [ -f "$MODDIR/translations/$lang/strings.sh" ]; then
    . "$MODDIR/translations/$lang/strings.sh"
else
    . "$MODDIR/strings.sh"
fi

echo "========================================"
echo "       ACC Daemon Action Controller      "
echo "========================================"

# Is a charging-switch test (acc -t) running? It needs the daemon stopped.
test_running() {
    pgrep -f '[a]cc/acc .* (-t|--test)( |$)' >/dev/null 2>&1
}

# Move accd to root cgroup
move_accd() {
    pgrep -f '[a]ccd' | while read -r PID; do
        [ -n "$PID" ] || continue
        echo "$PID" > /sys/fs/cgroup/cgroup.procs 2>/dev/null || echo "$PID" > /dev/freezer/tasks 2>/dev/null || echo "$PID" > /sys/fs/cgroup/freezer/tasks 2>/dev/null || true
        echo "$PID" > /dev/cpuset/tasks 2>/dev/null || echo "$PID" > /dev/sys/fs/cgroup/cpuset/tasks 2>/dev/null || true
        echo "$PID" > /dev/stune/tasks 2>/dev/null || echo "$PID" > /sys/fs/cgroup/schedtune/tasks 2>/dev/null || true
        echo -1000 > /proc/"$PID"/oom_score_adj 2>/dev/null || true
    done
}

# Initialize ACC environment if needed
test -f /dev/acca || /data/adb/vr25/acc/service.sh

# Toggle daemon
if pgrep -f '[a]ccd' >/dev/null 2>&1; then
    echo "$TXT_RUNNING"
    echo "$TXT_STOPPING"
    /dev/acca -D stop
    STATUS="❌"
    echo "$TXT_STOPPED"
else
    echo "$TXT_STOPPED_STATE"

    if test_running; then
        echo "$TXT_TEST_RUNNING"
        echo "$TXT_WAIT_TEST"
        echo "========================================"
        exit 0
    fi
    rm -f $TEST_FILES   # stale leftovers from an interrupted test

    echo "$TXT_STARTING"
    setsid nohup /dev/acca -D start >/dev/null 2>&1 < /dev/null &
    i=0
    while [ $i -lt 6 ]; do
        sleep 1
        move_accd
        i=$((i + 1))
    done
    STATUS="✅"
    echo "$TXT_STARTED"
fi

# Get capacities for description update
eval "$(/dev/acc -sp capacity 2>/dev/null | grep -E '^(resume|pause|shutdown)_capacity=')"

# Update description (cross-compatible)
if [ -f "$PROP_FILE" ]; then
    sed -i "s@^description=.*@description=[accd ${STATUS}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | ${MODULE_NAME}@" "$PROP_FILE"
else
    echo "$TXT_PROP_ERROR $PROP_FILE"
fi

echo "========================================"
