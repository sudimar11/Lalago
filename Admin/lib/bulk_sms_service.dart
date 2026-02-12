import 'package:brgy/services/sms_service.dart';
import 'package:brgy/database/database_helper.dart';

// Campaign type enum
enum CampaignType { none, prod, test }

// Progress callback types
typedef BulkSMSProgressCallback = void Function(
    int current, int total, String status);
typedef BulkSMSStatusChangeCallback = void Function(
    String userId, String status);

class BulkSMSService {
  String _campaignId = '';
  CampaignType _activeCampaign = CampaignType.none;
  bool _isBulkSending = false;
  int _currentSendingIndex = 0;
  int _totalToSend = 0;
  bool _isCancelled = false;
  bool _isProcessingSMS = false; // Add flag to prevent race conditions
  int _timerIterations = 0; // Track timer iterations to prevent infinite loops
  static const int _maxTimerIterations = 1000; // Safety limit
  final SMSService _smsService = SMSService();
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final Set<String> _sentUserIds =
      {}; // Track users who have been successfully sent SMS
  // Track users currently being processed to avoid reclaiming them
  final Set<String> _inFlightUserIds = {};
  final Map<String, int> _failedAttempts = {}; // Track failed attempts per user
  static const int _maxRetryAttempts = 2; // Maximum retry attempts per user
  static const String _testPhoneNumber = '+639652639563';

  // Progress callback
  BulkSMSProgressCallback? _progressCallback;
  BulkSMSStatusChangeCallback? _statusChangeCallback;

  // Getters for UI state
  String get campaignId => _campaignId;
  CampaignType get activeCampaign => _activeCampaign;
  bool get isBulkSending => _isBulkSending;
  int get currentSendingIndex => _currentSendingIndex;
  int get totalToSend => _totalToSend;
  bool get isCancelled => _isCancelled;

  // Set progress callback
  void setProgressCallback(BulkSMSProgressCallback? callback) {
    if (callback == null) {
      _progressCallback = null;
      return;
    }
    _progressCallback = (int current, int total, String status) {
      try {
        callback(current, total, status);
      } finally {
        final String normalized = status.toLowerCase();
        if (normalized.contains('completed') ||
            normalized.contains('cancelled')) {
          _activeCampaign = CampaignType.none;
        }
      }
    };
  }

  // Set status change callback
  void setStatusChangeCallback(BulkSMSStatusChangeCallback? callback) {
    _statusChangeCallback = callback;
  }

