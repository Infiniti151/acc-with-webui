#!/usr/bin/env bash
#
# Installation Archives Builder
# SPDX-FileCopyrightText: 2018-2024 VR25
# SPDX-FileCopyrightText: 2026 Infiniti151
# SPDX-License-Identifier: GPL-3.0-or-later
#
# usage: $0 [any_random_arg]
#   e.g.,
#     build.sh (builds $id and generates installable archives)
#     build.sh any_random_arg (only builds $id)
#     build.sh -W|--webui (only builds the WebUI)

# Bash built-in escape handling for colors
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

# Ensure script runs in its directory
cd "${0%/*}" 2>/dev/null || exit 1

# shellcheck disable=SC1091
source ./check-syntax.sh || exit $?

add_header() {
  local color="${2:-$CYAN}"
  echo "${color}--------------------------------------------------${NC}"
  echo "${color}$1${NC}"
  echo "${color}--------------------------------------------------${NC}"
  echo
}

set_prop() {
  sed -i -e "s/^($1=.*/($1=$2/" -e "s/^$1=.*/$1=$2/" \
    "${3:-module.prop}" 2>/dev/null
}

get_prop() {
  sed -n "s/^$1=//p" "${2:-module.prop}" 2>/dev/null
}

getVersionCode() {
    # Accept version string as argument ($1) or read from changelog-webui.md
    local ver="${1:-}"

    if [ -z "$ver" ]; then
        if [ -f "changelog-webui.md" ]; then
            ver=$(sed -n '1s/### \(v[0-9.]*\).*/\1/p' changelog-webui.md)
        elif [ -f "module.prop" ]; then
            ver=$(sed -n 's/^version=//p' module.prop)
        fi
    fi

    # Strip leading 'v' if present (e.g., "v1.1.1" -> "1.1.1")
    ver="${ver#v}"

    # Return 0 if no version could be resolved
    if [ -z "$ver" ]; then
        echo "0"
        return 1
    fi

    # Split MAJOR.MINOR.PATCH cleanly
    local major=0 minor=0 patch=0
    IFS='.' read -r major minor patch <<EOF
$ver
EOF

    # Default empty patch values to 0
    patch="${patch:-0}"

    # Calculate 5-digit versionCode: (MAJOR * 10000) + (MINOR * 100) + PATCH
    local version_code=$(( (major * 10000) + (minor * 100) + patch ))

    echo "$version_code"
}

build_webui() {
  add_header "Building WebUI..."

  # update version and acc_version in package.json
  sed -i -E \
  -e "s/(\"version\": *\")[^\"]*(\")/\1${version#v}\2/" \
  -e "s/(\"acc_version\": *\")[^\"]*(\")/\1${acc_version}\2/" \
  webui/package.json

  # Run deploy or standard build
  if [ "$DEPLOY_WEBUI_ONLY" = true ]; then
    (npm install --prefix=webui && npm run deploy --prefix=webui) || exit $?
  else
    (npm install --prefix=webui && npm run build --prefix=webui) || exit $?
  fi
}

BUILD_WEBUI_ONLY=false
DEPLOY_WEBUI_ONLY=false
SKIP_ARCHIVES=false

for arg in "$@"; do
  case $arg in
    -w|--webui) BUILD_WEBUI_ONLY=true ;; # Runs standard clean build for CI/CD
    -d|--deploy) DEPLOY_WEBUI_ONLY=true ;; # Runs the Vite build + ADB push plugin
    *) SKIP_ARCHIVES=true ;;
  esac
done

id=$(get_prop id)
domain=$(get_prop domain)
version=$(sed -n '1s/### \(v[0-9.]*\).*/\1/p' changelog-webui.md)
acc_version=$(sed -n '/^### v/{n;s/^`ACC: //;s/`$//;p;q}' changelog-webui.md)
versionCode=$(getVersionCode "$version")
basename="${id}-with-webui_${version}_${versionCode}"
tmpDir=".tmp/META-INF/com/google/android"

if [[ "$BUILD_WEBUI_ONLY" == true || "$DEPLOY_WEBUI_ONLY" == true ]]; then
  build_webui
  add_header "Done" "$GREEN"
  exit 0
fi

add_header "Updating module.json..."

# update module info
if [[ "$(get_prop version)" != "$version" ]]; then
  set_prop version "$version (ACC: $acc_version)"
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
    "changelog": "https://raw.githubusercontent.com/Infiniti151/acc-with-webui/dev/install/latest-release-notes.md"
}
EOF
fi

add_header "Updating latest-release-notes.md..."

sed -i -E "1s/^(### v[0-9.]+).*/\1 (${versionCode}) - $(date +%Y-%m-%d)/" changelog-webui.md

awk '
  NR==1 && /^###/ { print; next }
  /^###/ { exit }
  { print }
' changelog-webui.md > install/latest-release-notes.md

build_webui

add_header "Updating ID and domain in install scripts..."

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

add_header "Updating README.md and Generating README.html..."

# Update Svelte version badge
SVELTE_VERSION=$(grep '"svelte"' webui/package.json | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
sed -i "s/Svelte-[0-9.]*-orange/Svelte-${SVELTE_VERSION}-orange/g" README.md

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

add_header "Updating busybox config in install scripts..."

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

add_header "Building uninstaller zip..."

[[ ! -f customize.sh ]] || ! cmp -s install.sh customize.sh && cp install.sh customize.sh

[[ ! -f META-INF/com/google/android/update-binary ]] || ! cmp -s install.sh META-INF/com/google/android/update-binary && cp install.sh META-INF/com/google/android/update-binary

if [[ bin/${id}-with-webui_flashable_uninstaller.zip -ot install/uninstall.sh ]] || [[ ! -f bin/${id}-with-webui_flashable_uninstaller.zip ]]; then
  # generate $id-with-webui uninstaller flashable zip
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

if [[ "$SKIP_ARCHIVES" == false ]]; then

  # cleanup
  rm -rf "_builds/${basename:?}/" 2>/dev/null
  mkdir -p "_builds/${basename}/${basename}"

  cp "bin/${id}-with-webui_flashable_uninstaller.zip" install-online.sh install-tarball.sh "_builds/${basename}/"

  add_header "Building installable archives..."

  case $version in
    *-*) basename_="${basename}_$(date +%H%M)" ;;
    *)   basename_="$basename" ;;
  esac

  echo "=> _builds/${basename}/${basename_}.zip"
  zip -r9 "_builds/${basename}/${basename_}.zip" \
    customize.sh META-INF/ bin/ \
    install/ module.prop README.html \
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

  add_header "Done" "$GREEN"
fi

exit 0
