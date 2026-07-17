#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}

cleanup() {
    "$script_dir/unregister-derived-margin.sh"
}
trap cleanup EXIT

cd "$repository_root"
xcodegen generate
xcodebuild \
    -project BooksTranslator.xcodeproj \
    -scheme BooksTranslatorMac \
    -configuration Debug \
    -derivedDataPath .build/XcodeDerivedData-Mac.noindex \
    CODE_SIGNING_ALLOWED=NO \
    test
