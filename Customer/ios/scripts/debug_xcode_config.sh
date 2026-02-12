#!/bin/sh

LOG_PATH="/Users/sudimard/Desktop/customer/.cursor/debug.log"
SESSION_ID="debug-session"
RUN_ID="pre-xcode"

timestamp_ms() {
  date +%s000
}

write_log() {
  echo "$1" >> "$LOG_PATH"
}

PWD_VALUE="$(pwd)"
write_log "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"H1\",\"location\":\"ios/scripts/debug_xcode_config.sh:12\",\"message\":\"debug script start\",\"data\":{\"pwd\":\"${PWD_VALUE}\"},\"timestamp\":$(timestamp_ms)}"

GEN_PATH="/Users/sudimard/Desktop/customer/ios/Flutter/Generated.xcconfig"
if [ -f "$GEN_PATH" ]; then
  GEN_EXISTS=true
  GEN_MTIME=$(stat -f "%m" "$GEN_PATH")
else
  GEN_EXISTS=false
  GEN_MTIME=0
fi
write_log "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"H1\",\"location\":\"ios/scripts/debug_xcode_config.sh:22\",\"message\":\"Generated.xcconfig presence\",\"data\":{\"path\":\"${GEN_PATH}\",\"exists\":${GEN_EXISTS},\"mtime\":${GEN_MTIME}},\"timestamp\":$(timestamp_ms)}"

DEBUG_XCCONFIG="/Users/sudimard/Desktop/customer/ios/Flutter/Debug.xcconfig"
if [ -f "$DEBUG_XCCONFIG" ]; then
  DEBUG_EXISTS=true
  DEBUG_MTIME=$(stat -f "%m" "$DEBUG_XCCONFIG")
else
  DEBUG_EXISTS=false
  DEBUG_MTIME=0
fi
write_log "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"H2\",\"location\":\"ios/scripts/debug_xcode_config.sh:34\",\"message\":\"Debug.xcconfig presence\",\"data\":{\"path\":\"${DEBUG_XCCONFIG}\",\"exists\":${DEBUG_EXISTS},\"mtime\":${DEBUG_MTIME}},\"timestamp\":$(timestamp_ms)}"

WORKSPACE_PATH="/Users/sudimard/Desktop/customer/ios/Runner.xcworkspace"
if [ -d "$WORKSPACE_PATH" ]; then
  WORKSPACE_EXISTS=true
else
  WORKSPACE_EXISTS=false
fi
write_log "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"H3\",\"location\":\"ios/scripts/debug_xcode_config.sh:44\",\"message\":\"Runner.xcworkspace presence\",\"data\":{\"path\":\"${WORKSPACE_PATH}\",\"exists\":${WORKSPACE_EXISTS}},\"timestamp\":$(timestamp_ms)}"

PROJECT_PATH="/Users/sudimard/Desktop/customer/ios/Runner.xcodeproj"
if [ -d "$PROJECT_PATH" ]; then
  PROJECT_EXISTS=true
else
  PROJECT_EXISTS=false
fi
write_log "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"H4\",\"location\":\"ios/scripts/debug_xcode_config.sh:54\",\"message\":\"Runner.xcodeproj presence\",\"data\":{\"path\":\"${PROJECT_PATH}\",\"exists\":${PROJECT_EXISTS}},\"timestamp\":$(timestamp_ms)}"
