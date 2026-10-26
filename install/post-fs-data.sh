#!/system/bin/sh
#
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later

# Boot: assume accd is down until service.sh proves otherwise
MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
[ -f "$PROP_FILE" ] && sed -i 's/^description=\[accd [^]]*\]/description=[accd ❌]/' "$PROP_FILE"
