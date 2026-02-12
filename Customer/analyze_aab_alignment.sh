#!/bin/bash
# Bash script to analyze AAB/APK for 4KB alignment errors
# This script helps identify .so files with 4KB alignment that need 16KB alignment

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-aab-or-apk>"
    exit 1
fi

AAB_APK_PATH="$1"

if [ ! -f "$AAB_APK_PATH" ]; then
    echo "Error: File not found: $AAB_APK_PATH"
    exit 1
fi

echo "Analyzing AAB/APK for 16KB alignment compliance..."
echo "File: $AAB_APK_PATH"

# Check if it's an AAB or APK
EXTENSION="${AAB_APK_PATH##*.}"
if [ "$EXTENSION" != "aab" ] && [ "$EXTENSION" != "apk" ]; then
    echo "Error: File must be .aab or .apk"
    exit 1
fi

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Extracting $EXTENSION file..."
unzip -q "$AAB_APK_PATH" -d "$TEMP_DIR"

# Find all .so files
SO_FILES=$(find "$TEMP_DIR" -name "*.so" 2>/dev/null)

if [ -z "$SO_FILES" ]; then
    echo "No native libraries (.so files) found. This might be a pure Java/Kotlin app."
    exit 0
fi

echo ""
echo "Found native libraries (.so files):"
echo "=================================================================================="

COUNT=0
for SO_FILE in $SO_FILES; do
    COUNT=$((COUNT + 1))
    RELATIVE_PATH="${SO_FILE#$TEMP_DIR/}"
    FILE_SIZE=$(stat -f%z "$SO_FILE" 2>/dev/null || stat -c%s "$SO_FILE" 2>/dev/null)
    FILE_SIZE_KB=$((FILE_SIZE / 1024))
    
    # Extract ABI from path (lib/{abi}/*.so)
    ABI=$(echo "$RELATIVE_PATH" | sed -n 's|.*/lib/\([^/]*\)/.*|\1|p')
    
    echo ""
    echo "Library $COUNT: $RELATIVE_PATH"
    echo "  Size: ${FILE_SIZE_KB} KB"
    [ -n "$ABI" ] && echo "  ABI: $ABI"
    echo "  Status: Manual analysis required in Android Studio APK Analyzer"
    echo "    -> Open Android Studio > Build > Analyze APK"
    echo "    -> Check 'LOAD segment alignment' column for this file"
    echo "    -> Should show 16 KB (16384), not 4 KB (4096)"
done

echo ""
echo "=================================================================================="
echo "Summary:"
echo "  Total .so files found: $COUNT"
echo ""
echo "Next Steps:"
echo "  1. Open Android Studio"
echo "  2. Go to Build > Analyze APK..."
echo "  3. Select your AAB/APK file"
echo "  4. Expand the 'lib' folder"
echo "  5. Check each .so file's 'LOAD segment alignment' value"
echo "  6. Files showing '4 KB' need to be updated to '16 KB'"
echo "  7. Note the library names and trace them to dependencies in build.gradle/pubspec.yaml"
echo ""
echo "Common problematic Flutter plugins:"
echo "  - flutter_sound (uses native audio code)"
echo "  - flutter_image_compress (uses native image processing)"
echo "  - audioplayers (uses native audio)"
echo "  - video_player (uses native video codecs)"
echo "  - sqflite/moor_flutter (uses native SQLite)"
echo "  - google_maps_flutter (uses native Google Maps SDK)"
echo ""
echo "Analysis complete!"

