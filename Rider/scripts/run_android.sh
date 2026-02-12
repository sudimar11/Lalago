#!/usr/bin/env sh
# Run Rider on Android and hide BLASTBufferQueue / ScrollIdentify logs in this terminal.
# Usage: sh scripts/run_android.sh [flutter run args...]
# Example: sh scripts/run_android.sh -d <device_id>

cd "$(dirname "$0")/.." || exit 1
flutter run "$@" 2>&1 | grep --line-buffered -v -E 'BLASTBufferQueue|ScrollIdentify'
