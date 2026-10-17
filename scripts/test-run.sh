#!/usr/bin/env bash
set -euo pipefail

keyed_test_source="$(cd "$(dirname "$0")/.." && pwd)"
keyed_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/keyed-run.XXXXXX")
trap 'rm -rf "$keyed_test_temp"' EXIT
keyed_test_project="$keyed_test_temp/project with spaces"
export KEYED_RUN_TEST_OUTPUT="$keyed_test_temp/build products"
export KEYED_RUN_TEST_LAUNCH="$keyed_test_temp/launch"
export KEYED_RUN_TEST_MODE=''
mkdir -p "$keyed_test_project" "$keyed_test_temp/bin"
cp "$keyed_test_source/Makefile" "$keyed_test_project/Makefile"

cat > "$keyed_test_temp/bin/xcodegen" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$keyed_test_temp/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
set -eu
for argument in "$@"; do
    if [ "$argument" = -showBuildSettings ]; then
        if [ "${KEYED_RUN_TEST_MODE:-}" = settings-failure ]; then
            printf '    BUILT_PRODUCTS_DIR = %s\n' "$KEYED_RUN_TEST_OUTPUT"
            exit 42
        fi
        if [ "${KEYED_RUN_TEST_MODE:-}" = missing-directory ]; then
            printf '    PRODUCT_NAME = Keyed\n'
            exit 0
        fi
        printf '    OTHER_BUILT_PRODUCTS_DIR = /wrong-prefix\n'
        printf '    BUILT_PRODUCTS_DIR = %s\n' "$KEYED_RUN_TEST_OUTPUT"
        printf '    BUILT_PRODUCTS_DIR = /later-target\n'
        exit 0
    fi
done
if [ "${KEYED_RUN_TEST_MODE:-}" = build-failure ]; then
    exit 41
fi
STUB
cat > "$keyed_test_temp/bin/open" <<'STUB'
#!/usr/bin/env bash
set -eu
test "$#" -eq 1
printf '%s\n' "$1" > "$KEYED_RUN_TEST_LAUNCH"
STUB
chmod +x "$keyed_test_temp/bin/xcodegen" "$keyed_test_temp/bin/xcodebuild" "$keyed_test_temp/bin/open"
export PATH="$keyed_test_temp/bin:$PATH"

make -s -C "$keyed_test_project" run > "$keyed_test_temp/run.log" 2>&1
if [ "$(cat "$KEYED_RUN_TEST_LAUNCH")" != "$KEYED_RUN_TEST_OUTPUT/Keyed.app" ]; then
    echo 'make run did not pass the complete app path to open.' >&2
    cat "$KEYED_RUN_TEST_LAUNCH" >&2
    exit 1
fi
export KEYED_RUN_TEST_OUTPUT="$keyed_test_temp/products"
make -s -C "$keyed_test_project" run > "$keyed_test_temp/run.log" 2>&1
test "$(cat "$KEYED_RUN_TEST_LAUNCH")" = "$KEYED_RUN_TEST_OUTPUT/Keyed.app"
rm "$KEYED_RUN_TEST_LAUNCH"
export KEYED_RUN_TEST_MODE=settings-failure
if make -s -C "$keyed_test_project" run > "$keyed_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build-settings lookup.' >&2
    exit 1
fi
test ! -e "$KEYED_RUN_TEST_LAUNCH"
export KEYED_RUN_TEST_MODE=missing-directory
if make -s -C "$keyed_test_project" run > "$keyed_test_temp/run.log" 2>&1; then
    echo 'make run succeeded without a product directory.' >&2
    exit 1
fi
test ! -e "$KEYED_RUN_TEST_LAUNCH"
export KEYED_RUN_TEST_MODE=build-failure
if make -s -C "$keyed_test_project" run > "$keyed_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build.' >&2
    exit 1
fi
test ! -e "$KEYED_RUN_TEST_LAUNCH"
echo 'Passed 5 launch helper scenarios; no real builds or app launch ran.'
