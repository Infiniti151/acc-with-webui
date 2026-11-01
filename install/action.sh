#!/system/bin/sh
#
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later

MODDIR="${0%/*}"
PROP_FILE="$MODDIR/module.prop"
TEST_FILES="/data/local/tmp/acc_test_all.log /data/local/tmp/acc_test_all.hb"

# Detect system language
lang=""

# Helper function to normalize and check if a locale folder exists
resolve_locale() {
    local candidate="$1"
    [ -z "$candidate" ] && return 1

    local clean_locale
    clean_locale=$(echo "$candidate" | tr '_' '-')

    # 1. Check for exact match first (e.g. de-DE, pt-PT)
    if [ -d "$MODDIR/translations/$clean_locale" ]; then
        lang="$clean_locale"
        return 0

    # 2. Handle Chinese variants explicitly
    elif [ "$clean_locale" = "zh-CN" ] || [ "$clean_locale" = "zh-Hans-CN" ] || [ "$clean_locale" = "zh-Hans" ]; then
        lang="zh-rCN"
        return 0
    elif [ "$clean_locale" = "zh-TW" ] || [ "$clean_locale" = "zh-Hant-TW" ] || [ "$clean_locale" = "zh-Hant" ]; then
        lang="zh-rTW"
        return 0

    # 3. Fallback to 2-letter prefix for folders like ru, tr, fr, id
    else
        local short_lang
        short_lang=$(echo "$clean_locale" | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
        if [ -d "$MODDIR/translations/$short_lang" ]; then
            lang="$short_lang"
            return 0
        fi
    fi
    return 1
}

# Step 1: user's selected locale list (first entry = preferred)
raw_lang=$(settings get system system_locales 2>/dev/null | cut -d',' -f1)
resolve_locale "$raw_lang" || :

# Step 2: persist.sys.locale
if [ -z "$lang" ]; then
    resolve_locale "$(getprop persist.sys.locale 2>/dev/null)" || :
fi

# Step 3: ro.product.locale
if [ -z "$lang" ]; then
    resolve_locale "$(getprop ro.product.locale 2>/dev/null)" || :
fi

# Step 4: cmd activity get-config (last resort; handles both "ru-rUA" and "mccXXX-mncXX-ru-rRU")
if [ -z "$lang" ]; then
    cfg=$(cmd activity get-config 2>/dev/null | grep -m1 '^config:' | sed 's/^config:[[:space:]]*//' | cut -d',' -f1)
    l=$(echo "$cfg" | tr '-' '\n' | grep -m1 -E '^[a-z]{2,3}$' || :)
    r=$(echo "$cfg" | tr '-' '\n' | grep -m1 -E '^r[A-Z]{2}$' | cut -c2- || :)
    resolve_locale "${l:+$l${r:+-$r}}" || :
fi

# Step 5: English fallback
lang=${lang:-en}

# --- We specify the correct path via install/ ---
if [ -n "$lang" ] && [ -f "$MODDIR/translations/$lang/strings.sh" ]; then
    . "$MODDIR/translations/$lang/strings.sh"
else
    [ -f "$MODDIR/strings.sh" ] && . "$MODDIR/strings.sh"
fi
# --------------------------------

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

# We are creating a new description
NEW_DESC="[accd ${STATUS}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | ${MODULE_DESC}"

# Update description only if it has actually changed (prevents infinite loops)
if [ -f "$PROP_FILE" ]; then
    CURRENT_DESC="$(grep '^description=' "$PROP_FILE" | cut -d= -f2-)"
    if [ "$CURRENT_DESC" != "$NEW_DESC" ]; then
        sed -i "s@^description=.*@description=${NEW_DESC}@" "$PROP_FILE"
    fi
else
    echo "$TXT_PROP_ERROR $PROP_FILE"
fi

echo "========================================"
