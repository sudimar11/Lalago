import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service class for handling Google Play Integrity API calls
/// This replaces SafetyNet attestation with the newer Play Integrity API
class PlayIntegrityService {
  static const MethodChannel _channel =
      MethodChannel('com.lalago.customer/integrity');

  // Your Google Cloud project number - replace with your actual project number
  static const String _projectNumber =
      "YOUR_PROJECT_NUMBER"; // TODO: Replace with your actual project number

  /// Request an integrity token from Google Play Integrity API
  ///
  /// This method creates an IntegrityManager, builds an IntegrityTokenRequest
  /// with your Google Cloud project number, requests the integrity token,
  /// and handles success/failure responses.
  ///
  /// Returns a Map containing:
  /// - success: boolean indicating if the request was successful
  /// - token: the integrity token (if successful)
  /// - error: error message (if failed)
  /// - message: descriptive message
  static Future<Map<String, dynamic>> requestIntegrityToken(
      {String? customProjectNumber}) async {
    try {
      if (kDebugMode) {
        print('PlayIntegrityService: Requesting integrity token...');
      }

      final String projectNumber = customProjectNumber ?? _projectNumber;

      if (projectNumber == "YOUR_PROJECT_NUMBER") {
        return {
          'success': false,
          'error': 'Project number not configured',
          'message':
              'Please set your Google Cloud project number in PlayIntegrityService'
        };
      }

      // Call the native Android method through platform channel
      final Map<String, dynamic> result = Map<String, dynamic>.from(
          await _channel.invokeMethod('requestIntegrityToken', {
        'projectNumber': projectNumber,
      }));

      if (kDebugMode) {
        print(
            'PlayIntegrityService: Result - ${result['success'] ? 'Success' : 'Failed'}');
        if (!result['success']) {
          print('PlayIntegrityService: Error - ${result['error']}');
        }
      }

      return result;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('PlayIntegrityService: Platform exception - ${e.message}');
      }

      return {
        'success': false,
        'error': e.message ?? 'Unknown platform error',
        'message':
            'Platform exception occurred while requesting integrity token'
      };
    } catch (e) {
      if (kDebugMode) {
        print('PlayIntegrityService: Unexpected error - $e');
      }

      return {
        'success': false,
        'error': e.toString(),
        'message': 'Unexpected error occurred while requesting integrity token'
      };
    }
  }

  /// Verify the integrity of the app and device
  ///
  /// This is a convenience method that requests an integrity token
  /// and returns a simplified boolean result for basic integrity checks
  static Future<bool> verifyIntegrity({String? customProjectNumber}) async {
    final result =
        await requestIntegrityToken(customProjectNumber: customProjectNumber);
    return result['success'] == true && result['token'] != null;
  }

  /// Get detailed integrity information
  ///
  /// This method requests an integrity token and returns detailed information
  /// that can be used for more advanced integrity verification
  static Future<IntegrityResult> getIntegrityDetails(
      {String? customProjectNumber}) async {
    final result =
        await requestIntegrityToken(customProjectNumber: customProjectNumber);

    return IntegrityResult(
      isValid: result['success'] == true,
      token: result['token'],
      error: result['error'],
      message: result['message'],
    );
  }
}

/// Data class to hold integrity verification results
class IntegrityResult {
  final bool isValid;
  final String? token;
  final String? error;
  final String? message;

  const IntegrityResult({
    required this.isValid,
    this.token,
    this.error,
    this.message,
  });

  @override
  String toString() {
    return 'IntegrityResult(isValid: $isValid, hasToken: ${token != null}, error: $error, message: $message)';
  }
}
