# Firebase SHA Fingerprint Comparison & Configuration

## 📊 SHA Fingerprint Mapping

### Current Configuration in Firebase (google-services.json)

| Keystore           | SHA-1 (lowercase)                          | SHA-256 (lowercase)                                                 | OAuth Client ID                                                            | Status        |
| ------------------ | ------------------------------------------ | ------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------- |
| **lalago-key.jks** | `d0a5191f1073ddde22629ecb8511cd66604aea1e` | `625a663413af2217a7299c2692051e5738098d33239cb9eb870f076209e5aa92f` | `916084329397-f4bvnvbqfi9p1kqsq313rnbldq39lk01.apps.googleusercontent.com` | ✅ **ACTIVE** |
| **debug.keystore** | `ea4def1b2ea67bd5f384bf25e8219a3b9ea6b9ea` | `a073455d0fa683da1f87ee0f751ad25af23c528bdc76b445b66b56aa8ba2fc23`  | `916084329397-scv4cjo16vp6sib7i2uqqjrld04u1p1r.apps.googleusercontent.com` | ✅ **ACTIVE** |
| **Web Client**     | N/A                                        | N/A                                                                 | `916084329397-l5hn2jd8agb8228p3p42pf83jn4lf20b.apps.googleusercontent.com` | ✅ **ACTIVE** |

### Conflicting Keystore (NOT CONFIGURED - CAUSING ERROR)

| Keystore               | SHA-1 (lowercase)                          | Status          | Action Required                     |
| ---------------------- | ------------------------------------------ | --------------- | ----------------------------------- |
| **my-release-key.jks** | `3240e68e5d4a6f6b5c2404e1c2a7afb92b96a895` | ⚠️ **CONFLICT** | ❌ **REMOVE FROM FIREBASE CONSOLE** |

## 🎯 What You Need to Do in Firebase Console

### Step 1: Access Firebase Console

1. Go to https://console.firebase.google.com/
2. Select project: **lalago-v2**
3. Go to **Project Settings** (gear icon)
4. Scroll to **Your apps** section
5. Find app: **com.lalago.customer.android**

### Step 2: Review SHA Certificate Fingerprints

You should see **3 fingerprints** currently configured:

✅ **Keep These TWO:**

```
SHA-1: D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E
(from lalago-key.jks - for release builds)

SHA-1: EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA
(from debug.keystore - for debug builds)
```

❌ **REMOVE This ONE (Orange Warning):**

```
SHA-1: 32:40:E6:8E:5D:4A:6F:6B:5C:24:04:E1:C2:A7:AF:B9:2B:96:A8:95
(from my-release-key.jks - CAUSING CONFLICT)
```

### Step 3: Remove Conflicting SHA-1

1. Click on the **orange SHA-1** with warning triangle
2. Click **Delete** or **Remove**
3. Confirm deletion

### Step 4: Verify Remaining Configuration

After removal, you should have:

- ✅ **2 SHA-1 fingerprints** (lalago-key.jks + debug.keystore)
- ✅ **2 SHA-256 fingerprints** (corresponding to above)
- ✅ No orange warnings

### Step 5: Add Play Store App Signing Certificate (If Needed)

**IMPORTANT:** If you're using Google Play App Signing:

1. Go to **Google Play Console** > Your App > **Setup** > **App Signing**
2. Under "App signing key certificate", copy the **SHA-1** and **SHA-256**
3. Go back to Firebase Console
4. Click **Add fingerprint**
5. Add both SHA-1 and SHA-256 from Play Console
6. Save

### Step 6: Download Updated google-services.json

After making changes:

1. In Firebase Console, click **Download google-services.json**
2. Replace your current file at: `android/app/google-services.json`
3. Delete any backup files like `google-services (3).json`

## 🔍 How to Verify Play Console App Signing Certificate

### Option A: Via Google Play Console (Recommended)

```
1. Go to https://play.google.com/console
2. Select: LalaGo Customer app
3. Navigate to: Setup > App Signing
4. Find section: "App signing key certificate"
5. Copy the SHA-1 certificate fingerprint
6. Copy the SHA-256 certificate fingerprint
```

**If SHA-1 matches lalago-key.jks:** ✅ You're already configured!  
**If SHA-1 is different:** ⚠️ Add it to Firebase Console

### Option B: Via Command Line (After Upload)

If you've already uploaded a bundle to Play Store:

```bash
# The Play Console will show you the certificate
# under Release > Setup > App Signing
```

