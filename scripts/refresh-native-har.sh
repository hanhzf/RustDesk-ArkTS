#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
enhanced_root="${RUSTDESK_ENHANCED_ROOT:-$app_root/../RustDesk-Enhanced}"
ohos_cli_home="${OHOS_CLI_HOME:-/home/frankhan/command-line-tools}"
ohpm_bin="${OHPM:-$ohos_cli_home/bin/ohpm}"
source_har="${NATIVE_HAR_PATH:-$enhanced_root/dist/ohos-har/package.har}"
target_har="$app_root/rustdesk-ohrs.har"

if [[ ! -f "$source_har" ]]; then
  cat >&2 <<EOF
Missing native HAR: $source_har

Build it first:
  cd "$enhanced_root"
  scripts/ohos/build-har.sh
EOF
  exit 1
fi

source_har="$(cd "$(dirname "$source_har")" && pwd)/$(basename "$source_har")"

cp "$source_har" "$target_har"

cd "$app_root"
rm -rf oh_modules entry/oh_modules
"$ohpm_bin" install

cd "$app_root/entry"
"$ohpm_bin" install

printf 'Refreshed %s from %s\n' "$target_har" "$source_har"
