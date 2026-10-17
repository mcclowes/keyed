#!/bin/bash
set -euo pipefail

keyed_test_source="$(cd "$(dirname "$0")/.." && pwd)"
keyed_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/keyed-bump-version.XXXXXX")
trap 'rm -rf "$keyed_test_temp"' EXIT
keyed_cases=0

fail() { echo "$1" >&2; exit 1; }

new_fixture() {
    keyed_fixture=$(mktemp -d "$keyed_test_temp/project with spaces.XXXXXX")
    mkdir -p "$keyed_fixture/bin"
    cat > "$keyed_fixture/project.yml" <<'PROJECT'
settings:
  MARKETING_VERSION: "4.5.6"
  CURRENT_PROJECT_VERSION: 78
  SENTINEL: unchanged
PROJECT
    cp "$keyed_fixture/project.yml" "$keyed_fixture/original.yml"
    cat > "$keyed_fixture/bin/git" <<'STUB'
#!/bin/bash
printf '<%s>' "$@" >> "$GIT_LOG"
printf '\n' >> "$GIT_LOG"
exit "${GIT_STATUS:-97}"
STUB
    chmod +x "$keyed_fixture/bin/git"
}

run_helper() {
    if (cd "$keyed_fixture" && env PATH="$keyed_fixture/bin:/usr/bin:/bin" \
        BASH_ENV=/dev/null GIT_LOG="$keyed_fixture/git.log" GIT_STATUS="${keyed_git_status:-97}" \
        /bin/bash "$keyed_test_source/scripts/bump-version.sh" "$@") \
        > "$keyed_fixture/output" 2> "$keyed_fixture/error"; then
        keyed_status=0
    else
        keyed_status=$?
    fi
}

reject_arguments() {
    new_fixture
    run_helper "$@"
    [ "$keyed_status" = 2 ] || fail "Invalid arguments returned $keyed_status instead of usage status 2: $*"
    grep -q 'Usage:' "$keyed_fixture/error" || fail 'Missing usage diagnostic on stderr'
    [ ! -s "$keyed_fixture/output" ] || fail 'Invalid arguments emitted release progress'
    cmp -s "$keyed_fixture/project.yml" "$keyed_fixture/original.yml" || fail 'Invalid arguments changed project metadata'
    [ ! -e "$keyed_fixture/git.log" ] || fail 'Invalid arguments invoked Git'
    keyed_cases=$((keyed_cases + 1))
}

reject_arguments patch --pus
reject_arguments patch --push extra
reject_arguments
reject_arguments ''
reject_arguments release
reject_arguments PATCH
reject_arguments --push
reject_arguments patch ''
reject_arguments minor --help
reject_arguments major extra
reject_arguments patch --push --push
reject_arguments patch extra ignored

new_fixture
mv "$keyed_fixture/project.yml" "$keyed_fixture/unread-project.yml"
run_helper patch --pus
[ "$keyed_status" = 2 ] || fail 'Invalid arguments tried to read missing project metadata'
grep -q 'Usage:' "$keyed_fixture/error" || fail 'Missing usage before project read'
[ ! -e "$keyed_fixture/git.log" ] || fail 'Invalid arguments invoked Git without project metadata'
keyed_cases=$((keyed_cases + 1))

keyed_git_status=0
for bump in major minor patch; do
    case "$bump" in
        major) expected_version=5.0.0 ;;
        minor) expected_version=4.6.0 ;;
        patch) expected_version=4.5.7 ;;
    esac
    for mode in local push; do
        new_fixture
        if [ "$mode" = push ]; then
            run_helper "$bump" --push
        else
            run_helper "$bump"
        fi
        [ "$keyed_status" = 0 ] || fail "Valid $bump/$mode bump failed"
        cat > "$keyed_fixture/expected.yml" <<PROJECT
settings:
  MARKETING_VERSION: "$expected_version"
  CURRENT_PROJECT_VERSION: 78
  SENTINEL: unchanged
PROJECT
        cmp -s "$keyed_fixture/project.yml" "$keyed_fixture/expected.yml" || fail "Wrong metadata for $bump/$mode"
        cat > "$keyed_fixture/expected-git.log" <<GIT
<add><project.yml>
<commit><-m><Bump version to $expected_version>
<tag><-a><v$expected_version><-m><Release v$expected_version>
GIT
        if [ "$mode" = push ]; then
            cat >> "$keyed_fixture/expected-git.log" <<GIT
<push><origin><HEAD>
<push><origin><v$expected_version>
GIT
        fi
        cmp -s "$keyed_fixture/git.log" "$keyed_fixture/expected-git.log" || fail "Wrong Git actions for $bump/$mode"
        [ ! -s "$keyed_fixture/error" ] || fail 'Valid bump emitted errors'
        keyed_cases=$((keyed_cases + 1))
    done
done

echo "Passed $keyed_cases version-helper scenarios; no real Git mutations ran."
