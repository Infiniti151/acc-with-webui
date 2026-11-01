#!/system/bin/sh
#
# $id Installer/Upgrader
# SPDX-FileCopyrightText: 2019-2024 VR25
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later
#
# devs: triple hashtags (###) mark non-generic code


# override the official Magisk module installer
SKIPUNZIP=1
SKIPMOUNT=false


echo
id=acc
domain=vr25
data_dir=/data/adb/$domain/${id}-data


# log
[ -z "${LINENO-}" ] || export PS4='$LINENO: '
mkdir -p $data_dir/logs
exec 2>$data_dir/logs/install.log
set -x


exxit() {
  local e=$?
  set +eu
  rm -rf /dev/.$domain.${id}-install
  $KSU || {
    rm -rf /data/adb/modules_update/$id
    (abort) > /dev/null
  }
  echo
  exit $e
} 2>/dev/null

trap exxit EXIT


# set up busybox
#BB#
bin_dir=/data/adb/vr25/bin
busybox_dir=/dev/.vr25/busybox
magisk_busybox="$(ls /data/adb/*/bin/busybox /data/adb/magisk/busybox 2>/dev/null || :)"
[ -x $busybox_dir/ls ] || {
  mkdir -p $busybox_dir
  chmod 0755 $busybox_dir $bin_dir/busybox 2>/dev/null || :
  for f in $bin_dir/busybox $magisk_busybox /system/*bin/busybox*; do
    [ -x $f ] && eval $f --install -s $busybox_dir/ && break || :
  done
  [ -x $busybox_dir/ls ] || {
    echo "Install busybox or simply place it in $bin_dir/"
    echo
    exit 3
  }
}
case $PATH in
  $bin_dir:*) ;;
  *) export PATH="$bin_dir:$busybox_dir:$PATH";;
esac
unset f bin_dir busybox_dir magisk_busybox
#/BB#


# root check
[ $(id -u) -ne 0 ] && {
  echo "$0 must run as root (su)"
  exit 4
}


get_prop() { sed -n "s|^$1=||p" ${2:-$srcDir/module.prop}; }

set_perms() {
  local owner=${2:-0}
  local perms=0644
  local target=
  target=$(readlink -f $1)
  if echo $target | grep -q '.*\.sh$' || [ -d $target ]; then perms=0755; fi
  chmod $perms $target
  chown $owner:$owner $target
  chcon u:object_r:system_file:s0 $target 2>/dev/null || :
}

set_perms_recursive() {
  local owner=${2-0}
  local target=
  find $1 2>/dev/null | while read target; do set_perms $target $owner; done
}

set -eu


# set source code directory
srcDir="$(cd "${0%/*}" 2>/dev/null || :; echo "$PWD")"

# extract flashable zip if source code is unavailable
[ -d $srcDir/install ] || {
  srcDir=/dev/.$domain.${id}-install
  rm -rf $srcDir 2>/dev/null || :
  mkdir $srcDir
  unzip "${APK:-${ZIPFILE:-$3}}" -d $srcDir/ >&2
}


name=$(get_prop name)
author=$(get_prop author)
version=$(get_prop version)
magiskModDir=/data/adb/modules
versionCode=$(get_prop versionCode)
accaFiles=/data/data/mattecarra.accapp/files ###
: ${installDir:=$accaFiles} ###
config=$data_dir/config.txt


# install in front-end's internal path by default
if [ "$installDir" != "$accaFiles" ]; then
  case "$installDir" in
    /data/data/*|/data/user/*)
      accaFiles="$installDir"
    ;;
  esac
fi


[ -d $magiskModDir ] && magisk=true || magisk=false
ls -d ${accaFiles%/*}* > /dev/null 2>&1 && acca=true || acca=false ###


# ensure AccA's files/ exists - to prevent unwanted downgrades ###
if $acca && [ ! -d $accaFiles ]; then
  if mkdir $accaFiles 2>/dev/null; then
    chown $(stat -c %u:%g ${accaFiles%/*}) $accaFiles
    chmod $(stat -c %a ${accaFiles%/*}) $accaFiles
    /system/bin/restorecon $accaFiles
  fi
fi


# check/change parent installation directory
! $magisk || installDir=$magiskModDir
[ $installDir != /data/adb/$domain ] || mkdir -p $installDir
[ -d $installDir ] || {
  installDir=/data/adb/$domain
  mkdir -p $installDir
}

lang=""

# Helper function to normalize and check if a locale folder exists
resolve_locale() {
    local candidate="$1"
    [ -z "$candidate" ] && return 1

    local clean_locale
    clean_locale=$(echo "$candidate" | tr '_' '-')

    # 1. Check for exact match first (e.g. de-DE, pt-PT)
    if [ -d "$srcDir/install/translations/$clean_locale" ]; then
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
        if [ -d "$srcDir/install/translations/$short_lang" ]; then
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
if [ -n "$lang" ] && [ -f "$srcDir/install/translations/$lang/strings.sh" ]; then
    . "$srcDir/install/translations/$lang/strings.sh"
else
    [ -f "$srcDir/install/strings.sh" ] && . "$srcDir/install/strings.sh"
fi
# --------------------------------

echo "- Detected language: '${lang:-default (en)}'"
echo ""

###
echo "$name $version ($versionCode)
Copyright 2017-2024, $(echo "$author" | cut -d',' -f1 | tr -d ' ')
Copyright 2026, $(echo "$author" | cut -d',' -f2 | tr -d ' ')
GPLv3+


$TXT_INSTALLING_IN $installDir/$id/..."


# backup
rm -rf $data_dir/backup 2>/dev/null || :
mkdir -p $data_dir/backup
cp -aH /data/adb/$domain/$id/* $config $data_dir/backup/ 2>/dev/null || :


export KSU=${KSU:-false}
$KSU || { [ ! -f /data/adb/*/bin/busybox ] || KSU=true; }
/system/bin/sh $srcDir/install/uninstall.sh install
mkdir -p $installDir/$id
cp -R $srcDir/install/* $installDir/$id/
installDir=$(readlink -f $installDir/$id)
cp $srcDir/module.prop $installDir/
cp -f $srcDir/README.* $data_dir/


# KaiOS patches
[ ! -d /data/usbmsc_mnt/ ] || {
  for i in $installDir/$id/*.sh; do
    sed -Ei 's#/sdcard(/|/Download/)#/data/usbmsc_mnt/#g' $i
  done
}


tmpd=/dev/.$domain/$id
mkdir -p $tmpd


###
! $magisk || {

  # create executable wrappers to avoid rebooting unnecessarily
  mkdir -p $installDir/system/bin

  for i in ${id}.sh:$id ${id}.sh:${id}d, ${id}.sh:${id}d. ${id}a.sh:${id}a service.sh:${id}d; do
    j=$installDir/system/bin/${i#*:}
    [ ! -h $j ] || rm $j
    echo "#!/system/bin/sh
#exec_wrapper
if [ -f $tmpd/.updated ]; then
  exec /dev/${i#*:} \"\$@\"
else
  exec . /data/adb/$domain/$id/${i%:*} \"\$@\"
fi" > $j
  done
}


###
if $acca; then

  ! $magisk || {

    ln -fs $installDir $accaFiles/

    # AccA post-uninstall cleanup script
    mkdir -p /data/adb/service.d || {
      rm /data/adb/service.d
      mkdir /data/adb/service.d
    }
    echo "#!/system/bin/sh
      # acc front-end post-uninstall cleanup script

      until test -d /sdcard/Android \\
        && test .\$(getprop sys.boot_completed) = .1
      do
        sleep 60
      done

      sleep 60

      [ -e $accaFiles/$id ] || rm -rf \$0 /data/adb/$domain/$id /data/adb/modules/$id 2>/dev/null

      exit 0" | sed 's/^      //' > /data/adb/service.d/${id}-cleanup.sh
    chmod 0755 /data/adb/service.d/${id}-cleanup.sh
  }
fi


[ $installDir = /data/adb/$domain/$id ] || {
  mkdir -p /data/adb/$domain
  ln -sf $installDir /data/adb/$domain/
}


# install binaries
cp -f $srcDir/bin/${id}-with-webui_flashable_uninstaller.zip $data_dir/


# Termux, fix shebang
termux=false
case "$installDir" in
  */com.termux*)
    termux=true
    for f in $installDir/*.sh; do
      ! grep -q '^#\!/.*/sh' $f \
        || sed -i 's|^#!/.*/sh|#!/data/data/com.termux/files/usr/bin/bash|' $f
    done
  ;;
