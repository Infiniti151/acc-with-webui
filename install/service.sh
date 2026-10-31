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

# Подключаем локализацию (так как service.sh запускается из папки модуля)
    MODDIR="/data/adb/modules/acc"
    lang=$(cmd activity get-config 2>/dev/null | grep -m1 '^config:' | sed 's/^config:[[:space:]]*//' | cut -d',' -f1 | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]' | cut -c1-2)
    [ -z "$lang" ] && lang=$(getprop persist.sys.locale | cut -c1-2)
    [ -z "$lang" ] && lang=$(getprop ro.product.locale | cut -c1-2)

    if [ -n "$lang" ] && [ -f "$MODDIR/translations/$lang/strings.sh" ]; then
        . "$MODDIR/translations/$lang/strings.sh"
    else
        [ -f "$MODDIR/strings.sh" ] && . "$MODDIR/strings.sh"
    fi

    PROP_FILE="/data/adb/modules/acc/module.prop"

    if pgrep -f accd >/dev/null 2>&1; then
        STATUS="✅"
    else
        STATUS="❌"
    fi

# Get capacities for description update
eval "$(/dev/acc -sp capacity 2>/dev/null | grep -E '^(resume|pause|shutdown)_capacity=')"

# Формируем новое описание
NEW_DESC="[accd ${STATUS}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | ${MODULE_NAME}"

# Update description only if it has actually changed (prevents infinite loops)
if [ -f "$PROP_FILE" ]; then
    CURRENT_DESC="$(grep '^description=' "$PROP_FILE" | cut -d= -f2-)"
    if [ "$CURRENT_DESC" != "$NEW_DESC" ]; then
        sed -i "s@^description=.*@description=${NEW_DESC}@" "$PROP_FILE"
    fi
else
    echo "$TXT_PROP_ERROR $PROP_FILE"
fi
) &
# ------------------------------------------------

exec start-stop-daemon -bx $execDir/${id}d.sh -S -- "$@" || exit 12
