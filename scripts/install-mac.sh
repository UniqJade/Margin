#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
local_config="$repository_root/Local.xcconfig"
derived_data="$repository_root/.build/XcodeDerivedData-Install.noindex"
built_app="$derived_data/Build/Products/Release/Margin.app"
install_app="$HOME/Applications/Margin.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

if [[ ! -f "$local_config" ]]; then
    print -u2 "Margin installation stopped: Local.xcconfig is missing."
    print -u2 "Copy Local.xcconfig.example to Local.xcconfig and restore the existing personal identifiers before installing."
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

typeset -A local_values
required_keys=(
    MARGIN_DEVELOPMENT_TEAM
    MARGIN_MAC_BUNDLE_ID
    MARGIN_IOS_BUNDLE_ID
    MARGIN_ACTION_BUNDLE_ID
    MARGIN_APP_GROUP_IDENTIFIER
    MARGIN_SHARED_KEYCHAIN_SUFFIX
    MARGIN_MAC_KEYCHAIN_SERVICE
)
for key in "${required_keys[@]}"; do
    value=$(read_local_setting "$key")
    if [[ -z "$value" || "$value" == *YOUR_* || "$value" == *dev.example* ]]; then
        print -u2 "Margin installation stopped: $key is missing or still uses a public placeholder in Local.xcconfig."
        exit 2
    fi
    local_values[$key]=$value
done

team_id=${local_values[MARGIN_DEVELOPMENT_TEAM]}
expected_bundle_id=${local_values[MARGIN_MAC_BUNDLE_ID]}
expected_keychain_service=${local_values[MARGIN_MAC_KEYCHAIN_SERVICE]}
if [[ ! "$team_id" =~ '^[A-Z0-9]{10}$' ]]; then
    print -u2 "Margin installation stopped: MARGIN_DEVELOPMENT_TEAM must be a 10-character Apple Team ID."
    exit 2
fi

identities=$(/usr/bin/security find-identity -v -p codesigning)
if [[ "$identities" != *"Apple Development:"* ]]; then
    print -u2 "Margin installation stopped: no valid Apple Development signing identity was found."
    print -u2 "Open Xcode > Settings > Accounts > your Apple Account > Manage Certificates, create Apple Development, then rerun this script."
    exit 2
fi

cd "$repository_root"
xcodegen generate
build_settings=$(xcodebuild \
    -project BooksTranslator.xcodeproj \
    -target BooksTranslatorMac \
    -configuration Release \
    -showBuildSettings)

read_build_setting() {
    local key=$1
    print -r -- "$build_settings" | /usr/bin/awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[^=]*=[[:space:]]*", "")
            print
            exit
        }
    '
}

effective_team=$(read_build_setting DEVELOPMENT_TEAM)
effective_bundle_id=$(read_build_setting PRODUCT_BUNDLE_IDENTIFIER)
effective_keychain_service=$(read_build_setting MARGIN_MAC_KEYCHAIN_SERVICE)
if [[ "$effective_team" != "$team_id" ||
      "$effective_bundle_id" != "$expected_bundle_id" ||
      "$effective_keychain_service" != "$expected_keychain_service" ]]; then
    print -u2 "Margin installation stopped: generated Mac identity does not match Local.xcconfig."
    print -u2 "Expected team/bundle/keychain: $team_id / $expected_bundle_id / $expected_keychain_service"
    print -u2 "Resolved team/bundle/keychain: $effective_team / $effective_bundle_id / $effective_keychain_service"
    exit 2
fi

xcodebuild \
    -project BooksTranslator.xcodeproj \
    -scheme BooksTranslatorMac \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    build

"$script_dir/verify-mac-app.sh" "$built_app"
"$script_dir/unregister-derived-margin.sh"

/usr/bin/pkill -x Margin >/dev/null 2>&1 || true
/bin/mkdir -p "$HOME/Applications"
if [[ -d "$install_app" ]]; then
    "$lsregister" -u "$install_app" >/dev/null 2>&1 || true
    /bin/rm -rf "$install_app"
fi
/usr/bin/ditto "$built_app" "$install_app"
"$script_dir/verify-mac-app.sh" "$install_app"
"$lsregister" -f "$install_app"
/usr/bin/open "$install_app"

installed_executable="$install_app/Contents/MacOS/Margin"
for _ in {1..50}; do
    for pid in $(/usr/bin/pgrep -x Margin 2>/dev/null); do
        command=$(/bin/ps -p "$pid" -o command=)
        if [[ "$command" == "$installed_executable" || "$command" == "$installed_executable "* ]]; then
            print "Margin installation: running the fixed app at $installed_executable"
            exit 0
        fi
    done
    /bin/sleep 0.1
done

print -u2 "Margin installation: installed successfully, but the running path could not be confirmed."
exit 1
