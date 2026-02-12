# Google Sign-In Configuration Architecture

## 🏗️ System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         LalaGo Customer App                          │
│                    (com.lalago.customer.android)                     │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
         ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
         │ Debug Build  │  │Release Build │  │Play Store    │
         │ flutter run  │  │  Local APK   │  │   Bundle     │
         └──────────────┘  └──────────────┘  └──────────────┘
                │                  │                  │
         Signs with         Signs with        Signs with
                │                  │                  │
                ▼                  ▼                  ▼
         ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
         │debug.keystore│  │lalago-key.jks│  │Play Console  │
         │              │  │              │  │App Signing   │
         └──────────────┘  └──────────────┘  └──────────────┘
                │                  │                  │
         SHA-1: EA:4D         SHA-1: D0:A5      SHA-1: ?????
                │                  │                  │
                └──────────────────┼──────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   Firebase Console           │
                    │   Project: lalago-v2         │
                    │                              │
                    │  ✅ EA:4D:EF:1B:2E:A6:...    │ (debug)
                    │  ✅ D0:A5:19:1F:10:73:...    │ (release)
                    │  ❌ 32:40:E6:8E:5D:4A:...    │ (REMOVE!)
                    └──────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   OAuth 2.0 Clients          │
                    │                              │
                    │  Client 1 (Android):         │
                    │  - For EA:4D SHA-1           │
                    │  - ID: ...scv4cjo...         │
                    │                              │
                    │  Client 2 (Android):         │
                    │  - For D0:A5 SHA-1           │
                    │  - ID: ...f4bvnvb...         │
                    │                              │
                    │  Client 3 (Web):             │
                    │  - serverClientId            │
                    │  - ID: ...l5hn2jd...         │
                    └──────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │  google-services.json        │
                    │  Downloaded from Firebase    │
                    │  Contains all OAuth clients  │
                    └──────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │  Flutter App Code            │
                    │  lib/services/               │
                    │  FirebaseHelper.dart         │
                    │                              │
                    │  GoogleSignIn(               │
                    │    serverClientId: WEB_ID    │
                    │  )                           │
                    └──────────────────────────────┘
```

---

## 🔄 Sign-In Flow

```
User Clicks "Login with Google"
         │
         ▼
┌─────────────────────────────┐
│ GoogleSignIn.signIn()       │
│ - Uses serverClientId       │
│ - Opens Google picker       │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ User Selects Account        │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Google Validates Request    │
│ - Checks package name       │
│ - Checks app signature      │
│ - Extracts SHA-1 from APK   │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Google Looks Up OAuth Client│
│ - Package: com.lalago...    │
│ - SHA-1: (from APK)         │
└─────────────────────────────┘
         │
         ├─────────── Is SHA-1 registered? ─────────┐
         │                                           │
       YES                                          NO
         │                                           │
         ▼                                           ▼
┌─────────────────────┐               ┌─────────────────────────┐
│ Return Auth Token   │               │ Return DEVELOPER_ERROR  │
│ ✅ Success          │               │ ❌ Failed               │
└─────────────────────┘               └─────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Firebase Auth               │
│ signInWithCredential()      │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ User Logged In              │
│ Navigate to Home Screen     │
└─────────────────────────────┘
```

---

## 🔑 Keystore Mapping

### Current Configuration (AFTER our changes)

```
┌─────────────────────────────────────────────────────────────┐
│                  android/app/build.gradle                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  signingConfigs {                                            │
│    release {                                                 │
│      storeFile file('lalago-key.jks')    ← UPDATED!         │
│      keyAlias 'key0'                     ← UPDATED!         │
│      storePassword '071417'                                  │
│      keyPassword '071417'                                    │
│    }                                                         │
│  }                                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────┐
        │   lalago-key.jks          │
        ├───────────────────────────┤
        │ SHA-1:                    │
        │ D0:A5:19:1F:10:73:DD:DE   │
        │ :22:62:9E:CB:85:11:CD:66  │
        │ :60:4A:EA:1E              │
        │                           │
        │ SHA-256:                  │
        │ 62:5A:66:34:13:AF:22:17   │
        │ :A7:29:9C:26:92:05:1E:57  │
        │ :38:09:8D:33:23:9C:B9:EB  │
        │ :87:0F:07:62:E9:5A:A9:2F  │
        │                           │
        │ Alias: key0               │
        │ Created: Jun 3, 2025      │
        └───────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────┐
        │ Firebase Console          │
        │ ✅ Configured             │
        │ ✅ OAuth Client Exists    │
        └───────────────────────────┘