esac


# set perms
case $installDir in
  /data/data/*|/data/user/*)
    set_perms_recursive $installDir $(stat -c %u ${installDir%/$id})

    # Termux:Boot
    ! $termux || {
      mkdir -p ${installDir%/*}/.termux/boot
      ln -sf $installDir/service.sh ${installDir%/*}/.termux/boot/${id}-init.sh
      chown -R $(stat -c %u:%g /data/data/com.termux) ${installDir%/*}/.termux
      /system/bin/restorecon -R ${installDir%/*}/.termux > /dev/null 2>&1 || :
    }
  ;;
  *)
    set_perms_recursive $installDir
    chmod 0755 $installDir/system/bin/* 2>/dev/null || :
  ;;
esac


! $KSU || {
  upModDir=${magiskModDir}_update
  rm -rf $upModDir/$id 2>/dev/null || :
  cp -a $installDir $upModDir/
  touch $installDir/update
}


set +eu
printf "$TXT_DONE\n\n\n"

printf "─────────────[ ACC ⚡ WebUI ]─────────────\n\n"

printf "\n\nCHANGELOG\n\n"
cat $srcDir/install/latest-release-notes.md

_echo() {
  echo "$@" | tee -a $tmpd/.install-notes
}

printf "\n\n"
printf "$version ($versionCode) $TXT_INSTALLED_RUNNING\n\n" | tee $tmpd/.install-notes
if [ -x /sbin/${id}d ] || grep -q '#exec_wrapper' /system/bin/${id}d 2>/dev/null; then
  _echo "$TXT_REBOOT_UNNECESSARY"
else
  _echo "$TXT_REBOOT_NOTE"
fi


case $installDir in
  /data/adb/modules*) ;;
  *) $KSU || echo "
$TXT_NON_MAGISK_NOTICE";;
esac


# initialize $id
rm $data_dir/disable 2>/dev/null
/data/adb/$domain/$id/service.sh --init


# magic_overlayfs support

OVERLAY_IMAGE_EXTRA=0     # number of kb need to be added to overlay.img
OVERLAY_IMAGE_SHRINK=true # shrink overlay.img or not?

# only use OverlayFS if Magisk_OverlayFS is installed
if [ -f "/data/adb/modules/magisk_overlayfs/util_functions.sh" ] && \
    /data/adb/modules/magisk_overlayfs/overlayfs_system --test; then
  ui_print ""
  ui_print "$TXT_OVERLAY_SUPPORT"
  . /data/adb/modules/magisk_overlayfs/util_functions.sh
  support_overlayfs && rm -rf "$MODPATH"/system
fi

exit 0
