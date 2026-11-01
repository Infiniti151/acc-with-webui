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

# We enable localization (since service.sh is launched from the module folder)
    MODDIR="/data/adb/modules/acc"
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

    PROP_FILE="/data/adb/modules/acc/module.prop"

    if pgrep -f accd >/dev/null 2>&1; then
        STATUS="✅"
    else
        STATUS="❌"
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
) &
# ------------------------------------------------

exec start-stop-daemon -bx $execDir/${id}d.sh -S -- "$@" || exit 12