```

### Old Configuration (BEFORE our changes - PROBLEM!)

```
┌─────────────────────────────────────────────────────────────┐
│                  android/app/build.gradle                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  signingConfigs {                                            │
│    release {                                                 │
│      storeFile file('my-release-key.jks')  ← OLD!           │
│      keyAlias 'my-key-alias'               ← OLD!           │
│      storePassword '071417'                                  │
│      keyPassword '071417'                                    │
│    }                                                         │
│  }                                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────┐
        │   my-release-key.jks      │
        ├───────────────────────────┤
        │ SHA-1:                    │
        │ 32:40:E6:8E:5D:4A:6F:6B   │
        │ :5C:24:04:E1:C2:A7:AF:B9  │
        │ :2B:96:A8:95              │
        │                           │
        │ Alias: my-key-alias       │
        │ Created: Dec 12, 2024     │
        └───────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────┐
        │ ⚠️ PROBLEM!               │
        │ SHA-1 exists in           │
        │ DIFFERENT Firebase project│
        │ ❌ Conflict!              │
        └───────────────────────────┘
```

---

## 📊 Configuration Matrix

### What Gets Used When

| Build Type | Command | Keystore | SHA-1 | Firebase Must Have |
|------------|---------|----------|-------|--------------------|
| **Debug** | `flutter run` | debug.keystore | `EA:4D:EF:1B...` | ✅ Yes |
| **Release** | `flutter build apk --release` | lalago-key.jks | `D0:A5:19:1F...` | ✅ Yes |
| **Profile** | `flutter run --profile` | debug.keystore | `EA:4D:EF:1B...` | ✅ Yes |
| **Bundle** | `flutter build appbundle` | lalago-key.jks | `D0:A5:19:1F...` | ✅ Yes (or Play SHA) |

### OAuth Client Mapping

```
┌─────────────────────────────────────────────────────────────────┐
│                   google-services.json                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  "oauth_client": [                                               │
│    {                                                             │
│      "client_id": "916084329397-f4bvnvb...@googleusercontent",  │
│      "client_type": 1,            ← Android OAuth Client        │
│      "android_info": {                                           │
│        "package_name": "com.lalago.customer.android",           │
│        "certificate_hash": "d0a5191f1073ddde..."  ← Release    │
│      }                                                           │
│    },                                                            │
│    {                                                             │
│      "client_id": "916084329397-scv4cjo...@googleusercontent",  │
│      "client_type": 1,            ← Android OAuth Client        │
│      "android_info": {                                           │
│        "package_name": "com.lalago.customer.android",           │
│        "certificate_hash": "ea4def1b2ea67b..."   ← Debug        │
│      }                                                           │
│    },                                                            │
│    {                                                             │
│      "client_id": "916084329397-l5hn2jd...@googleusercontent",  │
│      "client_type": 3             ← Web OAuth Client            │
│    }                              ← Used as serverClientId      │
│  ]                                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   Flutter Code               │
                    │   lib/constants.dart         │
                    ├──────────────────────────────┤
                    │                              │
                    │ GOOGLE_SIGN_IN_WEB_CLIENT_ID │
                    │ = "916084329397-l5hn2jd..."  │
                    │                              │
                    └──────────────────────────────┘
