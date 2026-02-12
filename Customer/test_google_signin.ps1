# Google Sign-In Test Script for LalaGo Customer (PowerShell)
# This script automates the testing process for all three scenarios

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Google Sign-In Configuration Test" -ForegroundColor Cyan
Write-Host "Project: LalaGo Customer" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check if flutter is installed
try {
	$flutterVersion = flutter --version 2>&1 | Select-Object -First 1
	Write-Host "✅ Flutter found: $flutterVersion" -ForegroundColor Green
}
catch {
	Write-Host "❌ Flutter is not installed or not in PATH" -ForegroundColor Red
	exit 1
}

Write-Host ""

# Function to prompt user
function Prompt-Continue {
	param([string]$message)
	$response = Read-Host "$message (y/n)"
	return $response -eq 'y' -or $response -eq 'Y'
}

# Test 1: Debug Build
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "TEST 1: Debug Build (flutter run)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Expected SHA-1: EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA" -ForegroundColor Yellow
Write-Host ""

if (Prompt-Continue "Run debug build test?") {
	Write-Host "🧹 Cleaning project..." -ForegroundColor Yellow
	flutter clean
    
	Write-Host "📦 Getting dependencies..." -ForegroundColor Yellow
	flutter pub get
    
	Write-Host "🚀 Running debug build..." -ForegroundColor Yellow
	Write-Host "⚠️  MANUAL TEST REQUIRED:" -ForegroundColor Magenta
	Write-Host "   1. App should launch on device/emulator"
	Write-Host "   2. Navigate to login screen"
	Write-Host "   3. Click 'Login with Google' button"
	Write-Host "   4. Select Google account"
	Write-Host "   5. Verify successful login"
	Write-Host ""
    
	flutter run
    
	Write-Host ""
	if (Prompt-Continue "Did Google Sign-In work in debug mode?") {
		Write-Host "✅ Debug build test: PASSED" -ForegroundColor Green
	}
 else {
		Write-Host "❌ Debug build test: FAILED" -ForegroundColor Red
		Write-Host "   Check logs for DEVELOPER_ERROR or sign_in_failed" -ForegroundColor Yellow
	}
}

Write-Host ""

# Test 2: Release Build (Local)
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "TEST 2: Release Build (Local APK)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Expected SHA-1: D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E" -ForegroundColor Yellow
Write-Host ""

if (Prompt-Continue "Build and test release APK?") {
	Write-Host "🧹 Cleaning project..." -ForegroundColor Yellow
	flutter clean
    
	Write-Host "📦 Getting dependencies..." -ForegroundColor Yellow
	flutter pub get
    
	Write-Host "🔨 Building release APK..." -ForegroundColor Yellow
	flutter build apk --release
    
	if ($LASTEXITCODE -eq 0) {
		Write-Host "✅ APK built successfully" -ForegroundColor Green
		Write-Host "📱 APK location: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
		Write-Host ""
		Write-Host "⚠️  MANUAL INSTALLATION REQUIRED:" -ForegroundColor Magenta
		Write-Host "   1. Connect Android device via USB"
		Write-Host "   2. Enable USB debugging"
		Write-Host "   3. Run: adb install build\app\outputs\flutter-apk\app-release.apk"
		Write-Host "   4. Launch app manually"
		Write-Host "   5. Navigate to login screen"
		Write-Host "   6. Click 'Login with Google' button"
		Write-Host "   7. Select Google account"
		Write-Host "   8. Verify successful login"
		Write-Host ""
        
		if (Prompt-Continue "Did you install and test the APK?") {
			if (Prompt-Continue "Did Google Sign-In work in release mode?") {
				Write-Host "✅ Release build test: PASSED" -ForegroundColor Green
			}
			else {
				Write-Host "❌ Release build test: FAILED" -ForegroundColor Red
				Write-Host "   Most common issue: SHA-1 not in Firebase Console" -ForegroundColor Yellow
			}
		}
	}
 else {
		Write-Host "❌ APK build failed" -ForegroundColor Red
	}
}

Write-Host ""

# Test 3: App Bundle for Play Store
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "TEST 3: App Bundle (Play Store)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

if (Prompt-Continue "Build app bundle for Play Store?") {
	Write-Host "🧹 Cleaning project..." -ForegroundColor Yellow
	flutter clean
    
	Write-Host "📦 Getting dependencies..." -ForegroundColor Yellow
	flutter pub get
    
	Write-Host "🔨 Building app bundle..." -ForegroundColor Yellow
	flutter build appbundle --release
    
	if ($LASTEXITCODE -eq 0) {
		Write-Host "✅ App bundle built successfully" -ForegroundColor Green
		Write-Host "📦 Bundle location: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Cyan
		Write-Host ""
		Write-Host "⚠️  PLAY CONSOLE UPLOAD REQUIRED:" -ForegroundColor Magenta
		Write-Host "   1. Go to: https://play.google.com/console"
		Write-Host "   2. Select your app: LalaGo Customer"
		Write-Host "   3. Go to: Testing > Internal testing (or Closed testing)"
		Write-Host "   4. Create new release"
		Write-Host "   5. Upload: build\app\outputs\bundle\release\app-release.aab"
		Write-Host "   6. Complete release to testers"
		Write-Host "   7. Wait for processing (5-20 minutes)"
		Write-Host "   8. Install from Play Store link"
		Write-Host "   9. Test Google Sign-In"
		Write-Host ""
		Write-Host "🔍 IMPORTANT: Check App Signing Certificate" -ForegroundColor Yellow
		Write-Host "   1. In Play Console: Setup > App Signing"
		Write-Host "   2. Find 'App signing key certificate'"
		Write-Host "   3. Copy SHA-1 fingerprint"
		Write-Host "   4. Verify it's in Firebase Console"
		Write-Host "   5. If not, add it to Firebase and re-download google-services.json"
		Write-Host ""
        
		if (Prompt-Continue "Did you upload to Play Store and test?") {
			if (Prompt-Continue "Did Google Sign-In work from Play Store install?") {
				Write-Host "✅ Play Store build test: PASSED" -ForegroundColor Green
			}
			else {
				Write-Host "❌ Play Store build test: FAILED" -ForegroundColor Red
				Write-Host "   Check Play Console SHA-1 is in Firebase Console" -ForegroundColor Yellow
			}
		}
	}
 else {
		Write-Host "❌ App bundle build failed" -ForegroundColor Red
	}
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ = Passed | ❌ = Failed | ⏭️  = Skipped"
Write-Host ""
Write-Host "Debug Build:        (Check above for result)"
Write-Host "Release APK:        (Check above for result)"
Write-Host "Play Store Bundle:  (Check above for result)"
Write-Host ""
Write-Host "📋 For detailed configuration, see:" -ForegroundColor Cyan
Write-Host "   - GOOGLE_SIGNIN_AUDIT_REPORT.md"
Write-Host "   - FIREBASE_SHA_COMPARISON.md"
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
