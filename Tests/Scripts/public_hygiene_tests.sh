#!/bin/zsh

set -eu

test_dir=${0:A:h}
repository_root=${test_dir:h:h}
temporary_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/margin-public-hygiene.XXXXXX")
trap '/bin/rm -rf -- "$temporary_root"' EXIT

fail() {
    print -u2 "Public hygiene self-test failed: $1"
    exit 1
}

assert_exists() {
    [[ -e "$1" ]] || fail "expected path to exist: $1"
}

assert_missing() {
    [[ ! -e "$1" ]] || fail "expected path to be removed: $1"
}

clean_fixture="$temporary_root/clean-fixture"
/bin/mkdir -p "$clean_fixture/scripts"
/bin/cp "$repository_root/scripts/clean-local-builds.sh" "$clean_fixture/scripts/clean-local-builds.sh"

clean_log="$temporary_root/unregister.log"
cat > "$clean_fixture/scripts/unregister-derived-margin.sh" <<'STUB'
#!/bin/zsh
set -eu
for path in "$@"; do
    [[ -e "$path" ]] || {
        print -u2 "cleanup ran unregister after deleting $path"
        exit 1
    }
done
print -r -- "$*" >> "$MARGIN_CLEAN_TEST_LOG"
STUB
/bin/chmod +x "$clean_fixture/scripts/unregister-derived-margin.sh"

fake_home="$temporary_root/home"
/bin/mkdir -p \
    "$clean_fixture/.build/product" \
    "$clean_fixture/DerivedData/product" \
    "$fake_home/Library/Developer/Xcode/DerivedData/BooksTranslator-one" \
    "$fake_home/Library/Developer/Xcode/DerivedData/OtherProject-one" \
    "$fake_home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex" \
    "$fake_home/Applications/Margin.app" \
    "$fake_home/Library/Application Support/Margin" \
    "$fake_home/Library/Keychains"
/usr/bin/touch \
    "$fake_home/Applications/Margin.app/keep" \
    "$fake_home/Library/Application Support/Margin/keep" \
    "$fake_home/Library/Keychains/keep" \
    "$fake_home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/keep"

HOME="$fake_home" MARGIN_CLEAN_TEST_LOG="$clean_log" \
    "$clean_fixture/scripts/clean-local-builds.sh" >/dev/null
assert_missing "$clean_fixture/.build"
assert_missing "$clean_fixture/DerivedData"
assert_exists "$fake_home/Library/Developer/Xcode/DerivedData/BooksTranslator-one"
assert_exists "$fake_home/Library/Developer/Xcode/DerivedData/OtherProject-one"
assert_exists "$fake_home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/keep"
assert_exists "$fake_home/Applications/Margin.app/keep"
assert_exists "$fake_home/Library/Application Support/Margin/keep"
assert_exists "$fake_home/Library/Keychains/keep"

/bin/mkdir -p "$clean_fixture/.build/again" "$clean_fixture/DerivedData/again"
HOME="$fake_home" MARGIN_CLEAN_TEST_LOG="$clean_log" \
    "$clean_fixture/scripts/clean-local-builds.sh" --xcode-derived-data >/dev/null
assert_missing "$clean_fixture/.build"
assert_missing "$clean_fixture/DerivedData"
assert_missing "$fake_home/Library/Developer/Xcode/DerivedData/BooksTranslator-one"
assert_exists "$fake_home/Library/Developer/Xcode/DerivedData/OtherProject-one"
assert_exists "$fake_home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/keep"
assert_exists "$fake_home/Applications/Margin.app/keep"
assert_exists "$fake_home/Library/Application Support/Margin/keep"
assert_exists "$fake_home/Library/Keychains/keep"
[[ $(/usr/bin/wc -l < "$clean_log") -eq 2 ]] || fail "unregister script was not called before both cleanups"

audit_fixture="$temporary_root/audit-fixture"
/bin/mkdir -p "$audit_fixture/scripts"
/bin/cp "$repository_root/scripts/audit-public-repo.sh" "$audit_fixture/scripts/audit-public-repo.sh"
/bin/cp "$repository_root/.gitignore" "$audit_fixture/.gitignore"
cat > "$audit_fixture/README.md" <<'README'
# Margin

macOS is the primary platform. iOS and iPadOS source support is Experimental.
README
(
    cd "$audit_fixture"
    /usr/bin/git init -q
    /usr/bin/git config user.email margin-tests@example.invalid
    /usr/bin/git config user.name "Margin Tests"
    /usr/bin/git add .
    ./scripts/audit-public-repo.sh >/dev/null

    print 'private' > sample.private.json
    /usr/bin/git add -f sample.private.json
    if ./scripts/audit-public-repo.sh >"$temporary_root/private.out" 2>&1; then
        fail "audit accepted a tracked private JSON file"
    fi
    /usr/bin/grep -q 'private file is tracked' "$temporary_root/private.out" \
        || fail "audit did not explain the private JSON failure"
    /usr/bin/git rm -q --cached sample.private.json
    /bin/rm sample.private.json

    print 'sk-1234567890abcdefghijklmnop' > credential.txt
    /usr/bin/git add credential.txt
    if ./scripts/audit-public-repo.sh >"$temporary_root/secret.out" 2>&1; then
        fail "audit accepted a tracked API credential"
    fi
    /usr/bin/grep -q 'API credential' "$temporary_root/secret.out" \
        || fail "audit did not explain the API credential failure"
    /usr/bin/git rm -q --cached credential.txt
    /bin/rm credential.txt

    print 'certificate fixture' > signing.p12
    /usr/bin/git add -f signing.p12
    if ./scripts/audit-public-repo.sh >"$temporary_root/certificate.out" 2>&1; then
        fail "audit accepted a tracked certificate file"
    fi
    /usr/bin/grep -q 'credential or certificate file is tracked' "$temporary_root/certificate.out" \
        || fail "audit did not explain the certificate failure"
    /usr/bin/git rm -q --cached signing.p12
    /bin/rm signing.p12

    /bin/cp README.md README.original
    print 'macOS is the primary platform.' > README.md
    if ./scripts/audit-public-repo.sh >"$temporary_root/platform.out" 2>&1; then
        fail "audit accepted a README without the Experimental iOS declaration"
    fi
    /usr/bin/grep -q 'iOS/iPadOS support as Experimental' "$temporary_root/platform.out" \
        || fail "audit did not explain the platform declaration failure"
    /bin/mv README.original README.md

    /bin/dd if=/dev/zero of=large.bin bs=2048 count=1 2>/dev/null
    /usr/bin/git add large.bin
    if MARGIN_MAX_TRACKED_BYTES=1024 ./scripts/audit-public-repo.sh >"$temporary_root/large.out" 2>&1; then
        fail "audit accepted an oversized tracked blob"
    fi
    /usr/bin/grep -q 'tracked blob exceeds' "$temporary_root/large.out" \
        || fail "audit did not explain the oversized blob failure"
)

print "Public hygiene self-tests passed."
