#!/bin/zsh

set -eu

script_dir=${0:A:h}
repository_root=${script_dir:h}
maximum_tracked_bytes=${MARGIN_MAX_TRACKED_BYTES:-1000000}
failures=0

cd "$repository_root"

if ! /usr/bin/git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    print -u2 "Margin public audit: $repository_root is not a Git worktree."
    exit 2
fi
if [[ "$maximum_tracked_bytes" != <-> ]] || (( maximum_tracked_bytes <= 0 )); then
    print -u2 "Margin public audit: MARGIN_MAX_TRACKED_BYTES must be a positive integer."
    exit 2
fi

fail() {
    print -u2 "FAIL: $1"
    failures=$(( failures + 1 ))
}

is_allowed_private_readme() {
    case "$1" in
        Evaluation/private/README.md|Evaluation/results/README.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

while IFS= read -r -d $'\0' path; do
    lower=${path:l}
    case "$path" in
        Local.xcconfig|*/Local.xcconfig|claude_work.md|*/claude_work.md|*.local.json|*.private.json)
            fail "private file is tracked: $path"
            ;;
        Evaluation/private/*|Evaluation/results/*)
            is_allowed_private_readme "$path" || fail "private evaluation artifact is tracked: $path"
            ;;
    esac
    case "$lower" in
        *.key|*.p8|*.p12|*.pem|*.cer|*.crt|*.mobileprovision|*.provisionprofile)
            fail "credential or certificate file is tracked: $path"
            ;;
    esac

    if [[ -f "$path" ]]; then
        size=$(/usr/bin/stat -f %z "$path")
        if (( size > maximum_tracked_bytes )); then
            fail "tracked blob exceeds $maximum_tracked_bytes bytes ($size): $path"
        fi
    fi
done < <(/usr/bin/git ls-files -z)

secret_pattern='(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})'
private_key_pattern='-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----'
team_pattern='(DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|team_id=[A-Z0-9]{10})'
typeset -a audit_exclusions
audit_exclusions=(
    ':(exclude)scripts/audit-public-repo.sh'
    ':(exclude)Tests/Scripts/**'
)

for named_pattern in \
    "API credential:$secret_pattern" \
    "private key material:$private_key_pattern" \
    "personal development team:$team_pattern"; do
    label=${named_pattern%%:*}
    pattern=${named_pattern#*:}
    matches=$(/usr/bin/git grep -I -nE "$pattern" -- . "${audit_exclusions[@]}" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        fail "$label found in tracked text:\n$matches"
    fi
done

require_ignored() {
    local path=$1
    /usr/bin/git check-ignore -q "$path" || fail "required private path is not ignored: $path"
}

require_ignored Local.xcconfig
require_ignored claude_work.md
require_ignored sample.local.json
require_ignored sample.private.json
require_ignored Evaluation/private/sample.txt
require_ignored Evaluation/results/sample.json
if /usr/bin/git check-ignore -q Evaluation/private/README.md; then
    fail "Evaluation/private/README.md must remain publishable"
fi
if /usr/bin/git check-ignore -q Evaluation/results/README.md; then
    fail "Evaluation/results/README.md must remain publishable"
fi

if [[ ! -f README.md ]]; then
    fail "README.md is missing"
else
    if ! /usr/bin/grep -Eiq '(macOS.{0,80}(primary|verified)|(primary|verified).{0,80}macOS)' README.md; then
        fail "README.md must identify macOS as the primary or verified platform"
    fi
    if /usr/bin/grep -Eiq '(iOS|iPadOS|iPhone|iPad)' README.md; then
        fail "README.md must remain focused on the verified macOS experience"
    fi
fi

if (( failures > 0 )); then
    print -u2 "Margin public audit failed with $failures issue(s)."
    exit 1
fi

print "Margin public audit passed: no tracked secrets, private artifacts, oversized blobs, or missing platform declarations were found."
