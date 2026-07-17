#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
lsregister=${MARGIN_LSREGISTER_PATH:-/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister}

if [[ ! -x "$lsregister" ]]; then
    print -u2 "Margin cleanup: LaunchServices registration tool is unavailable."
    exit 1
fi

typeset -a search_roots
if (( $# > 0 )); then
    search_roots=("$@")
else
    common_git_dir=$(/usr/bin/git -C "$repository_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [[ -n "$common_git_dir" ]]; then
        workspace_root=${common_git_dir:h}
    else
        workspace_root=$repository_root
    fi
    search_roots=(
        "$workspace_root"
        "$repository_root"
        "$HOME/Library/Developer/Xcode/DerivedData"
    )
fi

typeset -A seen
unregistered=0

unregister_app() {
    local app=$1
    case "$app" in
        "$HOME/Applications/Margin.app")
            return 0
            ;;
        *"/DerivedData/"*|*"/.build/"*|*"/Build/Products/"*)
            ;;
        *)
            return 0
            ;;
    esac

    [[ -z "${seen[$app]-}" ]] || return 0
    seen[$app]=1
    "$lsregister" -u "$app" >/dev/null 2>&1 || true
    (( unregistered += 1 ))
}

# LaunchServices can retain paths after the build product has already been deleted.
while IFS= read -r app; do
    unregister_app "$app"
done < <(
    "$lsregister" -dump 2>/dev/null \
        | /usr/bin/sed -nE 's/^[[:space:]]*path:[[:space:]]+(.*\/Margin\.app)[[:space:]]+\(0x[[:xdigit:]]+\)$/\1/p'
)

for root in "${search_roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d $'\0' app; do
        unregister_app "$app"
    done < <(/usr/bin/find "$root" -type d -name Margin.app -prune -print0 2>/dev/null)
done

print "Margin cleanup: unregistered $unregistered temporary build(s)."
