# android/app/proguard-rules.pro

# Ignore *all* R8 warnings (including missing classes)
-ignorewarnings

# Suppress specifically the android.window.BackEvent reference
-dontwarn android.window.BackEvent

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }

# Keep Google Maps classes
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.**

# Keep Geocoding classes
-keep class com.baseflow.geocoding.** { *; }
-dontwarn com.baseflow.geocoding.**

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Flutter classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# path_provider_android (Pigeon) - avoid channel errors in release
-keep class io.flutter.plugins.pathprovider.** { *; }

# shared_preferences_android (Pigeon)
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# workmanager
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# geolocator_android / Geolocator plugin (needed in release for permission dialog)
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# permission_handler (needed in release for permission dialog)
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# location (lyokone) plugin
-keep class com.lyokone.location.** { *; }
-dontwarn com.lyokone.location.**

# flutter_inappwebview (transitive from flutterwave_standard) - ensure class
# loads in release so plugin registration does not fail
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**