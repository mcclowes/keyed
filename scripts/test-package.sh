#!/usr/bin/env bash
set -euo pipefail

keyed_test_source="$(cd "$(dirname "$0")/.." && pwd)"
keyed_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/keyed-package.XXXXXX")
trap 'rm -rf "$keyed_test_temp"' EXIT
keyed_test_project="$keyed_test_temp/project with spaces"
export KEYED_PACKAGE_TEST_OUTPUT="$keyed_test_temp/products"
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
        printf '    BUILT_PRODUCTS_DIR = %s\n' "$KEYED_PACKAGE_TEST_OUTPUT"
    fi
done
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
echo 'Passed 3 packaging scenarios; no real builds, signing, or app launch ran.'
