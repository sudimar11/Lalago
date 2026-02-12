# 🚀 QUICK START GUIDE: Google Sign-In Testing

**IMPORTANT:** Before running tests, complete the Firebase Console setup below!

---

## ⚠️ CRITICAL: Firebase Console Setup (DO THIS FIRST!)

### The Problem

You're seeing this error:
> "Another project contains an OAuth 2.0 client that uses this same SHA-1 fingerprint and package name combination"

This is because `my-release-key.jks` SHA-1 is registered in a different Firebase/Google Cloud project.

### The Solution: 3 Steps

#### Step 1: Open Firebase Console

1. Go to: https://console.firebase.google.com/
2. Select project: **lalago-v2**
3. Click ⚙️ **Project Settings**
4. Scroll to **Your apps**
5. Click on **com.lalago.customer.android** (Android icon)

#### Step 2: Remove Conflicting SHA-1

In the **SHA certificate fingerprints** section, you'll see 3 fingerprints.

Find and **DELETE** this one (it will have an orange warning ⚠️):

```
32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95
```

**How to delete:**
- Click the SHA-1 fingerprint
- Click the **trash/delete icon** or **Remove** button
- Confirm deletion

#### Step 3: Verify Remaining Configuration

After deletion, you should have **exactly 2 SHA-1 fingerprints**:

✅ **Keep:** `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E`  
   (lalago-key.jks - for release builds)

✅ **Keep:** `EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA`  
   (debug.keystore - for debug builds)

**No orange warnings should appear!**

---

## 🎯 What We've Already Done For You

✅ **Extracted all SHA fingerprints** from your keystores  
✅ **Identified the conflicting keystore** (my-release-key.jks)  
✅ **Updated build.gradle** to use lalago-key.jks instead  
✅ **Verified Google Sign-In code** is properly implemented  
✅ **Created test scripts** for automated testing  

---

## 🧪 Testing Process (After Firebase Setup)

### Option A: Automated Testing (Recommended for Windows)

Run the PowerShell test script:

```powershell
cd C:\LalaGo-Customer
.\test_google_signin.ps1
```

This script will:
- Guide you through testing debug, release, and Play Store builds
- Prompt you at each step
- Show expected SHA-1 for each scenario
- Help verify results

### Option B: Manual Testing

#### Test 1: Debug Build

```bash
flutter clean
flutter pub get
flutter run
```

**In the app:**
1. Navigate to login screen
2. Click "Login with Google"
3. Select your Google account
4. Verify successful login

**Expected Result:** ✅ Login succeeds

**If it fails:** Check that `EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA` is in Firebase Console

---

#### Test 2: Release Build (Local APK)

```bash
flutter clean
flutter pub get
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

**On the device:**
1. Open the installed app
2. Navigate to login screen
3. Click "Login with Google"
4. Select your Google account
5. Verify successful login

**Expected Result:** ✅ Login succeeds

**If it fails:** Check that `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E` is in Firebase Console

---

#### Test 3: Play Store Build

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

**Upload to Play Console:**
1. Go to: https://play.google.com/console
2. Select: LalaGo Customer
3. Navigate: Testing > Internal testing
4. Create new release
5. Upload: `build/app/outputs/bundle/release/app-release.aab`
6. Complete release

**Check App Signing Certificate:**
1. In Play Console: Setup > App Signing
2. Find "App signing key certificate"
3. Copy the SHA-1 fingerprint
4. **Compare with lalago-key.jks:** `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E`

**If SHA-1 matches:** ✅ You're good! No action needed.

**If SHA-1 is different:** 
1. Go back to Firebase Console
2. Click "Add fingerprint"
3. Add the Play Console SHA-1
4. Download updated google-services.json
5. Replace at: `android/app/google-services.json`
6. Rebuild and re-upload

**Install from Play Store:**
1. Use the Internal Testing link
2. Install the app
3. Test Google Sign-In

**Expected Result:** ✅ Login succeeds

---

## 🔍 Troubleshooting

### Error: "DEVELOPER_ERROR"

**Cause:** SHA-1 fingerprint not in Firebase Console

**Solution:**
1. Check which keystore signed the APK
2. Run: `keytool -list -v -keystore android/app/lalago-key.jks -storepass 071417 -alias key0`
3. Verify SHA-1 is in Firebase Console
4. If not, add it and rebuild

---

### Error: "sign_in_failed"

**Cause:** Configuration issue

**Solution:**
1. Verify `google-services.json` is up to date
2. Run: `flutter clean && flutter pub get`
3. Rebuild app

---

### Error: "API has not been used in project..."

**Cause:** Google Sign-In API not enabled

**Solution:**
1. Go to: https://console.cloud.google.com/
2. Select project: lalago-v2
3. Enable "Google People API" or "Google Sign-In API"
4. Wait 5-10 minutes

---

## 📋 Quick Reference

### SHA-1 Fingerprints Cheat Sheet

| Scenario | Keystore | SHA-1 |
|----------|----------|-------|
| **Debug** | debug.keystore | `EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA` |
| **Release** | lalago-key.jks | `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E` |
| **Play Store** | Check Play Console | Should match lalago-key.jks or be added to Firebase |

### Important Links

- **Firebase Console:** https://console.firebase.google.com/
- **Play Console:** https://play.google.com/console
- **Google Cloud Console:** https://console.cloud.google.com/

### Files Changed

- ✅ `android/app/build.gradle` - Updated to use lalago-key.jks
- ✅ `GOOGLE_SIGNIN_AUDIT_REPORT.md` - Comprehensive audit
- ✅ `FIREBASE_SHA_COMPARISON.md` - Detailed comparison
- ✅ `test_google_signin.ps1` - Automated test script (Windows)
- ✅ `test_google_signin.sh` - Automated test script (Mac/Linux)

---

## ✅ Checklist

Before declaring success, verify:

- [ ] Removed conflicting SHA-1 from Firebase Console
- [ ] Verified 2 SHA-1 fingerprints remain (debug + release)
- [ ] No orange warnings in Firebase Console
- [ ] Google Sign-In works in debug mode
- [ ] Google Sign-In works in release APK
- [ ] Google Sign-In works from Play Store install

---

## 🆘 Need Help?

If all three scenarios don't work:

1. **Check Firebase Console:**
   - Verify SHA-1 fingerprints are correctly added
   - Check that Google Sign-In is enabled in Authentication

2. **Check google-services.json:**
   - Should have 2 OAuth clients (type 1) for debug and release
   - Should have 1 OAuth client (type 3) for web

3. **Check logs:**
   - Look for DEVELOPER_ERROR in console
   - Check for specific error codes

4. **Review audit reports:**
   - `GOOGLE_SIGNIN_AUDIT_REPORT.md` - Full analysis
   - `FIREBASE_SHA_COMPARISON.md` - Configuration details

---

**Ready to test? Complete the Firebase Console setup above, then run the test script!**

```powershell
.\test_google_signin.ps1
```
