import '../database/database_helper.dart';

class UserStatisticsService {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  int _totalUsers = 0;
  bool _isLoadingUsers = false;
  int _failedCount = 0;
  int _totalSentCount = 0;

  // Getters for UI state
  int get totalUsers => _totalUsers;
  bool get isLoadingUsers => _isLoadingUsers;
  int get failedCount => _failedCount;
  int get totalSentCount => _totalSentCount;

  // Load total number of users from offline database
  Future<Map<String, dynamic>> loadTotalUsers() async {
    _isLoadingUsers = true;

    try {
      final List<Map<String, dynamic>> users = await _databaseHelper.getUsers();

      // Count active users (users with phone numbers)
      _totalUsers = users
          .where((user) =>
              (user['phoneNumber'] ?? '').isNotEmpty &&
              (user['active'] ?? true) == true)
          .length;

      return {
        'success': true,
        'totalUsers': _totalUsers,
        'message': 'User count loaded successfully from offline database',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error loading user count from offline database: $e',
        'totalUsers': 0,
      };
    } finally {
      _isLoadingUsers = false;
    }
  }

  // Load SMS statistics from offline database
  Future<Map<String, dynamic>> loadSMSStatistics() async {
    try {
      final List<Map<String, dynamic>> users = await _databaseHelper.getUsers();

      // Count users by sending status
      int failedCount = 0;
      int sentCount = 0;

      for (final user in users) {
        final String status = user['sending_status'] ?? '';
        switch (status.toLowerCase()) {
          case 'failed':
            failedCount++;
            break;
          case 'sent':
            sentCount++;
            break;
        }
      }

      _failedCount = failedCount;
      _totalSentCount = sentCount;

      return {
        'success': true,
        'failedCount': _failedCount,
        'totalSentCount': _totalSentCount,
        'message': 'SMS statistics loaded successfully from offline database',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error loading SMS statistics from offline database: $e',
        'failedCount': 0,
        'totalSentCount': 0,
      };
    }
  }

  // Load all statistics (users and SMS)
  Future<Map<String, dynamic>> loadAllStatistics() async {
    try {
      // Load user count
      final userResult = await loadTotalUsers();
      if (!userResult['success']) {
        return userResult;
      }

      // Load SMS statistics
      final smsResult = await loadSMSStatistics();
      if (!smsResult['success']) {
        return smsResult;
      }

      return {
        'success': true,
        'totalUsers': _totalUsers,
        'failedCount': _failedCount,
        'totalSentCount': _totalSentCount,
        'message': 'All statistics loaded successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error loading statistics: $e',
        'totalUsers': 0,
        'failedCount': 0,
        'totalSentCount': 0,
      };
    }
  }

  // Get statistics for current campaign from offline database
  Future<Map<String, dynamic>> getCampaignStatistics(String campaignId) async {
    try {
      final List<Map<String, dynamic>> users = await _databaseHelper.getUsers();

      // Count users by sending status for current campaign
      int sentCount = 0;
      int failedCount = 0;
      int cancelledCount = 0;

      for (final user in users) {
        final String status = user['sending_status'] ?? '';
        switch (status.toLowerCase()) {
          case 'sent':
            sentCount++;
            break;
          case 'failed':
            failedCount++;
            break;
          case 'cancelled':
            cancelledCount++;
            break;
        }
      }

      return {
        'success': true,
        'sentCount': sentCount,
        'failedCount': failedCount,
        'cancelledCount': cancelledCount,
        'totalCount': sentCount + failedCount + cancelledCount,
      };
    } catch (e) {
      return {
        'success': false,
        'message':
            'Error loading campaign statistics from offline database: $e',
        'sentCount': 0,
        'failedCount': 0,
        'cancelledCount': 0,
        'totalCount': 0,
      };
    }
  }

  // Get detailed SMS statistics from offline database
  Future<Map<String, dynamic>> getDetailedSMSStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final List<Map<String, dynamic>> users = await _databaseHelper.getUsers();

      int sentCount = 0;
      int failedCount = 0;
      int cancelledCount = 0;
      int toBeSentCount = 0;
      int sendingCount = 0;

      for (final user in users) {
        final String status = user['sending_status'] ?? '';

        switch (status.toLowerCase()) {
          case 'sent':
            sentCount++;
            break;
          case 'failed':
            failedCount++;
            break;
          case 'cancelled':
            cancelledCount++;
            break;
          case 'to be sent':
            toBeSentCount++;
            break;
          case 'sending':
            sendingCount++;
            break;
        }
      }

      return {
        'success': true,
        'sentCount': sentCount,
        'failedCount': failedCount,
        'cancelledCount': cancelledCount,
        'newCount': toBeSentCount,
        'claimedCount': sendingCount,
        'totalCount': users.length,
      };
    } catch (e) {
      return {
        'success': false,
        'message':
            'Error loading detailed SMS statistics from offline database: $e',
        'sentCount': 0,
        'failedCount': 0,
        'cancelledCount': 0,
        'newCount': 0,
        'claimedCount': 0,
        'totalCount': 0,
      };
    }
  }

  // Reset all statistics
  void resetStatistics() {
    _totalUsers = 0;
    _failedCount = 0;
    _totalSentCount = 0;
    _isLoadingUsers = false;
  }
}
