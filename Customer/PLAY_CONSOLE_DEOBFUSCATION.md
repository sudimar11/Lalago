# Play Console deobfuscation + SIGABRT diagnosis (Customer)

## Why you need this
If `minifyEnabled` is on, Play Console crashes can appear as obfuscated frames like
`[base.apk] U4.n.a`. Without the **R8 mapping file**, you cannot tell which
class/method actually crashed.

## 1) Build release
From `Customer/`:

```bash
flutter build appbundle --release
```

This generates (paths may vary slightly by tooling):
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- Mapping: `build/app/outputs/mapping/release/mapping.txt`

## 2) Archive mapping.txt (for Play upload)
From `Customer/android/`:

```bash
./gradlew :app:archivePlayDeobfuscationRelease
```

It will copy `mapping.txt` to:

`Customer/android/app/build/play-deobfuscation/<versionCode>_<versionName>/mapping.txt`

## 3) Upload mapping.txt to Play Console
Upload the archived `mapping.txt` to the **same release artifact**:
- Play Console → the release → **Deobfuscation files** → upload `mapping.txt`

After that, stacks like `U4.n.a` become real class/method names.

## 4) Capture the missing abort reason (SIGABRT)
For SIGABRT you often need the **abort message** (not just the backtrace).
If Play Console doesn’t show `Abort message:`, capture it via logcat.

Run the internal build on a device and capture logs:

```bash
adb logcat -v time | rg -i "Abort message|SIGABRT|JNI DETECTED ERROR|Check failed|FATAL"
```

Paste the `Abort message:` line (or the first `JNI DETECTED ERROR` / `Check failed`)
alongside the deobfuscated stack trace.

## 5) Internal diagnosis build without minify (optional, useful)
To make stacks readable quickly, you can build **release with minify/shrink off**
without changing code:

From `Customer/android/`:

```bash
./gradlew :app:assembleRelease -PenableMinify=false -PenableShrink=false
```

Then reproduce and collect logcat.

