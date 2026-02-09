import 'package:intl/intl.dart';

class TimeTrackingService {
  static const double VOUCHER_THRESHOLD_HOURS = 6.0;
  static const double VOUCHER_AMOUNT = 10.0;

  /// Calculate the duration between check-in and check-out times
  static Duration calculateWorkDuration(
      String checkInTime, String checkOutTime) {
    try {
      final checkInDateTime = _parseTimeString(checkInTime);
      final checkOutDateTime = _parseTimeString(checkOutTime);

      // If check-out is on the next day, add 24 hours
      if (checkOutDateTime.isBefore(checkInDateTime)) {
        final nextDayCheckOut = checkOutDateTime.add(Duration(days: 1));
        return nextDayCheckOut.difference(checkInDateTime);
      } else {
        return checkOutDateTime.difference(checkInDateTime);
      }
    } catch (e) {
      print('❌ Error calculating work duration: $e');
      return Duration.zero;
    }
  }

  /// Calculate the duration from today's check-in to current time
  static Duration calculateTodayWorkDuration(String todayCheckInTime) {
    try {
      final checkInDateTime = _parseTimeString(todayCheckInTime);
      final now = DateTime.now();

      // Create DateTime for today with check-in time
      final todayCheckIn = DateTime(now.year, now.month, now.day,
          checkInDateTime.hour, checkInDateTime.minute);

      return now.difference(todayCheckIn);
    } catch (e) {
      print('❌ Error calculating today work duration: $e');
      return Duration.zero;
    }
  }

  /// Check if the work duration qualifies for a voucher (6+ hours)
  static bool qualifiesForVoucher(Duration workDuration) {
    return workDuration.inHours >= VOUCHER_THRESHOLD_HOURS;
  }

  /// Calculate voucher amount based on work duration
  static double calculateVoucherAmount(Duration workDuration) {
    if (qualifiesForVoucher(workDuration)) {
      return VOUCHER_AMOUNT;
    }
    return 0.0;
  }

  /// Format duration to readable string
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// Parse time string to DateTime
  static DateTime _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(' ');
      if (parts.length == 2) {
        final timePart = parts[0];
        final period = parts[1];
        final timeParts = timePart.split(':');
        if (timeParts.length == 2) {
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);

          if (period.toLowerCase() == 'pm' && hour != 12) {
            hour += 12;
          } else if (period.toLowerCase() == 'am' && hour == 12) {
            hour = 0;
          }

          // Create DateTime for today with the parsed time
          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    } catch (e) {
      print('❌ Error parsing time string: $e');
    }
    return DateTime.now();
  }

  /// Get current time formatted as string
  static String getCurrentTimeString() {
    final now = DateTime.now();
    return DateFormat('h:mm a').format(now);
  }

  /// Get today's date as string
  static String getTodayDateString() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }
}
