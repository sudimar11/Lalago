#!/bin/bash

# Google Sign-In Test Script for LalaGo Customer
# This script automates the testing process for all three scenarios

echo "======================================"
echo "Google Sign-In Configuration Test"
echo "Project: LalaGo Customer"
echo "======================================"
echo ""

# Check if flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -n 1)"
echo ""

# Function to prompt user
prompt_continue() {
    read -p "$1 (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping..."
        return 1
    fi
    return 0
}

# Test 1: Debug Build
echo "======================================"
echo "TEST 1: Debug Build (flutter run)"
echo "======================================"
echo "Expected SHA-1: EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA"
echo ""

if prompt_continue "Run debug build test?"; then
    echo "🧹 Cleaning project..."
    flutter clean
    
    echo "📦 Getting dependencies..."
    flutter pub get
    
    echo "🚀 Running debug build..."
    echo "⚠️  MANUAL TEST REQUIRED:"
    echo "   1. App should launch on device/emulator"
    echo "   2. Navigate to login screen"
    echo "   3. Click 'Login with Google' button"
    echo "   4. Select Google account"
    echo "   5. Verify successful login"
    echo ""
    
    flutter run
    
    echo ""
    if prompt_continue "Did Google Sign-In work in debug mode?"; then
        echo "✅ Debug build test: PASSED"
    else
        echo "❌ Debug build test: FAILED"
        echo "   Check logs for DEVELOPER_ERROR or sign_in_failed"
    fi
fi

echo ""

# Test 2: Release Build (Local)
echo "======================================"
echo "TEST 2: Release Build (Local APK)"
echo "======================================"
echo "Expected SHA-1: D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E"
echo ""

if prompt_continue "Build and test release APK?"; then
    echo "🧹 Cleaning project..."
    flutter clean
    
    echo "📦 Getting dependencies..."
    flutter pub get
    
    echo "🔨 Building release APK..."
    flutter build apk --release
    
    if [ $? -eq 0 ]; then
        echo "✅ APK built successfully"
        echo "📱 APK location: build/app/outputs/flutter-apk/app-release.apk"
        echo ""
        echo "⚠️  MANUAL INSTALLATION REQUIRED:"
        echo "   1. Connect Android device via USB"
        echo "   2. Enable USB debugging"
        echo "   3. Run: adb install build/app/outputs/flutter-apk/app-release.apk"
        echo "   4. Launch app manually"
        echo "   5. Navigate to login screen"
        echo "   6. Click 'Login with Google' button"
        echo "   7. Select Google account"
        echo "   8. Verify successful login"
        echo ""
        
        if prompt_continue "Did you install and test the APK?"; then
            if prompt_continue "Did Google Sign-In work in release mode?"; then
                echo "✅ Release build test: PASSED"
            else
                echo "❌ Release build test: FAILED"
                echo "   Most common issue: SHA-1 not in Firebase Console"
            fi
        fi
    else
        echo "❌ APK build failed"
    fi
fi

echo ""

# Test 3: App Bundle for Play Store
echo "======================================"
echo "TEST 3: App Bundle (Play Store)"
echo "======================================"
echo ""

if prompt_continue "Build app bundle for Play Store?"; then
    echo "🧹 Cleaning project..."
    flutter clean
    
    echo "📦 Getting dependencies..."
    flutter pub get
    
    echo "🔨 Building app bundle..."
    flutter build appbundle --release
    
    if [ $? -eq 0 ]; then
        echo "✅ App bundle built successfully"
        echo "📦 Bundle location: build/app/outputs/bundle/release/app-release.aab"
        echo ""
        echo "⚠️  PLAY CONSOLE UPLOAD REQUIRED:"
        echo "   1. Go to: https://play.google.com/console"
        echo "   2. Select your app: LalaGo Customer"
        echo "   3. Go to: Testing > Internal testing (or Closed testing)"
        echo "   4. Create new release"
        echo "   5. Upload: build/app/outputs/bundle/release/app-release.aab"
        echo "   6. Complete release to testers"
        echo "   7. Wait for processing (5-20 minutes)"
        echo "   8. Install from Play Store link"
        echo "   9. Test Google Sign-In"
        echo ""
        echo "🔍 IMPORTANT: Check App Signing Certificate"
        echo "   1. In Play Console: Setup > App Signing"
        echo "   2. Find 'App signing key certificate'"
        echo "   3. Copy SHA-1 fingerprint"
        echo "   4. Verify it's in Firebase Console"
        echo "   5. If not, add it to Firebase and re-download google-services.json"
        echo ""
        
        if prompt_continue "Did you upload to Play Store and test?"; then
            if prompt_continue "Did Google Sign-In work from Play Store install?"; then
                echo "✅ Play Store build test: PASSED"
            else
                echo "❌ Play Store build test: FAILED"
                echo "   Check Play Console SHA-1 is in Firebase Console"
            fi
        fi
    else
        echo "❌ App bundle build failed"
    fi
fi

echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo ""
echo "✅ = Passed | ❌ = Failed | ⏭️  = Skipped"
echo ""
echo "Debug Build:        (Check above for result)"
echo "Release APK:        (Check above for result)"
echo "Play Store Bundle:  (Check above for result)"
echo ""
echo "📋 For detailed configuration, see:"
echo "   - GOOGLE_SIGNIN_AUDIT_REPORT.md"
echo "   - FIREBASE_SHA_COMPARISON.md"
echo ""
echo "======================================"
