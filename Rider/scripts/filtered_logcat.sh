#!/usr/bin/env sh
# Hides BLASTBufferQueue and ScrollIdentify logs when debugging Android.
# Run: ./scripts/filtered_logcat.sh
# Or from Rider: sh scripts/filtered_logcat.sh

adb logcat -v time '*:V' BLASTBufferQueue:S ScrollIdentify:S
