#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcrun swift build -c release --product coredevice_hid_cli
install -d bin
cp .build/release/coredevice_hid_cli bin/coredevice_hid_cli
shasum -a 256 bin/coredevice_hid_cli
