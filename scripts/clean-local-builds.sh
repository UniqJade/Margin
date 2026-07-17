#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
xcode_derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
include_xcode_derived_data=false

usage() {
    print "Usage: $0 [--xcode-derived-data]"
    print ""
    print "By default, removes only this repository's .build and DerivedData directories."
    print "With --xcode-derived-data, also removes BooksTranslator-* directories from Xcode DerivedData."
}

while (( $# > 0 )); do
    case "$1" in
        --xcode-derived-data)
            include_xcode_derived_data=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 "Margin cleanup: unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

typeset -a repository_targets
repository_targets=(
    "$repository_root/.build"
    "$repository_root/DerivedData"
)

typeset -a xcode_targets
if [[ "$include_xcode_derived_data" == true && -d "$xcode_derived_data_root" ]]; then
    xcode_targets=("$xcode_derived_data_root"/BooksTranslator-*(N))
fi

typeset -a unregister_roots
unregister_roots=("${repository_targets[@]}" "${xcode_targets[@]}")
"$script_dir/unregister-derived-margin.sh" "${unregister_roots[@]}"

remove_repository_target() {
    local target=$1
    case "$target" in
        "$repository_root/.build"|"$repository_root/DerivedData")
            ;;
        *)
            print -u2 "Margin cleanup refused unexpected repository path: $target"
            exit 1
            ;;
    esac
    if [[ -e "$target" || -L "$target" ]]; then
        /bin/rm -rf -- "$target"
        print "Margin cleanup: removed $target"
    fi
}

remove_xcode_target() {
    local target=$1
    local parent=${target:h}
    local name=${target:t}
    if [[ "$parent" != "$xcode_derived_data_root" || "$name" != BooksTranslator-* ]]; then
        print -u2 "Margin cleanup refused unexpected Xcode DerivedData path: $target"
        exit 1
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        /bin/rm -rf -- "$target"
        print "Margin cleanup: removed $target"
    fi
}

for target in "${repository_targets[@]}"; do
    remove_repository_target "$target"
done
for target in "${xcode_targets[@]}"; do
    remove_xcode_target "$target"
done

print "Margin cleanup: local build cleanup complete. Installed apps, app data, Keychain, and shared ModuleCache were not touched."
