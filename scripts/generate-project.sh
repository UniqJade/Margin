#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
expected_xcodegen_version=2.45.4
pinned_xcodegen="$repository_root/.build/tooling/xcodegen-$expected_xcodegen_version/bin/xcodegen"
temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-project-generation.XXXXXX")
stable_root="$temporary_root/Margin"
generated_project="$stable_root/BooksTranslator.xcodeproj"
destination_project="$repository_root/BooksTranslator.xcodeproj"

cleanup() {
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

if [[ -x "$pinned_xcodegen" ]]; then
    xcodegen_command=$pinned_xcodegen
elif command -v xcodegen >/dev/null 2>&1; then
    xcodegen_command=$(command -v xcodegen)
else
    print -u2 "Margin project generation stopped: XcodeGen is not installed."
    print -u2 "Run ./scripts/install-xcodegen.sh to install the pinned release."
    exit 2
fi

xcodegen_version=$("$xcodegen_command" --version)
if [[ "$xcodegen_version" != "Version: $expected_xcodegen_version" ]]; then
    print -u2 "Margin project generation stopped: expected XcodeGen $expected_xcodegen_version, got $xcodegen_version."
    print -u2 "Run ./scripts/install-xcodegen.sh to install the pinned release."
    exit 2
fi

/bin/mkdir "$stable_root"
for item in project.yml Package.swift Apps Assets Config Resources Sources Tests; do
    /bin/ln -s "$repository_root/$item" "$stable_root/$item"
done

(
    cd "$stable_root"
    "$xcodegen_command" generate
)

if [[ ! -f "$generated_project/project.pbxproj" ]]; then
    print -u2 "Margin project generation stopped: XcodeGen did not produce BooksTranslator.xcodeproj."
    exit 1
fi

/bin/mkdir -p "$destination_project"
/usr/bin/rsync \
    --archive \
    --delete \
    --exclude '/xcuserdata/' \
    --exclude '/project.xcworkspace/xcuserdata/' \
    --exclude '/project.xcworkspace/xcshareddata/' \
    "$generated_project/" \
    "$destination_project/"

print "Margin project generation completed with stable checkout-independent metadata."
