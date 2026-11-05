
#!/system/bin/sh
#
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later

# Resolve an Android locale to an existing ACC translation directory
resolve_locale() {
    local moddir="$1"
    local candidate="$2"
    [ -z "$candidate" ] && return 1

    local clean_locale
    clean_locale=$(printf '%s' "$candidate" | tr '_' '-')

    # 1. Exact match (e.g. de-DE, pt-PT)
    if [ -d "$moddir/translations/$clean_locale" ]; then
        printf '%s\n' "$clean_locale"
        return 0

    # 2. Chinese variants
    elif [ "$clean_locale" = "zh-CN" ] ||
         [ "$clean_locale" = "zh-Hans-CN" ] ||
         [ "$clean_locale" = "zh-Hans" ]; then
        printf '%s\n' "zh-rCN"
        return 0

    elif [ "$clean_locale" = "zh-TW" ] ||
         [ "$clean_locale" = "zh-Hant-TW" ] ||
         [ "$clean_locale" = "zh-Hant" ]; then
        printf '%s\n' "zh-rTW"
        return 0

    # 3. Two-letter language fallback
    else
        local short_lang
        short_lang=$(printf '%s' "$clean_locale" |
            cut -d'-' -f1 |
            tr '[:upper:]' '[:lower:]')

        if [ -d "$moddir/translations/$short_lang" ]; then
            printf '%s\n' "$short_lang"
            return 0
        fi
    fi

    return 1
}

# Detect the preferred system language
get_lang() {
    local moddir="$1"
    local lang="" candidate="" cfg="" l="" r=""

    # Step 1: User-selected locale list (first entry = preferred)
    candidate=$(settings get system system_locales 2>/dev/null |
        cut -d',' -f1)

    lang=$(resolve_locale "$moddir" "$candidate") || lang=""

    # Step 2: persist.sys.locale
    if [ -z "$lang" ]; then
        candidate=$(getprop persist.sys.locale 2>/dev/null)
        lang=$(resolve_locale "$moddir" "$candidate") || lang=""
    fi

    # Step 3: ro.product.locale
    if [ -z "$lang" ]; then
        candidate=$(getprop ro.product.locale 2>/dev/null)
        lang=$(resolve_locale "$moddir" "$candidate") || lang=""
    fi

    # Step 4: cmd activity get-config (last resort)
    if [ -z "$lang" ]; then
        cfg=$(cmd activity get-config 2>/dev/null |
            grep -m1 '^config:' |
            sed 's/^config:[[:space:]]*//' |
            cut -d',' -f1)

        l=$(printf '%s' "$cfg" |
            tr '-' '\n' |
            grep -m1 -E '^[a-z]{2,3}$' || :)

        r=$(printf '%s' "$cfg" |
            tr '-' '\n' |
            grep -m1 -E '^r[A-Z]{2}$' |
            cut -c2- || :)

        candidate="${l:+$l${r:+-$r}}"
        lang=$(resolve_locale "$moddir" "$candidate") || lang=""
    fi

    # Step 5: English fallback
    printf '%s\n' "${lang:-en}"
}

# Detect language and load shell translations
load_translations() {
    local moddir="$1"

    lang=$(get_lang "$moddir")

    # Load English defaults first
    if [ -f "$moddir/strings.sh" ]; then
        . "$moddir/strings.sh"
    else
        echo "Error: English translations not found: $moddir/strings.sh" >&2
        return 1
    fi

    # Override with selected locale
    if [ "$lang" != "en" ] &&
       [ -f "$moddir/translations/$lang/strings.sh" ]; then
        . "$moddir/translations/$lang/strings.sh"
    fi

    export lang
}

# Update ACC module description with daemon status and capacities
update_module_description() {
    local status="$1"
    local prop_file="${2:-/data/adb/modules/acc/module.prop}"
    local capacities new_desc current_desc

    # Get charging capacities
    capacities=$(/dev/acc -sp capacity 2>/dev/null |
        grep -E '^(resume|pause|shutdown)_capacity=')

    eval "$capacities"

    # Build the new description
    new_desc="[accd ${status}] | 🟢 ${resume_capacity}% | 🟡 ${pause_capacity}% | 🔴 ${shutdown_capacity}% | ${MODULE_DESC}"

    # Update only if the description has changed
    if [ -f "$prop_file" ]; then
        current_desc=$(sed -n 's/^description=//p' "$prop_file")

        if [ "$current_desc" != "$new_desc" ]; then
            sed -i "s@^description=.*@description=${new_desc}@" "$prop_file"
        fi
    else
        echo "$TXT_PROP_ERROR $prop_file"
        return 1
    fi
}

