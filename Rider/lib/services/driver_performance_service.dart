import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/services/time_tracking_service.dart';

class DriverPerformanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Performance adjustment constants
  static const double ADJUSTMENT_LATE_CHECKIN = -1.0;
  static const double ADJUSTMENT_UNDERTIME = -2.0;
  static const double ADJUSTMENT_ABSENT = -3.0;
  static const double ADJUSTMENT_CANCELLATION = -1.0;
  static const double ADJUSTMENT_OUTSIDE_SERVICE_AREA = -1.0;
  static const double ADJUSTMENT_COMPLETE_5_HOURS = 1.0;
  static const double ADJUSTMENT_ON_TIME_CHECKIN = 0.5;
  static const double ADJUSTMENT_PERFECT_ATTENDANCE_7_DAYS = 2.0;

  // Performance limits
  static const double MIN_PERFORMANCE = 50.0;
  static const double MAX_PERFORMANCE = 100.0;

  // Perfect attendance requirement: 7 consecutive days
  static const int PERFECT_ATTENDANCE_DAYS = 7;

  // Grace period for new drivers (days after first check-in)
  static const int GRACE_PERIOD_DAYS = 3;

  // Default detection range (days)
  static const int DEFAULT_DETECTION_RANGE_DAYS = 90;

  /// Enforce min/max limits on performance score
  static double clampPerformance(double score) {
    return score.clamp(MIN_PERFORMANCE, MAX_PERFORMANCE);
  }

  /// Parse time string to DateTime (same format as TimeTrackingService)
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

          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    } catch (e) {
      print('❌ Error parsing time string: $e');
    }
    return DateTime.now();
  }

  /// Calculate scheduled work hours (checkOutTime - checkInTime)
  static Duration calculateScheduledHours(
      String checkInTime, String checkOutTime) {
    try {
      final checkInDateTime = _parseTimeString(checkInTime);
      final checkOutDateTime = _parseTimeString(checkOutTime);

      if (checkOutDateTime.isBefore(checkInDateTime)) {
        final nextDayCheckOut = checkOutDateTime.add(Duration(days: 1));
        return nextDayCheckOut.difference(checkInDateTime);
      } else {
        return checkOutDateTime.difference(checkInDateTime);
      }
    } catch (e) {
      print('❌ Error calculating scheduled hours: $e');
      return Duration.zero;
    }
  }

  /// Check if check-in is on-time (within the scheduled check-in time)
  static bool isOnTimeCheckIn(
      String scheduledCheckInTime, String actualCheckInTime) {
    try {
      final scheduled = _parseTimeString(scheduledCheckInTime);
      final actual = _parseTimeString(actualCheckInTime);

      final now = DateTime.now();
      final todayScheduled = DateTime(
          now.year, now.month, now.day, scheduled.hour, scheduled.minute);
      final todayActual =
          DateTime(now.year, now.month, now.day, actual.hour, actual.minute);

      // On-time if actual check-in is before or at scheduled time
      // Allow 15 minutes grace period
      final difference = todayActual.difference(todayScheduled);
      return difference.inMinutes <= 15 && difference.inMinutes >= 0;
    } catch (e) {
      print('❌ Error checking on-time status: $e');
      return false;
    }
  }

  /// Check if check-in is late
  static bool isLateCheckIn(
      String scheduledCheckInTime, String actualCheckInTime) {
    try {
      final scheduled = _parseTimeString(scheduledCheckInTime);
      final actual = _parseTimeString(actualCheckInTime);

      final now = DateTime.now();
      final todayScheduled = DateTime(
          now.year, now.month, now.day, scheduled.hour, scheduled.minute);
      final todayActual =
          DateTime(now.year, now.month, now.day, actual.hour, actual.minute);

      // Late if actual check-in is more than 15 minutes after scheduled time
      final difference = todayActual.difference(todayScheduled);
      return difference.inMinutes > 15;
    } catch (e) {
      print('❌ Error checking late status: $e');
      return false;
    }
  }

  /// Record attendance for a day
  static Future<void> recordAttendance(
    String driverId, {
    required String date,
    required String? scheduledCheckInTime,
    required String? actualCheckInTime,
    required String? scheduledCheckOutTime,
    required String? actualCheckOutTime,
    required Duration workHours,
    required Duration scheduledHours,
    required bool isOnTime,
    required bool isLate,
    required bool isAbsent,
    required bool isUndertime,
    bool isExcused = false,
  }) async {
    try {
      final attendanceData = {
        'date': date,
        'scheduledCheckInTime': scheduledCheckInTime,
        'actualCheckInTime': actualCheckInTime,
        'scheduledCheckOutTime': scheduledCheckOutTime,
        'actualCheckOutTime': actualCheckOutTime,
        'workHours': workHours.inMinutes, // Store as minutes
        'scheduledHours': scheduledHours.inMinutes,
        'isOnTime': isOnTime,
        'isLate': isLate,
        'isAbsent': isAbsent,
        'isUndertime': isUndertime,
        'isExcused': isExcused,
        'recordedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .doc(date)
          .set(attendanceData);
    } catch (e) {
      print('❌ Error recording attendance: $e');
    }
  }

  /// Check if driver had perfect attendance for the last N consecutive days
  /// Perfect attendance = on-time check-in + completed full scheduled hours
  static Future<bool> hasPerfectAttendanceStreak(
      String driverId, int days) async {
    try {
      final now = DateTime.now();
      final attendanceRecords = <Map<String, dynamic>>[];

      // Get attendance records for the last N days
      for (int i = 0; i < days; i++) {
        final date = now.subtract(Duration(days: i));
        final dateString = DateFormat('yyyy-MM-dd').format(date);

        final doc = await _firestore
            .collection('users')
            .doc(driverId)
            .collection('attendance_history')
            .doc(dateString)
            .get();

        if (!doc.exists) {
          // Missing record means no perfect attendance
          return false;
        }

        final data = doc.data()!;
        attendanceRecords.add(data);
      }

      // Check if all records show perfect attendance
      for (final record in attendanceRecords) {
        final isOnTime = record['isOnTime'] as bool? ?? false;
        final isUndertime = record['isUndertime'] as bool? ?? false;

        // Perfect attendance requires: on-time AND not undertime
        if (!isOnTime || isUndertime) {
          return false;
        }
      }

      return true;
    } catch (e) {
      print('❌ Error checking perfect attendance streak: $e');
      return false;
    }
  }

  /// Apply performance adjustment for check-in (on-time or late)
  static Future<double> applyCheckInAdjustment(String driverId,
      String scheduledCheckInTime, String actualCheckInTime) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return 100.0;

      final currentPerformance =
          (currentUserDoc.data()?['driver_performance'] as num?)?.toDouble() ??
              100.0;

      double adjustment = 0.0;

      final isOnTime = isOnTimeCheckIn(scheduledCheckInTime, actualCheckInTime);
      final isLate = isLateCheckIn(scheduledCheckInTime, actualCheckInTime);

      if (isOnTime) {
        adjustment = ADJUSTMENT_ON_TIME_CHECKIN;
      } else if (isLate) {
        adjustment = ADJUSTMENT_LATE_CHECKIN;
      }

      final newPerformance = clampPerformance(currentPerformance + adjustment);

      await _firestore.collection('users').doc(driverId).update({
        'driver_performance': newPerformance,
      });

      // Create partial attendance record at check-in
      // This prevents the day from being marked as absent if user doesn't check out
      final today = TimeTrackingService.getTodayDateString();
      final userData = currentUserDoc.data()!;
      final scheduledCheckOutTime = userData['checkOutTime'] as String?;

      await recordAttendance(driverId,
          date: today,
          scheduledCheckInTime: scheduledCheckInTime,
          actualCheckInTime: actualCheckInTime,
          scheduledCheckOutTime: scheduledCheckOutTime,
          actualCheckOutTime: null, // Not checked out yet
          workHours: Duration.zero, // Will be calculated at check-out
          scheduledHours: scheduledCheckOutTime != null
              ? calculateScheduledHours(
                  scheduledCheckInTime, scheduledCheckOutTime)
              : Duration.zero,
          isOnTime: isOnTime,
          isLate: isLate,
          isAbsent: false,
          isUndertime: false);

      return newPerformance;
    } catch (e) {
      print('❌ Error applying check-in adjustment: $e');
      return 100.0;
    }
  }

  /// Apply performance adjustments for check-out
  static Future<double> applyCheckOutAdjustments(
    String driverId, {
    required String? scheduledCheckInTime,
    required String actualCheckInTime,
    required String? scheduledCheckOutTime,
    required String actualCheckOutTime,
  }) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return 100.0;

      final currentPerformance =
          (currentUserDoc.data()?['driver_performance'] as num?)?.toDouble() ??
              100.0;

      double adjustment = 0.0;

      // Calculate work hours and scheduled hours
      final workDuration = TimeTrackingService.calculateWorkDuration(
          actualCheckInTime, actualCheckOutTime);
      final scheduledDuration = scheduledCheckInTime != null &&
              scheduledCheckOutTime != null
          ? calculateScheduledHours(scheduledCheckInTime, scheduledCheckOutTime)
          : Duration.zero;

      final workHours = workDuration.inHours + (workDuration.inMinutes / 60.0);
      final scheduledHours =
          scheduledDuration.inHours + (scheduledDuration.inMinutes / 60.0);

      // Check for undertime (work hours < scheduled hours)
      final isUndertime = scheduledHours > 0 && workHours < scheduledHours;
      if (isUndertime) {
        adjustment += ADJUSTMENT_UNDERTIME;
      }

      // Check for 5-hour bonus
      if (workHours >= 5.0) {
        adjustment += ADJUSTMENT_COMPLETE_5_HOURS;
      }

      // Check for perfect attendance streak (7 days)
      final hasPerfectStreak =
          await hasPerfectAttendanceStreak(driverId, PERFECT_ATTENDANCE_DAYS);
      if (hasPerfectStreak) {
        adjustment += ADJUSTMENT_PERFECT_ATTENDANCE_7_DAYS;
      }

      // Update attendance record for today with check-out information
      // The record should already exist from check-in, and we update it with complete data
      final today = TimeTrackingService.getTodayDateString();
      final isOnTime = scheduledCheckInTime != null
          ? isOnTimeCheckIn(scheduledCheckInTime, actualCheckInTime)
          : false;
      final isLate = scheduledCheckInTime != null
          ? isLateCheckIn(scheduledCheckInTime, actualCheckInTime)
          : false;

      // Update attendance record with complete check-in and check-out data
      // This will update the existing record created at check-in
      await recordAttendance(driverId,
          date: today,
          scheduledCheckInTime: scheduledCheckInTime,
          actualCheckInTime: actualCheckInTime,
          scheduledCheckOutTime: scheduledCheckOutTime,
          actualCheckOutTime: actualCheckOutTime,
          workHours: workDuration,
          scheduledHours: scheduledDuration,
          isOnTime: isOnTime,
          isLate: isLate,
          isAbsent: false,
          isUndertime: isUndertime);

      final newPerformance = clampPerformance(currentPerformance + adjustment);

      await _firestore.collection('users').doc(driverId).update({
        'driver_performance': newPerformance,
      });

      return newPerformance;
    } catch (e) {
      print('❌ Error applying check-out adjustments: $e');
      return 100.0;
    }
  }

  /// Apply penalty when rider stays outside service area for 30+ minutes
  static Future<double> applyOutsideServiceAreaPenalty(String driverId) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return 100.0;

      final currentPerformance =
          (currentUserDoc.data()?['driver_performance'] as num?)?.toDouble() ??
              100.0;

      final newPerformance =
          clampPerformance(currentPerformance + ADJUSTMENT_OUTSIDE_SERVICE_AREA);

      await _firestore.collection('users').doc(driverId).update({
        'driver_performance': newPerformance,
      });

      return newPerformance;
    } catch (e) {
      print('❌ Error applying outside service area penalty: $e');
      return 100.0;
    }
  }

  /// Apply penalty for driver-fault cancellation
  static Future<double> applyCancellationPenalty(String driverId) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return 100.0;

      final currentPerformance =
          (currentUserDoc.data()?['driver_performance'] as num?)?.toDouble() ??
              100.0;

      final newPerformance =
          clampPerformance(currentPerformance + ADJUSTMENT_CANCELLATION);

      await _firestore.collection('users').doc(driverId).update({
        'driver_performance': newPerformance,
      });

      return newPerformance;
    } catch (e) {
      print('❌ Error applying cancellation penalty: $e');
      return 100.0;
    }
  }

  /// Record absent day (when driver doesn't check in)
  /// This will NOT mark as absent if the day is already excused
  /// [date] - Optional date string in 'yyyy-MM-dd' format. Defaults to today.
  static Future<double> recordAbsentDay(String driverId, {String? date}) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return 100.0;

      // Use provided date or default to today
      final targetDate = date ?? TimeTrackingService.getTodayDateString();
      final userData = currentUserDoc.data()!;
      final excusedDays = List<String>.from(userData['excusedDays'] ?? []);

      // Check if date is already excused
      if (excusedDays.contains(targetDate)) {
        print(
            'ℹ️ Driver $driverId is excused for $targetDate, skipping absence marking');
        // Return current performance without penalty
        final currentPerformance =
            (userData['driver_performance'] as num?)?.toDouble() ?? 100.0;
        return currentPerformance;
      }

      // Check if attendance record already exists for this date
      final existingRecord = await _firestore
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .doc(targetDate)
          .get();

      if (existingRecord.exists) {
        final existingData = existingRecord.data()!;
        final isAlreadyAbsent = existingData['isAbsent'] as bool? ?? false;
        final isAlreadyExcused = existingData['isExcused'] as bool? ?? false;
        final actualCheckInTime = existingData['actualCheckInTime'] as String?;

        // If already marked as absent or excused, skip to prevent duplicate deduction
        if (isAlreadyAbsent || isAlreadyExcused) {
          print(
              'ℹ️ Driver $driverId already has attendance record for $targetDate, skipping');
          final currentPerformance =
              (userData['driver_performance'] as num?)?.toDouble() ?? 100.0;
          return currentPerformance;
        }

        // Safeguard: If user has checked in (actualCheckInTime exists), don't overwrite with absent
        // This prevents overwriting a valid check-in record
        if (actualCheckInTime != null && actualCheckInTime.isNotEmpty) {
          print(
              'ℹ️ Driver $driverId already checked in for $targetDate (check-in time: $actualCheckInTime), skipping absence marking');
          final currentPerformance =
              (userData['driver_performance'] as num?)?.toDouble() ?? 100.0;
          return currentPerformance;
        }
      }

      final currentPerformance =
          (userData['driver_performance'] as num?)?.toDouble() ?? 100.0;

      final newPerformance =
          clampPerformance(currentPerformance + ADJUSTMENT_ABSENT);

      // Record absent attendance
      await recordAttendance(driverId,
          date: targetDate,
          scheduledCheckInTime: null,
          actualCheckInTime: null,
          scheduledCheckOutTime: null,
          actualCheckOutTime: null,
          workHours: Duration.zero,
          scheduledHours: Duration.zero,
          isOnTime: false,
          isLate: false,
          isAbsent: true,
          isUndertime: false,
          isExcused: false);

      await _firestore.collection('users').doc(driverId).update({
        'driver_performance': newPerformance,
      });

      print(
          '✅ Marked driver $driverId as absent for $targetDate (performance: $currentPerformance -> $newPerformance)');
      return newPerformance;
    } catch (e) {
      print('❌ Error recording absent day: $e');
      return 100.0;
    }
  }

  /// Get current performance score
  static Future<double> getCurrentPerformance(String driverId) async {
    try {
      final doc = await _firestore.collection('users').doc(driverId).get();
      if (!doc.exists) return 100.0;

      final performance =
          (doc.data()?['driver_performance'] as num?)?.toDouble();
      return performance ?? 100.0;
    } catch (e) {
      print('❌ Error getting current performance: $e');
      return 100.0;
    }
  }

  /// Initialize performance score for existing drivers
  static Future<void> initializePerformance(String driverId) async {
    try {
      final doc = await _firestore.collection('users').doc(driverId).get();
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      // Only initialize if driver_performance doesn't exist
      if (!data.containsKey('driver_performance') ||
          data['driver_performance'] == null) {
        await _firestore.collection('users').doc(driverId).update({
          'driver_performance': 100.0,
        });
      }
    } catch (e) {
      print('❌ Error initializing performance: $e');
    }
  }

  /// Get first check-in date from attendance history
  static Future<DateTime?> getFirstCheckInDate(String driverId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .orderBy('date', descending: false)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final firstRecord = snapshot.docs.first.data();
      final dateString = firstRecord['date'] as String?;
      if (dateString == null) {
        return null;
      }

      return DateTime.parse(dateString);
    } catch (e) {
      print('❌ Error getting first check-in date: $e');
      return null;
    }
  }

  /// Check if date is within grace period after first check-in
  static Future<bool> isWithinGracePeriod(
      String driverId, String dateString) async {
    try {
      final firstCheckInDate = await getFirstCheckInDate(driverId);
      if (firstCheckInDate == null) {
        // No check-in history, apply grace period
        return true;
      }

      final targetDate = DateTime.parse(dateString);
      final daysSinceFirstCheckIn =
          targetDate.difference(firstCheckInDate).inDays;

      return daysSinceFirstCheckIn < GRACE_PERIOD_DAYS;
    } catch (e) {
      print('❌ Error checking grace period: $e');
      return false;
    }
  }

  /// Get consecutive absence count for a given date
  static Future<int> getConsecutiveAbsenceCount(
      String driverId, String dateString) async {
    try {
      final targetDate = DateTime.parse(dateString);
      int consecutiveCount = 0;
      var currentDate = targetDate;

      while (true) {
        final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
        final doc = await _firestore
            .collection('users')
            .doc(driverId)
            .collection('attendance_history')
            .doc(dateStr)
            .get();

        if (!doc.exists) {
          break;
        }

        final data = doc.data()!;
        final isAbsent = data['isAbsent'] as bool? ?? false;
        final isExcused = data['isExcused'] as bool? ?? false;

        if (isAbsent && !isExcused) {
          consecutiveCount++;
          currentDate = currentDate.subtract(Duration(days: 1));
        } else {
          break;
        }
      }

      return consecutiveCount;
    } catch (e) {
      print('❌ Error getting consecutive absence count: $e');
      return 0;
    }
  }

  /// Report absence issue/dispute
  static Future<void> reportAbsenceIssue(
    String driverId,
    String date,
    String reason,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(driverId)
          .collection('absence_disputes')
          .add({
        'date': date,
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Absence dispute reported for $date');
    } catch (e) {
      print('❌ Error reporting absence issue: $e');
      rethrow;
    }
  }

  /// Get dispute status for a date
  static Future<String?> getDisputeStatus(String driverId, String date) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(driverId)
          .collection('absence_disputes')
          .where('date', isEqualTo: date)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return snapshot.docs.first.data()['status'] as String?;
    } catch (e) {
      print('❌ Error getting dispute status: $e');
      return null;
    }
  }

  /// Detect and mark missing absences for a driver
  /// Checks for missing attendance records and marks them as absent
  /// Skips dates that are excused, already have attendance records, or are within grace period
  /// Returns the count of absences marked
  static Future<int> detectAndMarkMissingAbsences(
    String driverId, {
    int? detectionRangeDays,
  }) async {
    try {
      print('🔍 Starting absence detection for driver: $driverId');

      // Check if detection already ran today
      final userDoc = await _firestore.collection('users').doc(driverId).get();
      if (!userDoc.exists) {
        print('⚠️ User document not found for driver: $driverId');
        return 0;
      }

      final userData = userDoc.data()!;
      final lastDetection = userData['lastAbsenceDetection'] as Timestamp?;

      if (lastDetection != null) {
        final lastDate = lastDetection.toDate();
        final today = DateTime.now();
        if (lastDate.year == today.year &&
            lastDate.month == today.month &&
            lastDate.day == today.day) {
          print('ℹ️ Absence detection already ran today, skipping');
          return 0;
        }
      }

      final excusedDays = List<String>.from(userData['excusedDays'] ?? []);

      // Get all attendance records
      final snapshot = await _firestore
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .get();

      // Build set of existing dates
      final existingDates = <String>{};
      for (var doc in snapshot.docs) {
        final date = doc.data()['date'] as String?;
        if (date != null) {
          existingDates.add(date);
        }
      }

      // Calculate date range
      final rangeDays = detectionRangeDays ?? DEFAULT_DETECTION_RANGE_DAYS;
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: rangeDays));
      final todayString = TimeTrackingService.getTodayDateString();

      // Get first check-in date for grace period check
      final firstCheckInDate = await getFirstCheckInDate(driverId);

      // Check each day in the range
      int absentDaysMarked = 0;
      var currentDate = startDate;

      // Only process past dates - exclude today since attendance is still in progress
      while (currentDate.isBefore(now)) {
        final dateString = DateFormat('yyyy-MM-dd').format(currentDate);

        // Skip today - attendance is still in progress, record will be created at check-out
        if (dateString == todayString) {
          currentDate = currentDate.add(Duration(days: 1));
          continue;
        }

        // Skip if record already exists
        if (existingDates.contains(dateString)) {
          currentDate = currentDate.add(Duration(days: 1));
          continue;
        }

        // Skip if excused
        if (excusedDays.contains(dateString)) {
          currentDate = currentDate.add(Duration(days: 1));
          continue;
        }

        // Skip if within grace period (only if driver has check-in history)
        if (firstCheckInDate != null) {
          final daysSinceFirstCheckIn =
              currentDate.difference(firstCheckInDate).inDays;
          if (daysSinceFirstCheckIn < GRACE_PERIOD_DAYS) {
            print(
                'ℹ️ Skipping $dateString - within grace period after first check-in');
            currentDate = currentDate.add(Duration(days: 1));
            continue;
          }
        }

        // Mark as absent
        print(
            '📅 Detected missing attendance for $dateString, marking as absent...');
        await recordAbsentDay(driverId, date: dateString);
        absentDaysMarked++;

        currentDate = currentDate.add(Duration(days: 1));
      }

      // Update last detection timestamp
      await _firestore.collection('users').doc(driverId).update({
        'lastAbsenceDetection': FieldValue.serverTimestamp(),
      });

      if (absentDaysMarked > 0) {
        print(
            '✅ Absence detection completed: marked $absentDaysMarked day(s) as absent');
      } else {
        print('ℹ️ No missing absences detected');
      }

      return absentDaysMarked;
    } catch (e) {
      print('❌ Error detecting missing absences: $e');
      // Don't throw - fail gracefully to avoid breaking UI
      return 0;
    }
  }

  /// Record excused day (when driver excuses themselves)
  /// This does NOT apply performance penalty and does NOT mark as absent
  static Future<void> recordExcusedDay(String driverId, String date) async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(driverId).get();
      if (!currentUserDoc.exists) return;

      // Record excused attendance (isExcused: true, isAbsent: false)
      await recordAttendance(driverId,
          date: date,
          scheduledCheckInTime: null,
          actualCheckInTime: null,
          scheduledCheckOutTime: null,
          actualCheckOutTime: null,
          workHours: Duration.zero,
          scheduledHours: Duration.zero,
          isOnTime: false,
          isLate: false,
          isAbsent: false,
          isUndertime: false,
          isExcused: true);

      // Update user's excusedDays list
      final userData = currentUserDoc.data()!;
      final excusedDays = List<String>.from(userData['excusedDays'] ?? []);

      // Add date if not already present
      if (!excusedDays.contains(date)) {
        excusedDays.add(date);

        // Update user document with excusedDays
        await _firestore.collection('users').doc(driverId).update({
          'excusedDays': excusedDays,
        });
      }

      print('✅ Excused day recorded for driver $driverId on $date');
    } catch (e) {
      print('❌ Error recording excused day: $e');
    }
  }

  /// Get daily performance scores for the week
  /// Returns a map of date -> performance impact for that day
  /// Date format: 'yyyy-MM-dd'
  static Future<Map<String, double>> getWeeklyPerformanceScores(
    String driverId,
    String mondayDate,
    String sundayDate,
  ) async {
    try {
      // Query attendance records for the week
      final snapshot = await _firestore
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .where('date', isGreaterThanOrEqualTo: mondayDate)
          .where('date', isLessThanOrEqualTo: sundayDate)
          .get();

      // Initialize map with all 7 days (Mon-Sun) with 0.0
      final weeklyScores = <String, double>{};
      final monday = DateTime.parse(mondayDate);
      for (int i = 0; i < 7; i++) {
        final date = monday.add(Duration(days: i));
        final dateString = DateFormat('yyyy-MM-dd').format(date);
        weeklyScores[dateString] = 0.0;
      }

      // Calculate performance impact for each day
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final date = data['date'] as String?;
        if (date == null || !weeklyScores.containsKey(date)) {
          continue;
        }

        double dailyImpact = 0.0;

        final isAbsent = data['isAbsent'] as bool? ?? false;
        final isExcused = data['isExcused'] as bool? ?? false;
        final isLate = data['isLate'] as bool? ?? false;
        final isUndertime = data['isUndertime'] as bool? ?? false;
        final isOnTime = data['isOnTime'] as bool? ?? false;
        final workHoursMinutes = data['workHours'] as int? ?? 0;
        final workHours = workHoursMinutes / 60.0;

        // Calculate daily impact
        if (isExcused) {
          // Excused days have no impact
          dailyImpact = 0.0;
        } else if (isAbsent) {
          dailyImpact = ADJUSTMENT_ABSENT; // -3.0
        } else {
          // Check for positive adjustments
          if (isOnTime) {
            dailyImpact += ADJUSTMENT_ON_TIME_CHECKIN; // +0.5
          }
          if (isLate) {
            dailyImpact += ADJUSTMENT_LATE_CHECKIN; // -1.0
          }
          if (isUndertime) {
            dailyImpact += ADJUSTMENT_UNDERTIME; // -2.0
          }
          if (workHours >= 5.0) {
            dailyImpact += ADJUSTMENT_COMPLETE_5_HOURS; // +1.0
          }
        }

        weeklyScores[date] = dailyImpact;
      }

      return weeklyScores;
    } catch (e) {
      print('❌ Error getting weekly performance scores: $e');
      // Return empty map with all days set to 0.0 on error
      final weeklyScores = <String, double>{};
      final monday = DateTime.parse(mondayDate);
      for (int i = 0; i < 7; i++) {
        final date = monday.add(Duration(days: i));
        final dateString = DateFormat('yyyy-MM-dd').format(date);
        weeklyScores[dateString] = 0.0;
      }
      return weeklyScores;
    }
  }
}
