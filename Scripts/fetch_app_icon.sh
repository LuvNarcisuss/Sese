#!/bin/sh
set -eu

configuration="$1"
manifest="$2"
output="$3"

project_url=$(/usr/bin/plutil -extract url raw "$configuration")
object_path=$(/usr/bin/plutil -extract launcher.storage_path raw "$manifest")
expected=$(/usr/bin/plutil -extract launcher.sha256 raw "$manifest")

digest() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/cut -d ' ' -f 1
}

if [ -f "$output" ] && [ "$(digest "$output")" = "$expected" ]; then
    exit 0
fi

download=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/sese-app-icon.XXXXXX")
trap 'rm -f "$download"' EXIT

if ! /usr/bin/curl --proto '=https' --fail --silent --show-error \
    --retry 2 --connect-timeout 10 --max-time 30 --output "$download" \
    "${project_url%/}/storage/v1/object/public/$object_path"; then
    echo "error: Could not download the Sese app icon from Supabase." >&2
    exit 1
fi

if [ "$(digest "$download")" != "$expected" ]; then
    echo "error: The Sese app icon does not match its artwork manifest." >&2
    exit 1
fi

/bin/mv -f "$download" "$output"
