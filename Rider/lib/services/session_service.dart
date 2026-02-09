import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/constants.dart';

class SessionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static String? _cachedClosingTime; // Cache to reduce Firestore reads
  static DateTime? _lastFetchTime;
  static const Duration _cacheValidity = Duration(hours: 1); // Cache for 1 hour
  static const Duration _gracePeriod = Duration(minutes: 5); // 5-minute grace period

  /// Fetch closing_time from driver_performance settings (with caching)
  static Future<String?> getClosingTime({bool forceRefresh = false}) async {
    try {
      // Return cached value if still valid
      if (!forceRefresh && 
          _cachedClosingTime != null && 
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < _cacheValidity) {
        return _cachedClosingTime;
      }

      final doc = await _firestore
          .collection(Setting)
          .doc('driver_performance')
          .get()
          .timeout(Duration(seconds: 10));
      
      if (doc.exists && doc.data() != null) {
        final closingTime = doc.data()!['closing_time']?.toString();
        _cachedClosingTime = closingTime;
        _lastFetchTime = DateTime.now();
        return closingTime;
      }
      return null;
    } catch (e) {
      print('❌ Error getting closing_time: $e');
      // Return cached value on error if available
      return _cachedClosingTime;
    }
  }

  /// Parse time string (e.g., "9 PM", "9:00 PM") to DateTime for today
  static DateTime? _parseClosingTime(String timeString) {
    try {
      final parts = timeString.trim().split(' ');
      if (parts.length < 2) {
        throw Exception('Invalid time format: $timeString');
      }
      
      final timePart = parts[0]; // "9" or "9:00"
      final period = parts[1].toUpperCase(); // "AM" or "PM"
      
      final timeComponents = timePart.split(':');
      int hour = int.parse(timeComponents[0]);
      int minute = timeComponents.length > 1 ? int.parse(timeComponents[1]) : 0;
      
      // Validate hour and minute
      if (hour < 1 || hour > 12 || minute < 0 || minute > 59) {
        throw Exception('Invalid time values: hour=$hour, minute=$minute');
      }
      
      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }
      
      // Create DateTime for today with closing time
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) {
      print('❌ Error parsing closing_time "$timeString": $e');
      return null;
    }
  }

  /// Check if current time has passed closing_time (with grace period)
  static Future<bool> hasPassedClosingTime() async {
    try {
      final closingTimeString = await getClosingTime();
      if (closingTimeString == null || closingTimeString.isEmpty) {
        print('⚠️ No closing_time set, skipping automatic logout check');
        return false; // Don't logout if no closing time is set
      }
      
      final closingTime = _parseClosingTime(closingTimeString);
      if (closingTime == null) {
        print('⚠️ Failed to parse closing_time, skipping check');
        return false;
      }
      
      final now = DateTime.now();
      // Add grace period to closing time
      final closingTimeWithGrace = closingTime.add(_gracePeriod);
      final hasPassed = now.isAfter(closingTimeWithGrace);
      
      if (hasPassed) {
        print('⏰ Current time (${DateFormat('h:mm a').format(now)}) has passed closing_time (${DateFormat('h:mm a').format(closingTime)}) with grace period');
      }
      
      return hasPassed;
    } catch (e) {
      print('❌ Error checking closing_time: $e');
      return false; // Don't logout on error - fail gracefully
    }
  }

  /// Clear cache (useful for testing or when settings change)
  static void clearCache() {
    _cachedClosingTime = null;
    _lastFetchTime = null;
  }
}

