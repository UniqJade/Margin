#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-xcodegen.XXXXXX")

cleanup() {
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT

cd "$repository_root"
/bin/mkdir "$temporary_root/first" "$temporary_root/second"
xcodegen generate \
    --project "$temporary_root/first" \
    --project-root "$repository_root"
xcodegen generate \
    --project "$temporary_root/second" \
    --project-root "$repository_root"
/usr/bin/diff -ru \
    "$temporary_root/first/BooksTranslator.xcodeproj" \
    "$temporary_root/second/BooksTranslator.xcodeproj"

print "XcodeGen determinism check passed: consecutive generations are identical."
