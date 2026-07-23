#!/usr/bin/env bash
# Installation Archives Builder
# Copyright 2018-2024, VR25
# Copyright 2026, Infiniti151
# License: GPLv3+
#
# usage: $0 [any_random_arg]
#   e.g.,
#     build.sh (builds $id and generates installable archives)
#     build.sh any_random_arg (only builds $id)

# Bash built-in escape handling for colors
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

# Ensure script runs in its directory
cd "${0%/*}" 2>/dev/null || exit 1

# shellcheck disable=SC1091
source ./check-syntax.sh || exit $?

set_prop() {
  sed -i -e "s/^($1=.*/($1=$2/" -e "s/^$1=.*/$1=$2/" \
    "${3:-module.prop}" 2>/dev/null
}

get_prop() {
  sed -n "s/^$1=//p" "${2:-module.prop}" 2>/dev/null
}

id=$(get_prop id)
domain=$(get_prop domain)
version=$(sed -n '1s/### \(v[0-9.]*\).*/\1/p' changelog-webui.md)
versionCode=$(sed -n '1s/.*(\([0-9]*\)).*/\1/p' changelog-webui.md)
basename="${id}-with-webui_${version}_${versionCode}"
tmpDir=".tmp/META-INF/com/google/android"

echo "${CYAN}--------------------------------------------------"
echo "Updating module.json..."
echo "${CYAN}--------------------------------------------------${NC}"
echo

# update module info
if [[ "$(get_prop version)" != "$version" ]]; then
  set_prop version "$version"
  set_prop versionCode "$versionCode"
  cat << EOF > module.json
{
    "busybox": "https://github.com/Magisk-Modules-Repo/busybox-ndk",
    "curl": "https://github.com/Zackptg5/Cross-Compiled-Binaries-Android/tree/master/curl",
    "onlineInstaller": "https://github.com/Infiniti151/acc-with-webui/releases/download/${version}/install-online.sh",
    "tgz": "https://github.com/Infiniti151/acc-with-webui/releases/download/${version}/${basename}.tgz",
    "tgzInstaller": "https://github.com/Infiniti151/acc-with-webui/releases/download/${version}/install-tarball.sh",
    "version": "${version}",
    "versionCode": ${versionCode},
    "zipUrl": "https://github.com/Infiniti151/acc-with-webui/releases/download/${version}/${basename}.zip",
    "changelog": "https://raw.githubusercontent.com/Infiniti151/acc-with-webui/dev/changelog-webui.md"
}
EOF
fi

echo "${CYAN}--------------------------------------------------"
echo "Building WebUI..."
echo "${CYAN}--------------------------------------------------${NC}"

# update package.json version and build WebUI
sed -i -E "s/(\"version\": *\")[^\"]*(\")/\1${version#v}\2/" webui/package.json
(npm install --prefix=webui && npm run build --prefix=webui) || exit $?

echo "${CYAN}--------------------------------------------------"
echo "Updating ID and domain in install scripts..."
echo "${CYAN}--------------------------------------------------${NC}"
echo

