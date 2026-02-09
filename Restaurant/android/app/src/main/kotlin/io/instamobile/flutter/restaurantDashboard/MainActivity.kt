package com.foodies.restaurant.android

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.google.android.gms.security.ProviderInstaller
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val TAG = "TLS"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ensure modern TLS provider is installed
        ProviderInstaller.installIfNeededAsync(this, object : ProviderInstaller.ProviderInstallListener {
            override fun onProviderInstalled() {
                Log.i(TAG, "✅ Security provider installed")
            }

            override fun onProviderInstallFailed(errorCode: Int, recoveryIntent: Intent?) {
                Log.e(TAG, "❗ Provider install failed: $errorCode")
                // You can prompt the user to update Google Play services if needed
            }
        })
    }
	
	
}
