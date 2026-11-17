#!/usr/bin/env sh
# Push and Install Zip
# SPDX-FileCopyrightText: 2022-2024 VR25
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later
#
# usage: $0 [k] [adb device]
# k is for KaiOS

id=$(sed -n "s/^id=//p" module.prop)
version=$(sed -n '1s/### \(v[0-9.]*\).*/\1/p' changelog-webui.md)
versionCode=$(sed -n '1s/.*(\([0-9]*\)).*/\1/p' changelog-webui.md)
zip=${id}-with-webui_${version}_$versionCode
zip=$(echo _builds/$zip/$zip*zip)
dest=/sdcard/Download/acc-with-webui.zip

[ ".${1-}" != .k ] || {
  dest=/data/usbmsc_mnt/acc-with-webui.zip
  shift
}

one=${1-}

# Auto-select single connected ADB device if none was explicitly provided
if [ -z "${one-}" ]; then
  devs=$(adb devices 2>/dev/null | awk '$2 == "device" {print $1}')
  dev_count=0
  single_dev=""
  for d in $devs; do
    dev_count=$((dev_count + 1))
    single_dev="$d"
  done

  if [ "$dev_count" -eq 1 ]; then
    one="$single_dev"
    printf '\033[0;36m=> Auto-selected ADB device: %s\033[0m\n' "$one"
  elif [ "$dev_count" -eq 0 ]; then
    printf '\033[0;31m=> Error: No ADB devices connected.\033[0m\n' >&2
    exit 1
  else
    printf '\033[0;31m=> Error: Multiple ADB devices connected (%s found). Please specify a device serial.\033[0m\n' "$dev_count" >&2
    printf '\033[0;31m=> Usage: %s [k] [adb device]\033[0m\n' "$0" >&2
    exit 1
  fi
fi

_adb() {
  if [ -n "${one-}" ]; then
    adb -s $one "$@"
  else
    adb "$@"
  fi
}

if _adb shell su -c "which apd >/dev/null"; then
  install="apd module install $dest"
elif _adb shell su -c "which ksud >/dev/null"; then
  install="ksud module install $dest"
elif _adb shell su -c "which magisk >/dev/null"; then
  install="magisk --install-module $dest"
else
  install=
fi

[ -z "$install" ] || _adb push $zip $dest && _adb shell su -c "$install" || :
