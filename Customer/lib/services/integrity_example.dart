import 'package:flutter/foundation.dart';
import 'play_integrity_service.dart';

/// Example usage of Play Integrity API
/// This file demonstrates how to use the PlayIntegrityService to replace SafetyNet attestation
class IntegrityExample {
  /// Example 1: Basic integrity check
  /// Use this for simple pass/fail integrity verification
  static Future<void> basicIntegrityCheck() async {
    if (kDebugMode) {
      print('=== Basic Integrity Check Example ===');
    }

    final bool isValid = await PlayIntegrityService.verifyIntegrity();

    if (isValid) {
      if (kDebugMode) {
        print('✅ Device and app integrity verified');
      }
      // Proceed with sensitive operations
    } else {
      if (kDebugMode) {
        print('❌ Integrity verification failed');
      }
      // Handle integrity failure (e.g., block sensitive operations)
    }
  }

  /// Example 2: Detailed integrity verification
  /// Use this when you need more information about the integrity result
  static Future<void> detailedIntegrityCheck() async {
    if (kDebugMode) {
      print('=== Detailed Integrity Check Example ===');
    }

    final IntegrityResult result =
        await PlayIntegrityService.getIntegrityDetails();

    if (result.isValid) {
      if (kDebugMode) {
        print('✅ Integrity verification successful');
        print('Token available: ${result.token != null}');
        print('Message: ${result.message}');
      }

      // You can now use the token for server-side verification
      // Send result.token to your backend for verification with Google's servers
    } else {
      if (kDebugMode) {
        print('❌ Integrity verification failed');
        print('Error: ${result.error}');
        print('Message: ${result.message}');
      }

      // Handle different types of failures
      if (result.error?.contains('Project number not configured') == true) {
        // Configuration error
        if (kDebugMode) {
          print('⚠️ Please configure your Google Cloud project number');
        }
      } else {
        // Actual integrity failure
        if (kDebugMode) {
          print('⚠️ Device or app integrity compromised');
        }
      }
    }
  }

  /// Example 3: Custom project number
  /// Use this if you need to use a different project number than the default
  static Future<void> customProjectIntegrityCheck(String projectNumber) async {
    if (kDebugMode) {
      print('=== Custom Project Integrity Check Example ===');
    }

    final result = await PlayIntegrityService.requestIntegrityToken(
        customProjectNumber: projectNumber);

    if (result['success']) {
      if (kDebugMode) {
        print('✅ Custom project integrity check passed');
      }
    } else {
      if (kDebugMode) {
        print('❌ Custom project integrity check failed: ${result['error']}');
      }
    }
  }

  /// Example 4: Integration with authentication flow
  /// Use this pattern to verify integrity before sensitive authentication operations
  static Future<bool> verifyIntegrityForAuth() async {
    if (kDebugMode) {
      print('=== Authentication Integrity Check ===');
    }

    // Check integrity before proceeding with authentication
    final IntegrityResult result =
        await PlayIntegrityService.getIntegrityDetails();

    if (!result.isValid) {
      if (kDebugMode) {
        print('❌ Cannot proceed with authentication - integrity check failed');
        print('Reason: ${result.error}');
      }
      return false;
    }

    if (kDebugMode) {
      print('✅ Integrity verified - safe to proceed with authentication');
    }

    // Optional: Send token to your backend for server-side verification
    // await sendTokenToBackend(result.token);

    return true;
  }

  /// Example 5: Integration with payment flow
  /// Use this pattern to verify integrity before processing payments
  static Future<bool> verifyIntegrityForPayment() async {
    if (kDebugMode) {
      print('=== Payment Integrity Check ===');
    }

    final IntegrityResult result =
        await PlayIntegrityService.getIntegrityDetails();

    if (!result.isValid) {
      if (kDebugMode) {
        print('❌ Cannot proceed with payment - integrity check failed');
        print('This could indicate a compromised device or app tampering');
      }
      return false;
    }

    if (kDebugMode) {
      print('✅ Integrity verified - safe to proceed with payment');
    }

    return true;
  }
}

/// Migration guide from SafetyNet to Play Integrity
/// 
/// OLD SafetyNet pattern:
/// ```dart
/// // SafetyNet (deprecated)
/// final SafetyNetResponse response = await SafetyNet.requestAttestation(nonce);
/// if (response.isSuccess) {
///   // Process attestation
/// }
/// ```
/// 
/// NEW Play Integrity pattern:
/// ```dart
/// // Play Integrity (recommended)
/// final IntegrityResult result = await PlayIntegrityService.getIntegrityDetails();
/// if (result.isValid) {
///   // Process integrity verification
/// }
/// ```
/// 
/// Key differences:
/// 1. No nonce required - Play Integrity generates its own challenges
/// 2. More comprehensive device and app integrity checks
/// 3. Better protection against various attack vectors
/// 4. Integrated with Google Play services for better reliability
/// 5. Server-side verification through Google's API endpoints
