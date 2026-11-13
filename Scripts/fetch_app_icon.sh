#!/bin/sh
set -eu

encoded_source="$1"
manifest="$2"
output="$3"
expected=$(/usr/bin/plutil -extract launcher.sha256 raw "$manifest")

digest() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/cut -d ' ' -f 1
}

if [ -f "$output" ] && [ "$(digest "$output")" = "$expected" ]; then
    exit 0
fi

prepared=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/sese-app-icon.XXXXXX")
trap 'rm -f "$prepared"' EXIT
/usr/bin/base64 --decode -i "$encoded_source" -o "$prepared"

if [ "$(digest "$prepared")" != "$expected" ]; then
    echo "error: The Sese app icon does not match its artwork manifest." >&2
    exit 1
fi

/bin/mkdir -p "$(/usr/bin/dirname "$output")"
/bin/mv -f "$prepared" "$output"
