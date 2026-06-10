#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 1 ]]; then
  printf 'usage: scripts/validate-smoke.sh <simulator-udid> [surface-width surface-height]\n' >&2
  exit 2
fi

udid="$1"
width="${2:-402}"
height="${3:-874}"
cli="${COREDEVICE_HID_CLI:-bin/coredevice_hid_cli}"

"$cli" "$udid" tap 10 10 "$width" "$height"
"$cli" "$udid" touch 10 10 down-up "$width" "$height"
"$cli" "$udid" key 0x2a
