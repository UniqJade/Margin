#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
local_config="$repository_root/Local.xcconfig"
app=${1:-}

if [[ ! -f "$local_config" ]]; then
    print -u2 "Margin verification stopped: Local.xcconfig is missing."
    exit 2
fi

read_local_setting() {
    local key=$1
    /usr/bin/awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[^=]*=[[:space:]]*", "")
            value=$0
        }
        END { print value }
    ' "$local_config"
}

expected_team_id=$(read_local_setting MARGIN_DEVELOPMENT_TEAM)
expected_bundle_id=$(read_local_setting MARGIN_MAC_BUNDLE_ID)
expected_keychain_service=$(read_local_setting MARGIN_MAC_KEYCHAIN_SERVICE)
for value in "$expected_team_id" "$expected_bundle_id" "$expected_keychain_service"; do
    if [[ -z "$value" || "$value" == *YOUR_* || "$value" == *dev.example* ]]; then
        print -u2 "Margin verification stopped: Local.xcconfig does not contain a complete personal Mac identity."
        exit 2
    fi
done

if [[ -z "$app" || ! -d "$app" ]]; then
    print -u2 "Usage: $0 /path/to/Margin.app"
    exit 2
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
signature=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
keychain_service=$(/usr/libexec/PlistBuddy -c "Print :MarginMacKeychainService" "$app/Contents/Info.plist")

if [[ "$bundle_id" != "$expected_bundle_id" ]]; then
    print -u2 "Margin verification: expected bundle ID $expected_bundle_id, found $bundle_id."
    exit 1
fi
if [[ "$keychain_service" != "$expected_keychain_service" ]]; then
    print -u2 "Margin verification: expected Keychain service $expected_keychain_service, found $keychain_service."
    exit 1
fi
if [[ "$signature" != *"Authority=Apple Development:"* ]]; then
    print -u2 "Margin verification: the app is not signed by an Apple Development certificate."
    exit 1
fi
if [[ "$signature" != *"TeamIdentifier=$expected_team_id"* ]]; then
    print -u2 "Margin verification: expected team $expected_team_id."
    exit 1
fi

entitlements=$(/usr/bin/codesign -d --entitlements :- "$app" 2>/dev/null || true)
for forbidden in \
    com.apple.security.app-sandbox \
    com.apple.security.application-groups \
    keychain-access-groups; do
    if [[ "$entitlements" == *"<key>$forbidden</key>"* ]]; then
        print -u2 "Margin verification: forbidden macOS entitlement present: $forbidden"
        exit 1
    fi
done

print "Margin verification: signature, team, bundle ID, and capabilities are correct."
