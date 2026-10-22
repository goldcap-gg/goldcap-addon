#!/usr/bin/env bash
# Usage: build-addon-manifest.sh <addon zip> <out dir>
#
# Writes <out dir>/GoldCap-addon-v<ver>.zip (a copy) and <out dir>/addon.json, the
# manifest the Companion reads from goldcap.gg/downloads/addon/ to install and
# update the addon. With TAURI_SIGNING_PRIVATE_KEY set it also signs addon.json
# into addon.json.sig; without it, it says "unsigned dry run" and still exits 0.
#
# <ver> is read from GoldCap/GoldCap.toc inside the zip ("## Version: addon-v0.22.0").
# Optional environment:
#   ADDON_TAG     the git tag being released; its version must equal the TOC's
#   PUBLISHED_AT  the timestamp to record (default: now, UTC)
#
# Everything is checked before anything is written, so a refused zip leaves no
# addon.json behind. The zip checks mirror what the Companion refuses to unpack
# (companion src-tauri/src/addon_files.rs), so a release it could not install fails
# here instead of after the tag.
set -euo pipefail

BASE_URL="https://goldcap.gg/downloads/addon"
# Exact, and at least two weeks old when pinned; the key is the Companion's updater key.
TAURI_CLI="@tauri-apps/cli@2.11.5"
MAX_ENTRIES=4000
MAX_UNPACKED=$((64 * 1024 * 1024))

die() { echo "build-addon-manifest: $*" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: build-addon-manifest.sh <addon zip> <out dir>"
zip=$1
out=$2
[ -f "$zip" ] || die "no such zip: $zip"

names=$(unzip -Z1 "$zip") || die "not a readable zip: $zip"

count=0
while IFS= read -r name; do
  count=$((count + 1))
  case "$name" in
    GoldCap/*) ;;
    *) die "entry outside the GoldCap folder: $name" ;;
  esac
  case "/$name/" in
    */../*) die "entry leaves the folder: $name" ;;
    */GoldCap_AppData/*) die "the zip carries GoldCap_AppData, which the Companion owns: $name" ;;
    */.goldcap-companion.json/*) die "the zip carries the Companion's marker: $name" ;;
  esac
  lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *.exe|*.dll|*.bat|*.cmd|*.com|*.scr|*.ps1|*.sh|*.msi|*.jar|*.vbs|*.js) die "executable file in the zip: $name" ;;
  esac
done <<< "$names"
[ "$count" -le "$MAX_ENTRIES" ] || die "$count entries, the Companion unpacks at most $MAX_ENTRIES"

unpacked=$(unzip -Zt "$zip" | sed -E 's/^[0-9]+ files?, ([0-9]+) bytes uncompressed.*/\1/')
[[ "$unpacked" =~ ^[0-9]+$ ]] || die "could not read the unpacked size"
[ "$unpacked" -le "$MAX_UNPACKED" ] || die "unpacks to $unpacked bytes, the Companion allows $MAX_UNPACKED"

case $'\n'"$names"$'\n' in
  *$'\nGoldCap/GoldCap.toc\n'*) ;;
  *) die "no GoldCap/GoldCap.toc in the zip" ;;
esac

toc=$(unzip -p "$zip" GoldCap/GoldCap.toc)
line=$(grep -m1 '^## Version:' <<< "$toc" || true)
[ -n "$line" ] || die "GoldCap.toc has no ## Version line"
raw=$(printf '%s' "${line#\#\# Version:}" | tr -d '[:space:]')
version=${raw#addon-v}
version=${version#v}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version \"$raw\" is not N.N.N"

if [ -n "${ADDON_TAG:-}" ] && [ "${ADDON_TAG#addon-v}" != "$version" ]; then
  die "tag $ADDON_TAG does not match the TOC version $version"
fi

published_at=${PUBLISHED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
file="GoldCap-addon-v$version.zip"

mkdir -p "$out"
cp "$zip" "$out/$file"
size=$(wc -c < "$zip" | tr -d ' ')
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
jq -n --arg version "$version" --arg url "$BASE_URL/$file" --arg sha "$sha" \
  --argjson size "$size" --arg at "$published_at" \
  '{version: $version, url: $url, sha256: $sha, size: $size, publishedAt: $at}' > "$out/addon.json"

if [ -n "${TAURI_SIGNING_PRIVATE_KEY:-}" ]; then
  rm -f "$out/addon.json.sig"
  npx --yes "$TAURI_CLI" signer sign -p "${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:-}" "$out/addon.json" >&2
  [ -s "$out/addon.json.sig" ] || die "signing wrote no addon.json.sig"
else
  echo "unsigned dry run: set TAURI_SIGNING_PRIVATE_KEY to sign"
fi

echo "$out/addon.json"