  // Generate campaign ID
  String _generateCampaignId() {
    return 'campaign_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Create bulk SMS campaign
  Future<Map<String, dynamic>> createBulkSMSCampaign({
    required String message,
    required SimCard? selectedSimCard,
  }) async {
    try {
      // Reset state
      _isCancelled = false;
      _isProcessingSMS = false;
      _sentUserIds.clear(); // Clear sent users for new campaign
      _inFlightUserIds.clear(); // Clear in-flight users for new campaign
      _failedAttempts.clear(); // Clear failed attempts for new campaign
      _timerIterations = 0; // Reset timer iterations counter

      // Generate campaign ID
      _campaignId = _generateCampaignId();
      _activeCampaign = CampaignType.prod;

      // Release stale 'Sending' rows so recipient loading is accurate
      // Use a shorter timeout (10 seconds) to quickly release stuck numbers
      await _databaseHelper.releaseStaleSendingRows(
        staleAfter: const Duration(seconds: 10),
        resetAllIfNoTimestamps: true,
      );

      // Get only active users who haven't been sent SMS yet
      final List<Map<String, dynamic>> users =
          await _databaseHelper.getActiveUsersNotSent();

      _totalToSend = users.length;
      _currentSendingIndex = 0;

      // If there are no eligible recipients, stop early and notify caller
      if (_totalToSend == 0) {
        _activeCampaign = CampaignType.none;
        _isBulkSending = false;
        _progressCallback?.call(0, 0, 'No eligible recipients to send');
        return {
          'success': false,
          'message':
              'No eligible recipients. Only users with status "To be sent" are included.',
          'totalRecipients': 0,
        };
      }

      _isBulkSending = true;

      print('📊 Bulk SMS Campaign Setup:');
      print('   Campaign ID: $_campaignId');
      print('   Total users to send: $_totalToSend');
      print('   Campaign type: ${_activeCampaign.toString()}');

      // Update progress
      _progressCallback?.call(0, users.length, 'Starting bulk SMS campaign...');

      // Start the bulk sending process
      _startBulkSending(selectedSimCard, message);

      return {
        'success': true,
        'message':
            'Bulk SMS campaign created with ${users.length} recipients who haven\'t been sent SMS yet!',
        'totalRecipients': users.length,
      };
    } catch (e) {
      _activeCampaign = CampaignType.none;
      _isBulkSending = false;
      return {
        'success': false,
        'message': 'Error creating bulk SMS campaign: $e',
      };
    }
  }

  // Create bulk SMS testing campaign
  Future<Map<String, dynamic>> createBulkTestingCampaign({
    required String message,
    required SimCard? selectedSimCard,
  }) async {
    try {
      // Reset state
      _isCancelled = false;
      _isProcessingSMS = false;
      _sentUserIds.clear(); // Clear sent users for new campaign
      _inFlightUserIds.clear(); // Clear in-flight users for new campaign
      _failedAttempts.clear(); // Clear failed attempts for new campaign
      _timerIterations = 0; // Reset timer iterations counter

      // Generate campaign ID with test prefix
      _campaignId = 'test_${_generateCampaignId()}';
      _activeCampaign = CampaignType.test;

      // Release stale 'Sending' rows so recipient loading is accurate
      // Use a shorter timeout (10 seconds) to quickly release stuck numbers
      await _databaseHelper.releaseStaleSendingRows(
        staleAfter: const Duration(seconds: 10),
        resetAllIfNoTimestamps: true,
      );

      // Get only active users who haven't been sent SMS yet
      final List<Map<String, dynamic>> users =
          await _databaseHelper.getActiveUsersNotSent();

      _totalToSend = users.length;
      _currentSendingIndex = 0;

      // If there are no eligible recipients, stop early and notify caller
      if (_totalToSend == 0) {
        _activeCampaign = CampaignType.none;
        _isBulkSending = false;
        _progressCallback?.call(0, 0, 'No eligible recipients to send');
        return {
          'success': false,
          'message':
              'No eligible recipients. Only users with status "To be sent" are included.',
          'totalRecipients': 0,
        };
      }

      _isBulkSending = true;

      print('📊 Bulk SMS Testing Campaign Setup:');
      print('   Campaign ID: $_campaignId');
      print('   Total users to send: $_totalToSend');
      print('   Campaign type: ${_activeCampaign.toString()}');

      // Update progress
      _progressCallback?.call(
          0, users.length, 'Starting bulk SMS testing campaign...');

      // Start the bulk sending process
      _startBulkSending(selectedSimCard, message);

      return {
        'success': true,
        'message':
            'Bulk SMS testing campaign created with ${users.length} recipients who haven\'t been sent SMS yet!',
        'totalRecipients': users.length,
      };
    } catch (e) {
      _activeCampaign = CampaignType.none;
      _isBulkSending = false;
      return {
        'success': false,
        'message': 'Error creating bulk SMS testing campaign: $e',
      };
    }
  }

  // Start bulk sending process
  void _startBulkSending(SimCard? selectedSimCard, String message) {
    // Start processing immediately
    _processNextSMSBatch(selectedSimCard, message);
  }

  // Process SMS in batches without timer to avoid race conditions
  Future<void> _processNextSMSBatch(
      SimCard? selectedSimCard, String message) async {
    int consecutiveNullClaims = 0;
    const int maxConsecutiveNulls =
        5; // Stop if we can't claim users 5 times in a row

    while (_currentSendingIndex < _totalToSend &&
        !_isCancelled &&
        !_isProcessingSMS &&
        consecutiveNullClaims < maxConsecutiveNulls) {
      _timerIterations++;

      // Safety check to prevent infinite loops
      if (_timerIterations > _maxTimerIterations) {
        print(
            '⚠️ Maximum iterations reached ($_maxTimerIterations), stopping to prevent infinite loop');
        _isBulkSending = false;
        _activeCampaign = CampaignType.none;
        _progressCallback?.call(
            _currentSendingIndex, _totalToSend, 'Stopped due to safety limit');
        return;
      }

      print(
          '🔄 Processing SMS batch iteration $_timerIterations (${_currentSendingIndex + 1}/$_totalToSend)');

      // Track if we successfully processed a user this iteration
      bool processedUser = await _processNextSMS(selectedSimCard, message);

      if (processedUser) {
        consecutiveNullClaims = 0; // Reset counter on successful processing
      } else {
        consecutiveNullClaims++;
        print(
            '⚠️ No user available for processing (attempt $consecutiveNullClaims/$maxConsecutiveNulls)');

        // Release any stuck 'Sending' rows that might have timed out
        if (consecutiveNullClaims % 2 == 0) {
          // Every 2nd attempt
          await _databaseHelper.releaseStaleSendingRows(
            staleAfter: const Duration(seconds: 10),
            resetAllIfNoTimestamps: true,
          );
          print(
              '🔄 Released any stuck Sending rows due to consecutive null claims');
        }

        // Add a longer delay when no users are available to avoid rapid retries
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // Final completion check - determine why we exited the loop
    if (_isCancelled) {
      print('🏁 Bulk SMS process cancelled');
      _progressCallback?.call(
          _currentSendingIndex, _totalToSend, 'Operation cancelled');
    } else if (consecutiveNullClaims >= maxConsecutiveNulls) {
      print('🏁 Bulk SMS process completed - no more available recipients');
      _progressCallback?.call(_currentSendingIndex, _totalToSend,
          'Completed - no more recipients available');
    } else if (_currentSendingIndex >= _totalToSend) {
      print('🏁 Bulk SMS process completed - all recipients processed');
      _progressCallback?.call(_totalToSend, _totalToSend, 'Bulk SMS completed');
    }

    _isBulkSending = false;
    _activeCampaign = CampaignType.none;
  }

  // Process next SMS in queue
  Future<bool> _processNextSMS(SimCard? selectedSimCard, String message) async {
    // Set processing flag to prevent race conditions
    _isProcessingSMS = true;

    String? _currentInFlightUserId; // Track for cleanup in finally
    try {
      print(
          '🔄 Processing next SMS... (Current index: $_currentSendingIndex/$_totalToSend)');

      // Atomically claim the next user for sending (exclude sent and in-flight)
      final Set<String> excludeIds = {
        ..._sentUserIds,
        ..._inFlightUserIds,
      };
      final user = await _databaseHelper.claimNextUserForSending(
        excludeIds,
        staleAfter:
            const Duration(seconds: 10), // Quick timeout for stuck numbers
        resetAllIfNoTimestamps: true,
      );

      if (user == null) {
        // No available user right now; brief backoff to avoid hot loop
        await Future.delayed(const Duration(milliseconds: 150));
        return false; // Indicate no user was processed
      }

      final String phoneNumber = user['phoneNumber'] ?? '';
      final String userId = user['id'] ?? '';
      _currentInFlightUserId = userId;

      print('📱 Processing user $userId with phone $phoneNumber');

      // Mark as in-flight immediately so it cannot be reclaimed
      _inFlightUserIds.add(userId);

      // Mark status as 'Sending' in DB immediately
      await _databaseHelper.updateSendingStatus(userId, 'Sending');

      // Pre-validate phone number and skip early if invalid (except in test campaigns)
      if (_activeCampaign != CampaignType.test &&
          !_smsService.isValidPhoneForSending(phoneNumber)) {
        print('⏭️ Skipping user $userId due to invalid phone: $phoneNumber');
        await _databaseHelper.updateSendingStatus(userId, 'Failed');
        _statusChangeCallback?.call(userId, 'Failed');
        _progressCallback?.call(
          _currentSendingIndex + 1,
          _totalToSend,
          'Skipped invalid phone for ${user['firstName'] ?? 'User'} ($phoneNumber)',
        );
        _sentUserIds.add(userId); // ensure this user won't be reclaimed
        _currentSendingIndex++;
        return true; // User was processed (skipped)
      }

      if (phoneNumber.isEmpty || userId.isEmpty) {
        print('⚠️ Invalid user data: phoneNumber=$phoneNumber, userId=$userId');
        // Mark as failed since we can't send without phone number
        if (userId.isNotEmpty) {
          await _databaseHelper.updateSendingStatus(userId, 'Failed');
          _statusChangeCallback?.call(userId, 'Failed');
        }
        // Surface error to UI progress
        _progressCallback?.call(_currentSendingIndex + 1, _totalToSend,
            'Failed: Missing phone/user id for ${user['firstName'] ?? 'User'}');
        _currentSendingIndex++;
        return true; // User was processed (failed)
      }

      // Notify status change
      _statusChangeCallback?.call(userId, 'Sending');

      // Update progress BEFORE sending (so UI shows current user being processed)
      final String displayPhone =
          _activeCampaign == CampaignType.test ? _testPhoneNumber : phoneNumber;
      _progressCallback?.call(_currentSendingIndex + 1, _totalToSend,
          'Sending SMS to ${user['firstName'] ?? 'User'} (${displayPhone})');

      print(
          '📤 Sending SMS to user ${user['firstName']} ($userId) at $phoneNumber');

      // Send the SMS with a 5-second timeout to prevent getting stuck
      try {
        await _sendSMSToUser(user, message, selectedSimCard).timeout(
          const Duration(seconds: 5),
          onTimeout: () async {
            print('⏰ SMS sending timed out after 5 seconds for user $userId');
            // Mark as failed due to timeout
            await _databaseHelper.updateSendingStatus(userId, 'Failed');
            _statusChangeCallback?.call(userId, 'Failed');
            _sentUserIds.add(userId); // prevent re-claim within this campaign

            // Update progress with timeout message
            _progressCallback?.call(
              _currentSendingIndex + 1,
              _totalToSend,
              'Timeout sending to ${user['firstName'] ?? 'User'} ($phoneNumber) - proceeding to next',
            );
          },
        );
      } catch (timeoutError) {
        print('⏰ SMS sending timeout error for user $userId: $timeoutError');
        // Ensure user is marked as failed and excluded from further processing
        await _databaseHelper.updateSendingStatus(userId, 'Failed');
        _statusChangeCallback?.call(userId, 'Failed');
        _sentUserIds.add(userId);
      }

      // Increment only after successful processing attempt
      _currentSendingIndex++;

      print(
          '✅ Completed processing for user $userId (${_currentSendingIndex}/$_totalToSend)');

      return true; // User was successfully processed
    } catch (e) {
      print('❌ Error processing SMS: $e');
      // Ensure we don't get stuck - increment counter even on error
      if (_currentSendingIndex < _totalToSend) {
        _currentSendingIndex++;
      }
      return true; // Even on error, we processed a user (failed)
    } finally {
      // Always clear the processing flag and in-flight marker
      _isProcessingSMS = false;
      if (_currentInFlightUserId != null && _currentInFlightUserId.isNotEmpty) {
        _inFlightUserIds.remove(_currentInFlightUserId);
      }
      print(
          '🏁 Processing flag cleared. Next: ${_currentSendingIndex}/$_totalToSend');
    }
  }

  // Send SMS to user
  Future<void> _sendSMSToUser(Map<String, dynamic> user, String message,
      SimCard? selectedSimCard) async {
    try {
      final String phoneNumber = user['phoneNumber'] ?? '';
      final String userId = user['id'] ?? '';

      // Determine phone number based on campaign type
      String targetPhone = phoneNumber;
      if (_activeCampaign == CampaignType.test) {
        targetPhone = _testPhoneNumber; // Use consistent test phone
      }

      // Use improved SMS service to send the message with a timeout to avoid getting stuck
      final Map<String, dynamic> result = await _smsService
          .sendSingleSMS(
            phoneNumber: targetPhone,
            message: message,
            selectedSimCard: selectedSimCard,
            useFallback: true,
            skipDuplicateCheck: true, // Skip duplicate check for bulk sending
          )
          .timeout(
            Duration(seconds: 5),
            onTimeout: () => {
              'success': false,
              'message': 'No status received after 5 seconds',
              'error': 'STATUS_TIMEOUT',
              'method': 'timeout',
            },
          );

      if (result['success'] == true) {
        // Update status to 'Sent' in database
        await _databaseHelper.updateSendingStatus(userId, 'Sent');

        // Add to sent users to prevent sending again
        _sentUserIds.add(userId);

        // Notify status change
        _statusChangeCallback?.call(userId, 'Sent');
      } else {
        // Handle failed SMS with smarter retry logic
        final String errorCode = (result['error'] ?? '').toString();
        final String errorMessage =
            (result['message'] ?? 'Unknown error').toString();

        // Emit progress update with error details
        _progressCallback?.call(
          _currentSendingIndex + 1,
          _totalToSend,
          'Failed to send to ${user['firstName'] ?? 'User'} ($targetPhone): ' +
              errorMessage +
              (errorCode.isNotEmpty ? ' [$errorCode]' : ''),
        );

        // Invalid phone or no status timeout should be treated as permanently failed immediately
        if (errorCode == 'INVALID_PHONE' || errorCode == 'STATUS_TIMEOUT') {
          await _databaseHelper.updateSendingStatus(userId, 'Failed');
          _statusChangeCallback?.call(userId, 'Failed');
          // Exclude this user from further claims in this campaign
          _sentUserIds.add(userId);
          print(
              '❌ User $userId permanently failed (${errorCode}). Marked Failed and skipped.');
        } else {
          int currentAttempts = _failedAttempts[userId] ?? 0;
          currentAttempts++;
          _failedAttempts[userId] = currentAttempts;

          if (currentAttempts >= _maxRetryAttempts) {
            // Max retries reached, mark as permanently failed and skip further processing
            await _databaseHelper.updateSendingStatus(userId, 'Failed');
            _statusChangeCallback?.call(userId, 'Failed');
            _sentUserIds.add(userId); // prevent re-claim within this campaign
            print(
                '❌ User $userId failed after $currentAttempts attempts, marking as permanently failed');
          } else {
            // Still has retries left, mark as 'To be sent' for retry
            await _databaseHelper.updateSendingStatus(userId, 'To be sent');
            _statusChangeCallback?.call(userId, 'Retry pending');
            print(
                '🔄 User $userId failed (attempt $currentAttempts/$_maxRetryAttempts), will retry');
          }
        }
      }

      // Add delay to allow UI to update and prevent hanging
      // Proceed immediately without added delay
    } catch (e) {
      // Handle exception with retry logic
      final String userId = user['id'] ?? '';
      final String targetPhoneForLog = (user['phoneNumber'] ?? '').toString();
      // Surface exception to UI progress
      _progressCallback?.call(_currentSendingIndex + 1, _totalToSend,
          'Exception sending to ${user['firstName'] ?? 'User'} ($targetPhoneForLog): $e');
      if (userId.isNotEmpty) {
        int currentAttempts = _failedAttempts[userId] ?? 0;
        currentAttempts++;
        _failedAttempts[userId] = currentAttempts;

        if (currentAttempts >= _maxRetryAttempts) {
          // Max retries reached, mark as permanently failed
          await _databaseHelper.updateSendingStatus(userId, 'Failed');
          // Notify status change
          _statusChangeCallback?.call(userId, 'Failed');
          _sentUserIds.add(userId); // prevent re-claim within this campaign
          print(
              '❌ User $userId failed with exception after $currentAttempts attempts: $e');
        } else {
          // Still has retries left, mark as 'To be sent' for retry
          await _databaseHelper.updateSendingStatus(userId, 'To be sent');
          // Notify status change
          _statusChangeCallback?.call(userId, 'Retry pending');
          print(
              '🔄 User $userId failed with exception (attempt $currentAttempts/$_maxRetryAttempts), will retry: $e');
        }
      }
      print('Error sending SMS to user: $e');

      // Add delay even on error to prevent hanging
      // Proceed immediately without added delay
    }
  }

  // Cancel bulk SMS campaign
  Future<void> cancelBulkSMS() async {
    print('Cancelling bulk SMS campaign: $_campaignId');
    _isCancelled = true;

    // Mark remaining SMS as cancelled in offline database
    try {
      final List<Map<String, dynamic>> users = await _databaseHelper.getUsers();
      int cancelledCount = 0;

      for (final user in users) {
        final String status = user['sending_status'] ?? 'To be sent';
        if (status == 'To be sent' || status == 'Sending') {
          final String userId = user['id'] ?? '';
          if (userId.isNotEmpty) {
            await _databaseHelper.updateSendingStatus(userId, 'Cancelled');
            cancelledCount++;
          }
        }
      }

      print('Cancelled $cancelledCount pending SMS messages');
    } catch (e) {
      print('Error cancelling SMS: $e');
    }

    _isBulkSending = false;
    _activeCampaign = CampaignType.none;
    print('Bulk SMS campaign cancelled successfully');
  }

  // Dispose resources
  void dispose() {
    _isCancelled = true;
  }
}
