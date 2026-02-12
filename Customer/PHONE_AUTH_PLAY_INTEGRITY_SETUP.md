# Play Integrity setup for Phone Login

Firebase Phone Auth uses **Play Integrity API** (or reCAPTCHA) to verify that sign-in requests come from your app. The error `missing-client-identifier` means this verification failed. Follow these steps so Play Integrity can identify your app.

## Prerequisites

- SHA-1 and SHA-256 already added in **Firebase Console** (Project settings → Your apps → Customer app). ✓ You confirmed this.
- The same Google Cloud project is used by Firebase and (after linking) by Play Console.

---

## Step 1: Have your app in Google Play Console

Play Integrity only works for apps that exist in Google Play Console (even if not publicly released).

1. Go to [Google Play Console](https://play.google.com/console/).
2. Sign in with the same Google account that owns your Firebase project.
3. If your **Customer** app is not there yet:
   - Click **Create app** (or **Add app**).
   - Fill in app name, default language, and type (e.g. App).
   - Complete the required setup (e.g. App access, Ads declaration if needed). You can use **Internal testing** so the app does not need to be public.
4. If the app is already there, open it and continue below.

---

## Step 2: Link your Cloud project in Play Console (required)

This links the **same** Google Cloud project that Firebase uses so Play Integrity can issue tokens for your app.

1. In **Play Console**, select your **Customer** app.
2. In the left menu go to: **Release** → **Setup** → **App integrity**  
   (On some layouts: **Release** → **App integrity**.)
3. Find the **Play Integrity API** section.
4. Click **Link Cloud project** (or **Link** / **Set up**).
5. In the list, select the **Google Cloud project** that your Firebase project uses.  
   - To see which project that is: **Firebase Console** → Project settings (gear) → under "Your apps" the project ID is shown; the **Project number** is in the General tab. The same project appears in the "Link Cloud project" list (by name or ID).
6. Confirm linking.  
   - You must be an **Owner** of that Cloud project. If you don’t see it, use an account that is Owner.

After this, Play Integrity can associate your app (and its signing key) with your Firebase/Cloud project.

---

## Step 3: Enable Play Integrity API in Google Cloud (if needed)

Sometimes the API must be enabled in the Cloud project.

1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Select the **same project** as your Firebase project.
3. Open **APIs & services** → **Library** (or go to [APIs & Services – Library](https://console.cloud.google.com/apis/library)).
4. Search for **Play Integrity API**.
5. Open it and click **Enable** if it is not already enabled.

---

## Step 4: Use the correct signing key

- **Debug builds (e.g. from Android Studio):**  
  Use the **debug** keystore SHA-1 and SHA-256. Add them in Firebase Console for your Customer Android app.  
  Get debug fingerprints:
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
- **Release / Play builds:**  
  Use the SHA-1 and SHA-256 from the keystore you use to build the app (e.g. `my-release-key.jks` or the one Play uses). Add those in Firebase Console.  
  You already have a script: from `Customer/android` run the PowerShell script or the Gradle task that prints SHA-1 and SHA-256.

If you test with both debug and release, add **both** sets of fingerprints in Firebase.

---

## Step 5: Test again

1. Rebuild and reinstall the Customer app (so it uses the same signing key as the fingerprints in Firebase).
2. On a **real Android device** with **Google Play services** (not an emulator without Play), open the app and try **Login with Phone Number** again.
3. If you still see `missing-client-identifier`, check:
   - Play Console: **App integrity** → Play Integrity API shows your project as **Linked**.
   - Firebase: Project settings → Your apps → Customer app has the correct SHA-1 and SHA-256 for the build you are running.
   - You are testing on a real device with Google Play services.

---

## Summary checklist

- [ ] App exists in Google Play Console (e.g. Internal testing).
- [ ] **Release** → **App integrity** → **Play Integrity API** → **Link Cloud project** → same project as Firebase.
- [ ] Play Integrity API enabled in Google Cloud Console (same project).
- [ ] SHA-1 and SHA-256 for the build you use (debug or release) added in Firebase Console.
- [ ] Test on a real device with Google Play services.

No code changes are required for this; it is all configuration in Play Console, Cloud Console, and Firebase Console.
