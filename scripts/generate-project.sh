#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-project-generation.XXXXXX")
stable_root="$temporary_root/Margin"
generated_project="$stable_root/BooksTranslator.xcodeproj"
destination_project="$repository_root/BooksTranslator.xcodeproj"

cleanup() {
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "Margin project generation stopped: xcodegen is not installed."
    exit 2
fi

/bin/mkdir "$stable_root"
for item in project.yml Package.swift Apps Assets Config Resources Sources Tests; do
    /bin/ln -s "$repository_root/$item" "$stable_root/$item"
done

(
    cd "$stable_root"
    xcodegen generate
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