for file in ./install*.sh ./install/*.sh ./bundle.sh; do
  if [[ -f "$file" ]] && grep -Eq '(^|\()id=' "$file"; then
    grep -Eq "(^|\()id=$id" "$file" || set_prop id "$id" "$file"
  fi
done

# set domain
for file in ./install*.sh ./install/*.sh ./bundle.sh; do
  if [[ -f "$file" ]] && grep -Eq '(^|\()domain=' "$file"; then
    grep -Eq "(^|\()domain=$domain" "$file" || set_prop domain "$domain" "$file"
  fi
done

echo "${CYAN}--------------------------------------------------"
echo "Generating README.html..."
echo "${CYAN}--------------------------------------------------${NC}"
echo

if [[ README.md -ot install/default-config.txt ]] \
  || [[ README.md -ot install/strings.sh ]] \
  || [[ README.md -nt README.html ]]
then
  # default config
  set -e
  { sed -n '1,/#DC#/p' README.md; echo; cat install/default-config.txt; \
    echo; sed -n '/^#\/DC#/,$p' README.md; } > README.md.tmp

  # terminal commands
  { sed -n '1,/#TC#/p' README.md.tmp; \
    echo; # shellcheck disable=SC1091
    source ./install/strings.sh; print_help; \
    echo; sed -n '/^#\/TC#/,$p' README.md.tmp; } > README.md
  rm -f README.md.tmp
  set +e
  markdown README.md > README.html 2>/dev/null || :
fi

echo "${CYAN}--------------------------------------------------"
echo "Updating busybox config in install scripts..."
echo "${CYAN}--------------------------------------------------${NC}"
echo

# update busybox config (from install/setup-busybox.sh) in install/uninstall.sh and install scripts
set -e
for file in ./install/uninstall.sh ./install*.sh; do
  if [[ "$file" -ot install/setup-busybox.sh ]]; then
    { sed -n '1,/#BB#/p' "$file"; \
      grep -Ev '^$|^#' install/setup-busybox.sh; \
      sed -n '/^#\/BB#/,$p' "$file"; } > "${file}.tmp"
    mv -f "${file}.tmp" "$file"
  fi
done
set +e

echo "${CYAN}--------------------------------------------------"
echo "Building uninstaller zip..."
echo "${CYAN}--------------------------------------------------${NC}"
echo

{ cp -u install.sh customize.sh
  cp -u install.sh META-INF/com/google/android/update-binary; } 2>/dev/null

if [[ bin/${id}-with-webui_flashable_uninstaller.zip -ot install/uninstall.sh ]] || [[ ! -f bin/${id}-with-webui_flashable_uninstaller.zip ]]; then
  # generate $id uninstaller flashable zip
  echo "=> bin/${id}-with-webui_flashable_uninstaller.zip"
  rm -rf "bin/${id}-with-webui_flashable_uninstaller.zip" "$tmpDir" 2>/dev/null
  mkdir -p bin "$tmpDir"
  sed 's|#!/system/bin/sh|#!/sbin/sh|' install/uninstall.sh > "$tmpDir/update-binary"
  echo "#MAGISK" > "$tmpDir/updater-script"
  (cd .tmp && zip -r9 "../bin/${id}-with-webui_flashable_uninstaller.zip" ./* \
    | sed 's|.*adding: ||' | grep -iv 'zip warning:')
  rm -rf .tmp
  echo
fi

if [[ -z "$1" ]]; then

  # cleanup
  rm -rf "_builds/${basename:?}/" 2>/dev/null
  mkdir -p "_builds/${basename}/${basename}"

  cp "bin/${id}-with-webui_flashable_uninstaller.zip" install-online.sh install-tarball.sh "_builds/${basename}/"

  echo "${CYAN}--------------------------------------------------"
  echo "Building installable archives..."
  echo "${CYAN}--------------------------------------------------${NC}"
  echo

  case $version in
    *-*) basename_="${basename}_$(date +%H%M)" ;;
    *)   basename_="$basename" ;;
  esac

  echo "=> _builds/${basename}/${basename_}.zip"
  zip -r9 "_builds/${basename}/${basename_}.zip" \
    ./* .gitattributes .gitignore .github \
    -x _\*/\* "images/*" "webui/*" \
    | sed 's|.*adding: ||' | grep -iv 'zip warning:'
  echo

  # prepare files to be included in $id installable tarball
  cp -R install install.sh License.md README.* module.prop bin/ \
    "_builds/${basename}/${basename}/" 2>&1 \
    | grep -iv "can't preserve"

  # generate $id installable tarball
  cd "_builds/${basename}" || exit 1
  echo "=> _builds/${basename}/${basename}.tgz"
  tar -cvf - "${basename}" | gzip -9 > "${basename}.tgz"
  rm -rf "${basename:?}/"
  echo

  echo "${GREEN}--------------------------------------------------"
  echo "Done"
  echo "${GREEN}--------------------------------------------------${NC}"
  echo
fi

exit 0