## 📝 Current Status Summary

### ✅ COMPLETED ACTIONS:

1. ✅ Extracted all SHA fingerprints from keystores
2. ✅ Identified conflicting SHA-1 (my-release-key.jks)
3. ✅ Updated build.gradle to use lalago-key.jks
4. ✅ Verified Google Sign-In code implementation
5. ✅ Mapped SHA fingerprints to OAuth clients

### ⏳ PENDING ACTIONS (Require User):

1. ⏳ **Remove conflicting SHA-1 from Firebase Console** (Step 2-3 above)
2. ⏳ **Verify Play Console App Signing certificate** (if using Play App Signing)
3. ⏳ **Download updated google-services.json** (Step 6 above)
4. ⏳ **Test Google Sign-In in Debug mode**
5. ⏳ **Test Google Sign-In in Release mode**
6. ⏳ **Test Google Sign-In from Play Store build**

## 🧪 Testing Checklist

After completing Firebase Console changes, test these scenarios:

### Test 1: Debug Build

```bash
cd C:\LalaGo-Customer
flutter clean
flutter pub get
flutter run
```

- [ ] App launches successfully
- [ ] "Login with Google" button is visible
- [ ] Click button - Google account picker appears
- [ ] Select account - Sign in succeeds
- [ ] User is authenticated and redirected

**Expected SHA-1:** `EA:4D:EF:1B:2E:A6:7B:D5:F3:84:BF:25:E8:21:9A:3B:9E:A6:B9:EA`

### Test 2: Release Build (Local)

```bash
flutter clean
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

- [ ] APK installs successfully
- [ ] Launch app manually
- [ ] "Login with Google" button is visible
- [ ] Click button - Google account picker appears
- [ ] Select account - Sign in succeeds
- [ ] User is authenticated and redirected

**Expected SHA-1:** `D0:A5:19:1F:10:73:DD:DE:22:62:9E:CB:85:11:CD:66:60:4A:EA:1E`

### Test 3: Play Store Build (Internal Testing)

```bash
flutter clean
flutter build appbundle --release
```

1. Upload to Play Console > Internal Testing
2. Wait for processing
3. Install from Play Store link
4. Test Google Sign-In

- [ ] Install from Play Store succeeds
- [ ] "Login with Google" button is visible
- [ ] Click button - Google account picker appears
- [ ] Select account - Sign in succeeds
- [ ] User is authenticated and redirected

**Expected SHA-1:** Check Play Console > App Signing

## ⚠️ Troubleshooting

### Error: "DEVELOPER_ERROR"

**Cause:** SHA-1 fingerprint mismatch  
**Solution:**

1. Verify which keystore was used to sign the APK
2. Check that SHA-1 is in Firebase Console
3. Rebuild app after adding SHA-1

### Error: "sign_in_failed"

**Cause:** General configuration issue  
**Solution:**

1. Verify Web Client ID is correct in `lib/constants.dart`
2. Check google-services.json is up to date
3. Run `flutter clean && flutter pub get`

### Error: "API has not been used in project..."

**Cause:** Google Sign-In API not enabled  
**Solution:**

1. Go to Google Cloud Console
2. Enable "Google+ API" or "People API"
3. Wait 5-10 minutes for propagation

## 🔐 Security Recommendations

### Current Issues:

- ⚠️ Keystore passwords hardcoded in build.gradle
- ⚠️ Keystores committed to repository (visible in file list)

### Recommended Actions:

```groovy
// In build.gradle, use:
def keystorePropertiesFile = rootProject.file("keystore.properties")
def keystoreProperties = new Properties()
keystoreProperties.load(new FileInputStream(keystorePropertiesFile))

signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile file(keystoreProperties['storeFile'])
        storePassword keystoreProperties['storePassword']
    }
}
```

Create `android/keystore.properties`:

```properties
storePassword=071417
keyPassword=071417
keyAlias=key0
storeFile=lalago-key.jks
```

Add to `.gitignore`:

```
android/keystore.properties
android/app/*.jks
android/app/*.keystore
```

## 📞 Next Steps

1. **Immediate:** Remove conflicting SHA-1 from Firebase Console
2. **Verification:** Download updated google-services.json
3. **Testing:** Run all 3 test scenarios
4. **Deployment:** Upload to Play Store Internal Testing
5. **Final Check:** Test from actual Play Store install

---

**Questions or Issues?**  
Refer back to GOOGLE_SIGNIN_AUDIT_REPORT.md for detailed analysis.
