#!/usr/bin/env bash
set -euo pipefail

keyed_test_source="$(cd "$(dirname "$0")/.." && pwd)"
keyed_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/keyed-package.XXXXXX")
trap 'rm -rf "$keyed_test_temp"' EXIT
keyed_test_project="$keyed_test_temp/project with spaces"
export KEYED_PACKAGE_TEST_OUTPUT="$keyed_test_temp/products"
export KEYED_PACKAGE_TEST_DITTO
KEYED_PACKAGE_TEST_DITTO=$(command -v ditto)
export KEYED_PACKAGE_TEST_MV
KEYED_PACKAGE_TEST_MV=$(command -v mv)
export KEYED_PACKAGE_TEST_MODE=''
export KEYED_PACKAGE_TEST_TOOLS="$keyed_test_temp/tools.log"
mkdir -p "$keyed_test_project" "$keyed_test_temp/bin" \
    "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources"
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
        if [ "$KEYED_PACKAGE_TEST_MODE" = missing-directory ]; then
            printf '    PRODUCT_NAME = Keyed\n'
            exit 0
        fi
        printf '    BUILT_PRODUCTS_DIR = %s\n' "$KEYED_PACKAGE_TEST_OUTPUT"
        if [ "$KEYED_PACKAGE_TEST_MODE" = settings-failure ]; then exit 42; fi
    fi
done
if [ "$KEYED_PACKAGE_TEST_MODE" = build-failure ]; then exit 41; fi
STUB
chmod +x "$keyed_test_temp/bin/xcodegen" "$keyed_test_temp/bin/xcodebuild"
export PATH="$keyed_test_temp/bin:$PATH"

package() {
    if ! make -s -C "$keyed_test_project" package > "$keyed_test_temp/package.log" 2>&1; then
        cat "$keyed_test_temp/package.log" >&2
        exit 1
    fi
}

printf 'obsolete\n' > "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources/removed.txt"
package
unzip -Z1 "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" > "$keyed_test_temp/entries"
grep -qx 'Keyed.app/Contents/Resources/removed.txt' "$keyed_test_temp/entries"

rm "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources/removed.txt"
printf 'current\n' > "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources/current.txt"
package
unzip -Z1 "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" > "$keyed_test_temp/entries"
if grep -qx 'Keyed.app/Contents/Resources/removed.txt' "$keyed_test_temp/entries"; then
    echo 'Repeated packaging retained a deleted app resource.' >&2
    exit 1
fi
grep -qx 'Keyed.app/Contents/Resources/current.txt' "$keyed_test_temp/entries"
unzip -tq "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip"

export KEYED_PACKAGE_TEST_OUTPUT="$keyed_test_temp/build products"
mkdir -p "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources"
printf 'space path\n' > "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources/current.txt"
package
if [ "$(unzip -p "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" Keyed.app/Contents/Resources/current.txt)" != 'space path' ]; then
    echo 'Packaging did not preserve the current resource from a path with spaces.' >&2
    exit 1
fi

mkdir -p "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/MacOS/Keyed"
chmod +x "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/MacOS/Keyed"
ln -s current.txt "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.app/Contents/Resources/linked.txt"
package
ditto -x -k "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" "$keyed_test_temp/extracted"
test -x "$keyed_test_temp/extracted/Keyed.app/Contents/MacOS/Keyed"
test -L "$keyed_test_temp/extracted/Keyed.app/Contents/Resources/linked.txt"
test "$(readlink "$keyed_test_temp/extracted/Keyed.app/Contents/Resources/linked.txt")" = current.txt
cp "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" "$keyed_test_temp/original.zip"
cat > "$keyed_test_temp/bin/ditto" <<'STUB'
#!/usr/bin/env bash
set -eu
printf 'archive\n' >> "$KEYED_PACKAGE_TEST_TOOLS"
case "$KEYED_PACKAGE_TEST_MODE" in
    archive-failure|corrupt-archive)
        printf 'partial archive\n' > "${!#}"
        if [ "$KEYED_PACKAGE_TEST_MODE" = archive-failure ]; then exit 73; fi
        exit 0
        ;;
esac
exec "$KEYED_PACKAGE_TEST_DITTO" "$@"
STUB
cat > "$keyed_test_temp/bin/mv" <<'STUB'
#!/usr/bin/env bash
set -eu
printf 'publish\n' >> "$KEYED_PACKAGE_TEST_TOOLS"
if [ "$KEYED_PACKAGE_TEST_MODE" = publish-failure ]; then exit 74; fi
exec "$KEYED_PACKAGE_TEST_MV" "$@"
STUB
chmod +x "$keyed_test_temp/bin/ditto" "$keyed_test_temp/bin/mv"

assert_no_staging() {
    if [ -n "$(find "$KEYED_PACKAGE_TEST_OUTPUT" -name '.keyed-package.*' -print)" ]; then
        echo 'Packaging left archive staging behind.' >&2
        exit 1
    fi
}

for KEYED_PACKAGE_TEST_MODE in archive-failure settings-failure missing-directory build-failure publish-failure corrupt-archive; do
    : > "$KEYED_PACKAGE_TEST_TOOLS"
    if make -s -C "$keyed_test_project" package > "$keyed_test_temp/package.log" 2>&1; then
        echo "Packaging succeeded in failure fixture: $KEYED_PACKAGE_TEST_MODE" >&2
        exit 1
    fi
    if ! cmp -s "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" "$keyed_test_temp/original.zip"; then
        echo "Failure replaced the previous package: $KEYED_PACKAGE_TEST_MODE" >&2
        exit 1
    fi
    if grep -q 'Package created at' "$keyed_test_temp/package.log"; then
        echo "Failure printed a success path: $KEYED_PACKAGE_TEST_MODE" >&2
        exit 1
    fi
    assert_no_staging
    case "$KEYED_PACKAGE_TEST_MODE" in
        settings-failure|missing-directory|build-failure)
            test ! -s "$KEYED_PACKAGE_TEST_TOOLS"
            ;;
        archive-failure|corrupt-archive)
            if grep -q publish "$KEYED_PACKAGE_TEST_TOOLS"; then
                echo 'Failed compression reached archive publication.' >&2
                exit 1
            fi
            ;;
    esac
done
KEYED_PACKAGE_TEST_MODE=''
package
assert_no_staging
unzip -tq "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip"
mv "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip" "$keyed_test_temp/final.zip"
mkdir "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip"
printf 'preserve directory\n' > "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip/sentinel"
: > "$KEYED_PACKAGE_TEST_TOOLS"
if make -s -C "$keyed_test_project" package > "$keyed_test_temp/package.log" 2>&1; then
    echo 'Packaging accepted a directory as the final ZIP path.' >&2
    exit 1
fi
test "$(cat "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip/sentinel")" = 'preserve directory'
test ! -e "$KEYED_PACKAGE_TEST_OUTPUT/Keyed.zip/Keyed.zip"
test ! -s "$KEYED_PACKAGE_TEST_TOOLS"
assert_no_staging
echo 'Passed 11 packaging scenarios; no real builds, signing, or app launch ran.'
