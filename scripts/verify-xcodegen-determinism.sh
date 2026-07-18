#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-xcodegen.XXXXXX")

cleanup() {
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

remove_xcode_runtime_metadata() {
    local project_copy=$1
    /bin/rm -rf -- \
        "$project_copy/xcuserdata" \
        "$project_copy/project.xcworkspace/xcuserdata" \
        "$project_copy/project.xcworkspace/xcshareddata"
}

cd "$repository_root"
/bin/cp -R "$repository_root/BooksTranslator.xcodeproj" "$temporary_root/before"
remove_xcode_runtime_metadata "$temporary_root/before"

"$script_dir/generate-project.sh"
/bin/cp -R "$repository_root/BooksTranslator.xcodeproj" "$temporary_root/after-first"
remove_xcode_runtime_metadata "$temporary_root/after-first"

"$script_dir/generate-project.sh"
/bin/cp -R "$repository_root/BooksTranslator.xcodeproj" "$temporary_root/after-second"
remove_xcode_runtime_metadata "$temporary_root/after-second"

/usr/bin/diff -ru \
    "$temporary_root/before" \
    "$temporary_root/after-first"
/usr/bin/diff -ru \
    "$temporary_root/after-first" \
    "$temporary_root/after-second"

if ! /usr/bin/grep -Fq \
    'name = Margin; path = .; sourceTree = SOURCE_ROOT;' \
    "$repository_root/BooksTranslator.xcodeproj/project.pbxproj"; then
    print -u2 "XcodeGen determinism check failed: the local package does not use stable Margin metadata."
    exit 1
fi

print "XcodeGen determinism check passed: the checked-in project and consecutive generations are identical."
