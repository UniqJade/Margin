#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
xcodegen_version=2.45.4
xcodegen_sha256=090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef
xcodegen_url="https://github.com/yonaskolb/XcodeGen/releases/download/${xcodegen_version}/xcodegen.zip"
install_root=${MARGIN_XCODEGEN_INSTALL_ROOT:-"$repository_root/.build/tooling/xcodegen-$xcodegen_version"}
xcodegen_binary="$install_root/bin/xcodegen"

if [[ -x "$xcodegen_binary" ]] \
    && [[ "$("$xcodegen_binary" --version)" == "Version: $xcodegen_version" ]]; then
    print -r -- "$xcodegen_binary"
    exit 0
fi

temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-xcodegen-install.XXXXXX")
archive_path="$temporary_root/xcodegen.zip"
extract_root="$temporary_root/extract"
staging_root="$temporary_root/install"

cleanup() {
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

/usr/bin/curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --output "$archive_path" \
    "$xcodegen_url"

actual_sha256=$(/usr/bin/shasum -a 256 "$archive_path")
actual_sha256=${actual_sha256%% *}
if [[ "$actual_sha256" != "$xcodegen_sha256" ]]; then
    print -u2 "Margin XcodeGen install stopped: archive SHA-256 did not match."
    exit 1
fi

/bin/mkdir -p "$extract_root" "$staging_root" "$install_root"
/usr/bin/ditto -x -k "$archive_path" "$extract_root"
PREFIX="$staging_root" /bin/bash "$extract_root/xcodegen/install.sh"
/usr/bin/ditto "$staging_root" "$install_root"

if [[ ! -x "$xcodegen_binary" ]] \
    || [[ "$("$xcodegen_binary" --version)" != "Version: $xcodegen_version" ]]; then
    print -u2 "Margin XcodeGen install stopped: installed binary failed version verification."
    exit 1
fi

print -r -- "$xcodegen_binary"