```

---

## 🎯 Problem vs Solution

### ❌ THE PROBLEM

```
my-release-key.jks (SHA-1: 32:40:E6...)
            │
            ├─── Registered in Project A (Unknown)
            │
            └─── Trying to register in Project B (lalago-v2)
                        │
                        └─── ❌ Google says NO! (Duplicate)
```

### ✅ THE SOLUTION

```
Step 1: Remove 32:40:E6... from Firebase Console
        │
        └─── ✅ Conflict resolved

Step 2: Use lalago-key.jks instead
        │
        └─── SHA-1: D0:A5:19:1F... (already in Firebase)
        │
        └─── ✅ Works immediately!
```

---

## 🔒 Security Considerations

### Keystore Storage

```
Current State:
┌─────────────────────────────────────────────┐
│ android/app/                                 │
│   ├─ lalago-key.jks          ⚠️ In repo!    │
│   └─ my-release-key.jks      ⚠️ In repo!    │
└─────────────────────────────────────────────┘

Recommended State:
┌─────────────────────────────────────────────┐
│ android/app/                                 │
│   ├─ lalago-key.jks          ✅ In .gitignore│
│   └─ my-release-key.jks      ✅ In .gitignore│
│                                              │
│ Stored securely:                             │
│   ├─ Password manager                        │
│   ├─ CI/CD secrets                           │
│   └─ Secure cloud storage                    │
└─────────────────────────────────────────────┘
```

### Credentials Management

```
Current: Hardcoded in build.gradle
┌──────────────────────────────┐
│ signingConfigs {             │
│   release {                  │
│     storePassword '071417'   │ ⚠️ Visible!
│     keyPassword '071417'     │ ⚠️ Visible!
│   }                          │
│ }                            │
└──────────────────────────────┘

Recommended: Environment Variables
┌──────────────────────────────┐
│ def keystoreProps = new      │
│   Properties()               │
│ keystoreProps.load(new       │
│   FileInputStream(           │
│     "keystore.properties"))  │
│                              │
│ signingConfigs {             │
│   release {                  │
│     storePassword            │
│       keystoreProps['pass']  │ ✅ Secure!
│   }                          │
│ }                            │
└──────────────────────────────┘
```

---

## 📱 End-to-End Flow (Complete Picture)

```
Developer                         Firebase/Google                Play Store
    │                                    │                            │
    │ 1. Write code                      │                            │
    │ (Google Sign-In button)            │                            │
    │                                    │                            │
    │ 2. Configure Firebase              │                            │
    ├──────── Add SHA-1 ────────────────>│                            │
    │                                    │                            │
    │                                    │ 3. Generate OAuth clients  │
    │                                    │    (Done automatically)    │
    │                                    │                            │
    │ 4. Download google-services.json   │                            │
    │<────────────────────────────────── │                            │
    │                                    │                            │
    │ 5. Build APK/Bundle                │                            │
    │    Signed with lalago-key.jks      │                            │
    │                                    │                            │
    │ 6. Upload to Play Store            │                            │
    ├────────────────────────────────────┼──────────────────────────>│
    │                                    │                            │
    │                                    │                            │ 7. Play Store
    │                                    │                            │    re-signs with
    │                                    │                            │    App Signing key
    │                                    │                            │
    │ 8. User installs app               │                            │
    │<───────────────────────────────────┼────────────────────────────│
    │                                    │                            │
    │ 9. User clicks "Login with Google" │                            │
    ├──────── Auth Request ─────────────>│                            │
    │    (includes SHA-1 from APK)       │                            │
    │                                    │                            │
    │                                    │ 10. Validate:              │
    │                                    │     - Package name ✅      │
    │                                    │     - SHA-1 ✅             │
    │                                    │     - OAuth client ✅      │
    │                                    │                            │
    │ 11. Return auth token              │                            │
    │<────────────────────────────────── │                            │
    │                                    │                            │
    │ 12. User logged in! 🎉             │                            │
    │                                    │                            │
```

---

**Next Step:** Follow instructions in `QUICK_START_TESTING.md` to test all three scenarios!
