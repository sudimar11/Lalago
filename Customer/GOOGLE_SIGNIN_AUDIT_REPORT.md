# Google Sign-In Configuration Audit Report

**Date:** January 10, 2026  
**Project:** LalaGo Customer (com.lalago.customer.android)  
**Firebase Project:** lalago-v2

---

## 📋 Executive Summary

This audit analyzes the Google Sign-In configuration across **three deployment scenarios**:

1. **Debug Mode** (`flutter run`)
2. **Release Mode** (`flutter run --release`)
3. **Play Store / Internal Testing** (Google Play App Signing)

---

## 🔑 Extracted SHA Fingerprints

### 1. Debug Keystore (`C:\Users\Sudimar\.android\debug.keystore`)

- **SHA-1:** `EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA`
- **SHA-256:** `A0:73:45:5D:0F:A6:83:DA:1F:87:EE:0F:75:1A:D2:5A:F2:3C:52:8B:DC:76:B4:45:B6:6B:56:AA:8B:A2:FC:23`
- **Alias:** `androiddebugkey`
- **Usage:** Local development with `flutter run`

### 2. Release Keystore - lalago-key.jks (Recommended for Play Store)

- **SHA-1:** `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E`
- **SHA-256:** `62:5A:66:34:13:AF:22:17:A7:29:9C:26:92:05:1E:57:38:09:8D:33:23:9C:B9:EB:87:0F:07:62:E9:5A:A9:2F`
- **Alias:** `key0`
- **Created:** June 3, 2025
- **Usage:** Local release builds and Play Store uploads

### 3. Release Keystore - my-release-key.jks (⚠️ Problem Identified)

- **SHA-1:** `32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95`
- **SHA-256:** `AA:8D:35:85:0E:08:73:E3:2C:5B:13:9A:30:5C:F4:B7:D6:83:96:43:49:AA:FD:C0:AF:34:62:B5:75:A0:56:78`
- **Alias:** `my-key-alias`
- **Created:** December 12, 2024
- **⚠️ STATUS:** This is the SHA-1 causing your error (shown in orange in Firebase Console)

---

## 🔍 Current Firebase Configuration Analysis

### OAuth Clients in google-services.json

Looking at lines 102-122, your current configuration has:

**Client 1** (OAuth Type 1 - Android):

- **Client ID:** `916084329397-f4bvnvbqfi9p1kqsq313rnbldq39lk01.apps.googleusercontent.com`
- **Certificate Hash:** `d0a5191f1073ddde22629ecb8511cd66604aea1e`
- **✅ MATCHES:** lalago-key.jks SHA-1

**Client 2** (OAuth Type 1 - Android):

- **Client ID:** `916084329397-scv4cjo16vp6sib7i2uqqjrld04u1p1r.apps.googleusercontent.com`
- **Certificate Hash:** `ea4def1b2ea67bd5f384bf25e8219a3b9ea6b9ea`
- **✅ MATCHES:** debug.keystore SHA-1

**Client 3** (OAuth Type 3 - Web):

- **Client ID:** `916084329397-l5hn2jd8agb8228p3p42pf83jn4lf20b.apps.googleusercontent.com`
- **✅ CORRECT:** Used as `serverClientId` in Flutter code

### ❌ MISSING Configuration

**NOT in google-services.json:**

- **SHA-1:** `32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95` (my-release-key.jks)

---

## ⚠️ ROOT CAUSE OF ERROR

**Error Message:** "Another project contains an OAuth 2.0 client that uses this same SHA-1 fingerprint and package name combination"

**Explanation:**

- The SHA-1 `32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95` from `my-release-key.jks` is registered in **another Firebase/Google Cloud project**
- You're trying to add it to the `lalago-v2` Firebase project, but Google doesn't allow duplicate SHA-1 + package name combinations across projects

**Why it's showing in Firebase Console with orange warning:**

- It was previously added to Firebase Console
- But the OAuth client for it exists in a different Google Cloud project
- Firebase detects this conflict

---

## 📊 Configuration Status Matrix

| Scenario                                    | Keystore           | SHA-1 Status | OAuth Client         | google-services.json | Status                 |
| ------------------------------------------- | ------------------ | ------------ | -------------------- | -------------------- | ---------------------- |
| **Debug** (`flutter run`)                   | debug.keystore     | ✅ Extracted | ✅ Exists            | ✅ Configured        | **READY**              |
| **Release Local** (`flutter run --release`) | lalago-key.jks     | ✅ Extracted | ✅ Exists            | ✅ Configured        | **READY**              |
| **Play Store**                              | Depends on config  | ⚠️ Unknown   | ❓ TBD               | ❓ TBD               | **NEEDS VERIFICATION** |
| **my-release-key.jks**                      | my-release-key.jks | ⚠️ Conflict  | ❌ Different project | ❌ Not configured    | **REMOVE**             |

