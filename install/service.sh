#!/system/bin/sh
# $id initializer
# Copyright 2017-2021, VR25
# Copyright 2026, Infiniti151
# License: GPLv3+

id=acc
domain=vr25
TMPDIR=/dev/.$domain/$id
execDir=/data/adb/$domain/$id
dataDir=/data/adb/$domain/${id}-data

[ -f $execDir/disable -o -f $dataDir/disable ] && exit 14

# wait til the lock screen is ready and give some bootloop grace period
slept=false
until [ .$(getprop init.svc.bootanim 2>/dev/null) = .stopped ]; do
  [ -f $execDir/disable -o -f $dataDir/disable ] && exit 14
  sleep 10 && slept=true
done
$slept && sleep 60
unset slept

mkdir -p $TMPDIR $dataDir
export dataDir domain execDir id TMPDIR
. $execDir/setup-busybox.sh
. $execDir/release-lock.sh
[ ".$1" = .-x ] && touch $dataDir/disable

# --- ACC WebUI: Dynamic Description Boot Sync ---
(
    sleep 3
    PROP_FILE="/data/adb/modules/acc/module.prop"

    if pgrep -f accd >/dev/null 2>&1; then
        STATUS="✅"
    else
        STATUS="❌"
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
) &
# ------------------------------------------------

exec start-stop-daemon -bx $execDir/${id}d.sh -S -- "$@" || exit 12
