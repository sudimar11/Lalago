package com.lalago.customer.android;

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.integrity.IntegrityManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.IntegrityTokenResponse
import com.google.android.gms.tasks.Task
import android.util.Log

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.lalago.customer/integrity"
    private lateinit var integrityManager: IntegrityManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize IntegrityManager
        integrityManager = IntegrityManagerFactory.create(applicationContext)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestIntegrityToken" -> {
                    val projectNumber = call.argument<String>("projectNumber")
                    if (projectNumber != null) {
                        requestIntegrityToken(projectNumber, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Project number is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun requestIntegrityToken(projectNumber: String, result: MethodChannel.Result) {
        // Create an integrity token request
        val integrityTokenRequest = IntegrityTokenRequest.builder()
            .setCloudProjectNumber(projectNumber.toLong())
            .build()
            
        // Request the integrity token
        integrityManager.requestIntegrityToken(integrityTokenRequest)
            .addOnSuccessListener { response: IntegrityTokenResponse ->
                val token = response.token()
                Log.d("PlayIntegrity", "Integrity token obtained successfully")
                result.success(mapOf(
                    "success" to true,
                    "token" to token,
                    "message" to "Integrity token obtained successfully"
                ))
            }
            .addOnFailureListener { exception: Exception ->
                Log.e("PlayIntegrity", "Failed to obtain integrity token", exception)
                result.success(mapOf(
                    "success" to false,
                    "error" to exception.message,
                    "message" to "Failed to obtain integrity token"
                ))
            }
    }
}
