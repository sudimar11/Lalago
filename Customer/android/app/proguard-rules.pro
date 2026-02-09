-keep class android.window.BackEvent { *; }
-dontwarn android.window.BackEvent

# SafetyNet suppression - exclude SafetyNet but allow R8 to proceed
# SafetyNet is deprecated and excluded; only Play Integrity is active
-dontwarn com.google.android.gms.safetynet.**
-dontwarn com.google.firebase.appcheck.safetynet.**

# Play Integrity API keep rules
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Keep Play Integrity related classes
-keep class * extends com.google.android.play.core.integrity.IntegrityTokenRequest { *; }
-keep class * extends com.google.android.play.core.integrity.IntegrityTokenResponse { *; }
-keep class * extends com.google.android.play.core.integrity.IntegrityManager { *; }

# Keep Google Play Services classes used by Play Integrity
-keep class com.google.android.gms.tasks.OnCompleteListener { *; }
-keep class com.google.android.gms.tasks.OnFailureListener { *; }
-keep class com.google.android.gms.tasks.OnSuccessListener { *; }
-keep class com.google.android.gms.tasks.Task { *; }

# Keep all public methods in Play Integrity classes
-keepclassmembers class com.google.android.play.core.integrity.** {
    public *;
}

# Prevent obfuscation of Play Integrity API calls
-keepnames class com.google.android.play.core.integrity.** { *; }

# ML Kit Barcode Scanning keep rules
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**

# Keep specific ML Kit classes
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }

# Keep ML Kit Vision common classes
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }

# Keep barcode format and value type enums
-keep enum com.google.mlkit.vision.barcode.common.Barcode$BarcodeFormat { *; }
-keep enum com.google.mlkit.vision.barcode.common.Barcode$BarcodeValueType { *; }

# Keep all barcode detection related classes
-keep class com.google.mlkit.vision.barcode.common.Barcode { *; }
-keep class com.google.mlkit.vision.barcode.common.Barcode$* { *; }
-keep class com.google.mlkit.vision.barcode.BarcodeScanner { *; }
-keep class com.google.mlkit.vision.barcode.BarcodeScannerOptions { *; }
-keep class com.google.mlkit.vision.barcode.BarcodeScanning { *; }

# OkHttp3 SSL platform classes (optional providers not available on Android)
-dontwarn org.bouncycastle.jsse.BCSSLParameters
-dontwarn org.bouncycastle.jsse.BCSSLSocket
-dontwarn org.bouncycastle.jsse.provider.BouncyCastleJsseProvider
-dontwarn org.conscrypt.Conscrypt$Version
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.ConscryptHostnameVerifier
-dontwarn org.openjsse.javax.net.ssl.SSLParameters
-dontwarn org.openjsse.javax.net.ssl.SSLSocket
-dontwarn org.openjsse.net.ssl.OpenJSSE

# Moor/Drift Database keep rules
# Keep all generated database classes
-keep class **.*Database { *; }
-keep class **.*Database$* { *; }

# Keep all generated table classes
-keep class **.*Table { *; }
-keep class **.*Table$* { *; }

# Keep all generated data classes
-keep class **.*DataClass { *; }
-keep class **.*DataClass$* { *; }

# Keep Moor/Drift runtime classes
-keep class drt.** { *; }
-keep class moor.** { *; }

# Keep generated database entities
-keep class * extends drt.GeneratedDatabase { *; }
-keep class * extends moor.GeneratedDatabase { *; }

# Keep database query classes
-keep class * extends drt.QueryEngine { *; }
-keep class * extends moor.QueryEngine { *; }

# Keep all classes in your localDatabase.g.dart file
-keep class foodie_customer.services.localDatabase.** { *; }

# Keep all classes with @UseMoor annotation
-keep @moor.UseMoor class * { *; }
-keep @drift.UseDrift class * { *; }

# Keep all methods used by Moor/Drift for streams
-keepclassmembers class * {
    java.util.stream.Stream *;
}

# Keep reflection-accessed members
-keepattributes *Annotation*, Signature, Exception

# Keep inner classes for generated code
-keepclassmembers class *$* {
    *;
}

# Flutter Local Notifications - prevent native crash on ARM64
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.** { *; }

# Prevent R8 from stripping native method stubs
-keepclasseswithmembernames class * {
    native <methods>;
}