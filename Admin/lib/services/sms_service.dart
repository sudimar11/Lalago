import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

// SimCard model
class SimCard {
  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final String number;

  SimCard({
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    required this.number,
  });

  @override
  String toString() {
    return '$displayName ($carrierName)';
  }
}

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  // Telephony instance
  final Telephony telephony = Telephony.instance;

  // Permission status
  bool _hasSmsPermission = false;
  bool get hasSmsPermission => _hasSmsPermission;

  // Track recent SMS sends to prevent duplicates
  final Map<String, DateTime> _recentSMSSends = {};
  static const Duration _duplicatePreventionWindow = Duration(seconds: 30);

  // Initialize the service
  Future<void> initialize() async {
    await _checkPermissions();
  }

  // Check and request SMS permissions
  Future<bool> _checkPermissions() async {
    try {
      // Check current permission status
      PermissionStatus status = await Permission.sms.status;

      if (status.isGranted) {
        _hasSmsPermission = true;
        return true;
      }

      // Request permission if not granted
      if (status.isDenied) {
        status = await Permission.sms.request();
        _hasSmsPermission = status.isGranted;
        return _hasSmsPermission;
      }

      // Handle permanently denied
      if (status.isPermanentlyDenied) {
        _hasSmsPermission = false;
        return false;
      }

      _hasSmsPermission = false;
      return false;
    } catch (e) {
      print('Error checking SMS permissions: $e');
      _hasSmsPermission = false;
      return false;
    }
  }

  // Request permissions explicitly
  Future<bool> requestPermissions() async {
    return await _checkPermissions();
  }

  // Format phone number to international format
  String _formatPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

    // If it starts with 0, replace with +63 (Philippines)
    if (cleaned.startsWith('0') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }

    // If it's 11 digits and starts with 9, add +63
    if (cleaned.length == 11 && cleaned.startsWith('9')) {
      return '+63$cleaned';
    }

    // If it's already in international format, return as is
    if (cleaned.startsWith('63') && cleaned.length == 12) {
      return '+$cleaned';
    }

    // If it starts with +, return as is
    if (phoneNumber.startsWith('+')) {
      return phoneNumber;
    }

    // Default: assume it's a local number and add +63
    if (cleaned.length == 10) {
      return '+63$cleaned';
    }

    // If all else fails, return the original
    return phoneNumber;
  }

  // Validate phone number
  bool _isValidPhoneNumber(String phoneNumber) {
    String formatted = _formatPhoneNumber(phoneNumber);
    // Basic validation for Philippine numbers
    return formatted.startsWith('+63') && formatted.length >= 13;
  }

  // Check if SMS was recently sent to prevent duplicates
  bool _isDuplicateSMS(String phoneNumber, String message) {
    final key = '$phoneNumber:${message.hashCode}';
    final lastSent = _recentSMSSends[key];

    if (lastSent != null) {
      final timeSinceLastSent = DateTime.now().difference(lastSent);
      if (timeSinceLastSent < _duplicatePreventionWindow) {
        print(
            '🚫 Duplicate SMS detected for $phoneNumber (sent ${timeSinceLastSent.inSeconds}s ago)');
        return true;
      }
    }

    return false;
  }

  // Mark SMS as sent to prevent duplicates
  void _markSMSAsSent(String phoneNumber, String message) {
    final key = '$phoneNumber:${message.hashCode}';
    _recentSMSSends[key] = DateTime.now();

    // Clean up old entries to prevent memory leaks
    _cleanupOldSMSRecords();
  }

  // Clean up old SMS records
  void _cleanupOldSMSRecords() {
    final now = DateTime.now();
    _recentSMSSends.removeWhere((key, timestamp) {
      return now.difference(timestamp) > _duplicatePreventionWindow;
    });
  }

  // Method 1: Send SMS using Telephony plugin
  Future<Map<String, dynamic>> _sendSMSViaTelephony({
    required String phoneNumber,
    required String message,
    SimCard? selectedSimCard,
  }) async {
    try {
      // Send SMS using Telephony plugin
      await telephony.sendSms(
        to: phoneNumber,
        message: message,
      );

      return {
        'success': true,
        'message': 'SMS sent successfully via Telephony!',
        'phoneNumber': phoneNumber,
        'status': 'SENT',
        'method': 'telephony',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error sending SMS via Telephony: $e',
        'error': 'TELEPHONY_EXCEPTION',
        'exception': e.toString(),
        'method': 'telephony',
      };
    }
  }

  // Method 2: Send SMS using URL Launcher (opens default SMS app)
  Future<Map<String, dynamic>> _sendSMSViaUrlLauncher({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: phoneNumber,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        return {
          'success': true,
          'message': 'SMS app opened successfully',
          'phoneNumber': phoneNumber,
          'status': 'APP_OPENED',
          'method': 'url_launcher',
        };
      } else {
        return {
          'success': false,
          'message': 'Could not open SMS app',
          'error': 'URL_LAUNCHER_FAILED',
          'phoneNumber': phoneNumber,
          'method': 'url_launcher',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error opening SMS app: $e',
        'error': 'URL_LAUNCHER_EXCEPTION',
        'exception': e.toString(),
        'method': 'url_launcher',
      };
    }
  }

  // Send single SMS with fallback methods
  Future<Map<String, dynamic>> sendSingleSMS({
    required String phoneNumber,
    required String message,
    SimCard? selectedSimCard,
    bool useFallback = true,
    bool skipDuplicateCheck = false,
  }) async {
    try {
      // Check permissions first
      if (!_hasSmsPermission) {
        bool permissionGranted = await requestPermissions();
        if (!permissionGranted) {
          return {
            'success': false,
            'message': 'SMS permission is required to send messages',
            'error': 'PERMISSION_DENIED',
          };
        }
      }

      // Format phone number
      String formattedPhone = _formatPhoneNumber(phoneNumber);

      // Validate phone number
      if (!_isValidPhoneNumber(formattedPhone)) {
        return {
          'success': false,
          'message': 'Invalid phone number format',
          'error': 'INVALID_PHONE',
          'originalPhone': phoneNumber,
          'formattedPhone': formattedPhone,
        };
      }

      // Validate message
      if (message.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Message cannot be empty',
          'error': 'EMPTY_MESSAGE',
        };
      }

      // Check for duplicate SMS only if not skipped (for bulk sending, we skip this check)
      if (!skipDuplicateCheck &&
          _isDuplicateSMS(formattedPhone, message.trim())) {
        return {
          'success': false,
          'message': 'Duplicate SMS prevented - same message sent recently',
          'error': 'DUPLICATE_SMS',
          'phoneNumber': formattedPhone,
        };
      }

      print('=== SMS SENDING DEBUG INFO ===');
      print('Original Phone: $phoneNumber');
      print('Formatted Phone: $formattedPhone');
      print('Message: $message');
      print('Message Length: ${message.trim().length}');
      print('SIM Slot: ${selectedSimCard?.subscriptionId ?? 0}');
      print('Has Permission: $_hasSmsPermission');
      print('==============================');

      // Try Method 1: Telephony plugin
      Map<String, dynamic> telephonyResult = await _sendSMSViaTelephony(
        phoneNumber: formattedPhone,
        message: message.trim(),
        selectedSimCard: selectedSimCard,
      );

      if (telephonyResult['success']) {
        print('✅ SMS sent successfully via Telephony');
        // Mark SMS as sent to prevent duplicates
        _markSMSAsSent(formattedPhone, message.trim());
        return telephonyResult;
      }

      // If Telephony fails and fallback is enabled, try Method 2
      if (useFallback) {
        print('⚠️ Telephony failed, trying URL Launcher fallback...');

        // Add a small delay to avoid rapid fallback attempts
        await Future.delayed(Duration(milliseconds: 500));

        // Double-check if SMS was already sent (in case telephony succeeded but reported failure)
        if (_isDuplicateSMS(formattedPhone, message.trim())) {
          return {
            'success': false,
            'message':
                'SMS may have been sent already, skipping fallback to prevent duplicate',
            'error': 'DUPLICATE_PREVENTION',
            'phoneNumber': formattedPhone,
          };
        }

        Map<String, dynamic> urlLauncherResult = await _sendSMSViaUrlLauncher(
          phoneNumber: formattedPhone,
          message: message.trim(),
        );

        if (urlLauncherResult['success']) {
          print('✅ SMS app opened successfully via URL Launcher');
          // Mark SMS as sent to prevent duplicates (even though it just opens the app)
          _markSMSAsSent(formattedPhone, message.trim());
          return urlLauncherResult;
        }

        // Both methods failed
        return {
          'success': false,
          'message': 'All SMS sending methods failed',
          'error': 'ALL_METHODS_FAILED',
          'telephonyError': telephonyResult['message'],
          'urlLauncherError': urlLauncherResult['message'],
          'phoneNumber': formattedPhone,
        };
      }

      // Return Telephony result if fallback is disabled
      return telephonyResult;
    } catch (e) {
      print('Error sending SMS: $e');
      return {
        'success': false,
        'message': 'Error sending SMS: $e',
        'error': 'EXCEPTION',
        'exception': e.toString(),
      };
    }
  }

  // Send bulk SMS with progress tracking
  Future<Map<String, dynamic>> sendBulkSMS({
    required List<String> phoneNumbers,
    required String message,
    SimCard? selectedSimCard,
    Function(int current, int total)? onProgress,
    bool useFallback = true,
  }) async {
    try {
      // Check permissions
      if (!_hasSmsPermission) {
        bool permissionGranted = await requestPermissions();
        if (!permissionGranted) {
          return {
            'success': false,
            'message': 'SMS permission is required to send messages',
            'error': 'PERMISSION_DENIED',
          };
        }
      }

      List<Map<String, dynamic>> results = [];
      int successCount = 0;
      int failureCount = 0;

      for (int i = 0; i < phoneNumbers.length; i++) {
        String phoneNumber = phoneNumbers[i];

        // Call progress callback
        onProgress?.call(i + 1, phoneNumbers.length);

        // Send individual SMS
        Map<String, dynamic> result = await sendSingleSMS(
          phoneNumber: phoneNumber,
          message: message,
          selectedSimCard: selectedSimCard,
          useFallback: useFallback,
        );

        results.add({
          'phoneNumber': phoneNumber,
          'result': result,
          'index': i,
        });

        if (result['success']) {
          successCount++;
        } else {
          failureCount++;
        }

        // Add delay between messages to avoid rate limiting
        if (i < phoneNumbers.length - 1) {
          await Future.delayed(Duration(milliseconds: 1000));
        }
      }

      return {
        'success': true,
        'message':
            'Bulk SMS completed: $successCount sent, $failureCount failed',
        'totalSent': successCount,
        'totalFailed': failureCount,
        'totalCount': phoneNumbers.length,
        'results': results,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error in bulk SMS: $e',
        'error': 'BULK_EXCEPTION',
        'exception': e.toString(),
      };
    }
  }

  // Get available SIM cards
  Future<List<SimCard>> getAvailableSimCards() async {
    try {
      List<SimCard> simCards = [];

      // For now, return default SIM cards since Telephony plugin doesn't provide SIM info
      simCards.add(SimCard(
        subscriptionId: 0,
        displayName: 'SIM 1',
        carrierName: 'Carrier',
        number: 'Unknown',
      ));

      // Add second SIM for dual SIM devices
      simCards.add(SimCard(
        subscriptionId: 1,
        displayName: 'SIM 2',
        carrierName: 'Carrier',
        number: 'Unknown',
      ));

      return simCards;
    } catch (e) {
      print('Error getting SIM cards: $e');
      // Return default SIM cards
      return [
        SimCard(
          subscriptionId: 0,
          displayName: 'SIM 1',
          carrierName: 'Default Carrier',
          number: 'Unknown',
        ),
      ];
    }
  }

  // Test SMS functionality
  Future<Map<String, dynamic>> testSMSFunctionality() async {
    try {
      // Test permissions
      bool hasPermission = await requestPermissions();

      // Test phone formatting
      String testPhone = '+639652639563';
      String formatted = _formatPhoneNumber(testPhone);
      bool isValid = _isValidPhoneNumber(formatted);

      // Get available SIM cards
      List<SimCard> simCards = await getAvailableSimCards();

      return {
        'success': true,
        'permissions': hasPermission,
        'phoneFormatting': {
          'original': testPhone,
          'formatted': formatted,
          'isValid': isValid,
        },
        'availableSimCards': simCards.length,
        'simCards': simCards.map((sim) => sim.toString()).toList(),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error testing SMS functionality: $e',
        'error': e.toString(),
      };
    }
  }

}

extension SMSValidationHelpers on SMSService {
  // Public helper to check if a phone number is valid for sending
  bool isValidPhoneForSending(String phoneNumber) {
    final formatted = _formatPhoneNumber(phoneNumber);
    return _isValidPhoneNumber(formatted);
  }
}