---

## ✅ Google Sign-In Code Implementation

**Status:** ✅ **PROPERLY IMPLEMENTED**

### Key Findings:

1. **Dependency:** `google_sign_in: ^6.2.1` (pubspec.yaml:23)

2. **Implementation Location:** `lib/services/FirebaseHelper.dart:2420-2498`

3. **Configuration:**

   - Uses Web Client ID: `916084329397-l5hn2jd8agb8228p3p42pf83jn4lf20b.apps.googleusercontent.com`
   - Configured with proper scopes: `['email', 'profile']`
   - Error handling for DEVELOPER_ERROR (SHA-1 mismatch)

4. **UI Integration:** Login button in `lib/ui/login/LoginScreen.dart:169`

5. **Error Handling:** Comprehensive error messages for:
   - Missing SHA-1/SHA-256 fingerprints
   - Invalid credentials
   - Network errors
   - Cancelled sign-in

---

## 🎯 Recommendations

### CRITICAL ACTION ITEMS:

1. **Remove Conflicting SHA-1 from Firebase Console**

   - Go to Firebase Console > Project Settings > Your Android App
   - Remove the orange SHA-1: `32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95`
   - This will resolve the error message

2. **Standardize on lalago-key.jks**

   - Update `build.gradle` to use `lalago-key.jks` instead of `my-release-key.jks`
   - This keystore is already properly configured in Firebase

3. **Verify Play Store App Signing**

   - Check Google Play Console > Setup > App Signing
   - Get the "App signing key certificate" SHA-1 and SHA-256
   - Add these to Firebase Console if different from lalago-key.jks

4. **Download Updated google-services.json**
   - After removing the conflicting SHA-1 from Firebase Console
   - Download the latest google-services.json
   - Replace the current file

### BUILD CONFIGURATION UPDATE NEEDED:

Current `build.gradle` (lines 86-93) uses `my-release-key.jks`:

```groovy
signingConfigs {
    release {
        storeFile file('my-release-key.jks')
        storePassword '071417'
        keyAlias 'my-key-alias'
        keyPassword '071417'
    }
}
```

**Recommended Change:**

```groovy
signingConfigs {
    release {
        storeFile file('lalago-key.jks')
        storePassword '071417'
        keyAlias 'key0'
        keyPassword '071417'
    }
}
```

---

## 🧪 Testing Plan

### Phase 1: Debug Mode Testing

```bash
flutter clean
flutter pub get
flutter run
```

- Test Google Sign-In button
- Expected: Should work with debug.keystore SHA-1

### Phase 2: Release Mode Testing

```bash
flutter clean
flutter build apk --release
flutter install --release
```

- Test Google Sign-In button
- Expected: Should work with lalago-key.jks SHA-1

### Phase 3: Play Store Testing

- Upload build to Internal Testing
- Install from Play Store
- Test Google Sign-In button
- Expected: Should work with Play App Signing certificate

---

## 📝 Next Steps

1. **Immediate (Do Now):**

   - Remove orange SHA-1 from Firebase Console
   - Update build.gradle to use lalago-key.jks
   - Clean and rebuild project

2. **Verification (After Changes):**

   - Test debug build
   - Test release build
   - Check Play Console for App Signing certificate

3. **Final Validation:**
   - Upload to Internal Testing
   - Install and test from Play Store
   - Confirm Google Sign-In works end-to-end

---

## 🔐 Security Notes

- **Never commit keystore files to version control**
- Both keystores are present in `android/app/` directory
- Keystore passwords are visible in `build.gradle` (consider using environment variables)
- Web Client ID is hardcoded in `lib/constants.dart` (acceptable for this use case)

---

## 📞 Support Information

If Google Sign-In fails, check logs for:

- `DEVELOPER_ERROR`: SHA-1 mismatch or missing Web Client ID
- `sign_in_failed`: General configuration issue
- `invalid-credential`: Check Firebase Authentication is enabled

**Firebase Project:** lalago-v2 (ID: 916084329397)
**Package Name:** com.lalago.customer.android

---

**End of Audit Report**
