import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class BackendService {
  static const String baseUrl =
      'https://your-backend-url.com/api/v1'; // Update with your backend URL

  /// Gets the Firebase ID token for authentication
  static Future<String?> _getFirebaseIdToken(
      {bool forceRefresh = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken(forceRefresh);
      }
    } catch (e) {
      print('❌ Error getting Firebase ID token: $e');
    }
    return null;
  }

  /// Creates authenticated headers with Firebase ID token
  static Future<Map<String, String>> _getAuthenticatedHeaders(
      {bool forceRefresh = false}) async {
    final idToken = await _getFirebaseIdToken(forceRefresh: forceRefresh);
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (idToken != null) {
      headers['Authorization'] = 'Bearer $idToken';
      print('🔐 Added Firebase ID token to Authorization header');
    } else {
      print(
          '⚠️ No Firebase ID token available - request will be unauthenticated');
    }

    return headers;
  }

  /// Makes an authenticated HTTP request with retry/backoff for transient errors
  static Future<http.Response> _makeAuthenticatedRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      final client = http.Client();

      try {
        // Get fresh headers for each attempt (force refresh on retry for 401s)
        final forceRefresh = attempt > 0; // Refresh token on retry attempts
        final headers =
            await _getAuthenticatedHeaders(forceRefresh: forceRefresh);

        http.Response response;

        switch (method.toUpperCase()) {
          case 'GET':
            response = await client.get(Uri.parse(url), headers: headers);
            break;
          case 'POST':
            response = await client.post(
              Uri.parse(url),
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            );
            break;
          default:
            throw ArgumentError('Unsupported HTTP method: $method');
        }

        // Check if we should retry based on status code
        if (_shouldRetry(response.statusCode)) {
          attempt++;
          if (attempt < maxRetries) {
            // Special handling for 401 - try refreshing token
            if (response.statusCode == 401) {
              print(
                  '🔄 Got 401, refreshing Firebase token and retrying (attempt ${attempt + 1}/$maxRetries)');
              // Force refresh token on next attempt
            } else {
              print(
                  '🔄 Retrying request (attempt ${attempt + 1}/$maxRetries) after ${delay.inMilliseconds}ms delay for status: ${response.statusCode}');
            }
            await Future.delayed(delay);
            delay = Duration(
                milliseconds: (delay.inMilliseconds * 1.5)
                    .round()); // Exponential backoff
            continue;
          }
        }

        // Return response (success or final failure)
        return response;
      } catch (e) {
        attempt++;
        if (attempt < maxRetries && _shouldRetryException(e)) {
          print(
              '🔄 Retrying request (attempt ${attempt + 1}/$maxRetries) after ${delay.inMilliseconds}ms delay for error: $e');
          await Future.delayed(delay);
          delay = Duration(
              milliseconds:
                  (delay.inMilliseconds * 1.5).round()); // Exponential backoff
        } else {
          rethrow; // Final attempt or non-retryable error
        }
      } finally {
        client.close();
      }
    }

    throw Exception('Max retries exceeded');
  }

  /// Determines if a status code warrants a retry
  static bool _shouldRetry(int statusCode) {
    return statusCode == 401 || // Unauthorized (try token refresh)
        statusCode == 500 || // Internal server error
        statusCode == 502 || // Bad gateway
        statusCode == 503 || // Service unavailable
        statusCode == 504 || // Gateway timeout
        statusCode == 429; // Too many requests
  }

  /// Determines if an exception warrants a retry
  static bool _shouldRetryException(dynamic exception) {
    final message = exception.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('socket');
  }

  /// Ensures a user has a referral code during login
  static Future<String?> ensureReferralCodeOnLogin(String userId) async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'POST',
        url: '$baseUrl/referral/login-check',
        body: {'userId': userId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final referralData = data['data'];
          if (referralData['enabled'] == true &&
              referralData['referralCode'] != null) {
            print(
                '✅ Backend assigned referral code: ${referralData['referralCode']}');
            return referralData['referralCode'];
          } else {
            print('ℹ️ Referral system disabled or no code assigned');
            return null;
          }
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Backend referral check non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error calling backend referral check: $e (soft failure)');
    }
    return null;
  }

  /// Ensures a user has a referral code when accessing referral screen
  static Future<String?> ensureReferralCodeForScreen(String userId) async {
    try {
      print('🔐 Ensuring referral code for user: $userId with Firebase auth');

      final response = await _makeAuthenticatedRequest(
        method: 'POST',
        url: '$baseUrl/referral/ensure-code',
        body: {'userId': userId},
      );

      // Handle specific status codes
      switch (response.statusCode) {
        case 200:
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final referralData = data['data'];
            if (referralData['disabled'] == true) {
              print('ℹ️ Referral code generation is disabled');
              return null;
            }
            if (referralData['referralCode'] != null) {
              print(
                  '✅ Backend ensured referral code: ${referralData['referralCode']}');
              return referralData['referralCode'];
            }
          }
          break;

        case 401:
          print(
              '⚠️ Authentication failed - invalid or expired Firebase token (soft failure)');
          break;

        case 403:
          print(
              '⚠️ Authorization failed - user not permitted to access this resource (soft failure)');
          break;

        case 404:
          print(
              '⚠️ Endpoint not found - backend may not be deployed (soft failure)');
          break;

        default:
          print(
              '⚠️ Backend referral ensure unexpected response: ${response.statusCode} (soft failure)');
          break;
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error calling backend referral ensure: $e (soft failure)');
    }
    return null;
  }

  /// Gets current referral system settings
  static Future<Map<String, dynamic>?> getReferralSettings() async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'GET',
        url: '$baseUrl/referral/settings',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Backend settings fetch non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error fetching referral settings: $e (soft failure)');
    }
    return null;
  }

  /// Processes order completion and handles rewards
  static Future<Map<String, dynamic>?> processOrderCompletion(
      String orderId, String userId) async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'POST',
        url: '$baseUrl/orders/complete',
        body: {
          'orderId': orderId,
          'userId': userId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Order completion processed: ${data['data']}');
          return data['data'];
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Order completion non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error processing order completion: $e (soft failure)');
    }
    return null;
  }

  /// Validates referral code during signup
  static Future<Map<String, dynamic>?> validateReferralCode(
      String referralCode, String userId) async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'POST',
        url: '$baseUrl/orders/validate-referral',
        body: {
          'referralCode': referralCode,
          'userId': userId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Referral validation non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error validating referral code: $e (soft failure)');
    }
    return null;
  }

  /// Gets reward history for a user
  static Future<Map<String, dynamic>?> getUserRewardHistory(
      String userId) async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'GET',
        url: '$baseUrl/orders/rewards/$userId',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Reward history fetch non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error fetching reward history: $e (soft failure)');
    }
    return null;
  }

  /// Runs test scenarios for QA
  static Future<Map<String, dynamic>?> runTestScenario(
      String scenario, Map<String, dynamic> data) async {
    try {
      final response = await _makeAuthenticatedRequest(
        method: 'POST',
        url: '$baseUrl/orders/test-scenarios',
        body: {
          'scenario': scenario,
          'data': data,
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          print('✅ Test scenario completed: $scenario');
          return responseData['data'];
        }
      } else {
        // Treat non-200 responses as soft failures
        print(
            '⚠️ Test scenario non-200 response: ${response.statusCode} (soft failure)');
      }
    } catch (e) {
      // Treat exceptions as soft failures
      print('⚠️ Error running test scenario: $e (soft failure)');
    }
    return null;
  }
}
