#!/usr/bin/env bash
# Tests for build-addon-manifest.sh. Builds small zips with `zip`, needs no network.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/build-addon-manifest.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# make_zip <name> <toc version line or "-" for none> [extra paths under the staging root...]
make_zip() {
  local name=$1 version=$2; shift 2
  local root="$work/src-$name"
  rm -rf "$root"; mkdir -p "$root/GoldCap/Core"
  echo "local a = 1" > "$root/GoldCap/Core/a.lua"
  if [ "$version" != "-" ]; then
    printf '## Title: GoldCap\n## Version: %s\n' "$version" > "$root/GoldCap/GoldCap.toc"
  fi
  local extra
  for extra in "$@"; do
    mkdir -p "$root/$(dirname "$extra")"; echo x > "$root/$extra"
  done
  (cd "$root" && zip -qr "$work/$name.zip" .)
  echo "$work/$name.zip"
}

# expect_refused <name> <zip> [env assignments...]: non-zero exit, nothing written.
expect_refused() {
  local name=$1 zip=$2; shift 2
  local out="$work/out-$name"
  if env "$@" bash "$script" "$zip" "$out" >"$work/$name.log" 2>&1; then
    fail "$name: the script accepted it"
  fi
  [ ! -e "$out/addon.json" ] || fail "$name: addon.json was written"
}

good_zip_produces_manifest() {
  local zip out=$work/out-good
  zip=$(make_zip good 'addon-v0.23.0')
  PUBLISHED_AT=2026-10-22T10:00:00Z bash "$script" "$zip" "$out" >"$work/good.log"
  local json=$out/addon.json size sha
  jq -e '.version == "0.23.0"' "$json" >/dev/null || fail "version"
  jq -e '.url == "https://goldcap.gg/downloads/addon/GoldCap-addon-v0.23.0.zip"' "$json" >/dev/null || fail "url"
  size=$(wc -c < "$zip" | tr -d ' ')
  sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
  jq -e --argjson s "$size" '.size == $s' "$json" >/dev/null || fail "size"
  jq -e --arg h "$sha" '.sha256 == $h' "$json" >/dev/null || fail "sha256"
  jq -e '.publishedAt == "2026-10-22T10:00:00Z"' "$json" >/dev/null || fail "publishedAt"
  jq -e 'keys == ["publishedAt","sha256","size","url","version"]' "$json" >/dev/null || fail "keys"
  cmp -s "$zip" "$out/GoldCap-addon-v0.23.0.zip" || fail "the copy differs"
  grep -q 'unsigned dry run' "$work/good.log" || fail "no unsigned notice"
  [ ! -e "$out/addon.json.sig" ] || fail "a signature appeared without a key"
}

tag_matches_passes() {
  local zip
  zip=$(make_zip tagok 'addon-v0.23.0')
  ADDON_TAG=addon-v0.23.0 bash "$script" "$zip" "$work/out-tagok" >/dev/null
}

tag_mismatch_fails() {
  expect_refused tag "$(make_zip tag 'addon-v0.23.0')" ADDON_TAG=addon-v0.24.0
}

non_numeric_version_fails() {
  expect_refused dev "$(make_zip dev '@project-version@')"
  expect_refused rc "$(make_zip rc 'addon-v0.23.0-rc1')"
  expect_refused short "$(make_zip short 'addon-v0.23')"
}

foreign_top_folder_fails() {
  expect_refused foreign "$(make_zip foreign 'addon-v0.23.0' Details/Core.lua)"
}

appdata_folder_fails() {
  expect_refused appdata "$(make_zip appdata 'addon-v0.23.0' GoldCap/GoldCap_AppData/AppData.lua)"
}

executable_fails() {
  expect_refused exe "$(make_zip exe 'addon-v0.23.0' GoldCap/Tools/Run.EXE)"
}

missing_toc_fails() {
  expect_refused notoc "$(make_zip notoc -)"
}

workflow="$here/../.github/workflows/addon-release.yml"

mirror_runs_only_on_addon_tags() {
  awk '/^  mirror:/{f=1;next} f&&/^  [a-z]/{exit} f&&/^    if: startsWith\(github.ref, .refs\/tags\/addon-v.\)$/{ok=1} END{exit !ok}' "$workflow" \
    || { echo "mirror job is not limited to refs/tags/addon-v*" >&2; return 1; }
}

artifact_upload_cannot_block_the_discord_post_on_a_tag() {
  awk '/upload-artifact@/{f=1;next} f&&/continue-on-error: .*startsWith\(github.ref, .refs\/tags\/.\)/{ok=1} f&&/^      - /{exit} END{exit !ok}' "$workflow" \
    || { echo "package's upload-artifact step can fail the job on a tag" >&2; return 1; }
}

for t in mirror_runs_only_on_addon_tags artifact_upload_cannot_block_the_discord_post_on_a_tag good_zip_produces_manifest tag_matches_passes tag_mismatch_fails non_numeric_version_fails \
         foreign_top_folder_fails appdata_folder_fails executable_fails missing_toc_fails; do
  "$t"
  echo "ok $t"
done
