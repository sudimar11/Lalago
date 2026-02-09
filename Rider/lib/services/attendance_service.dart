import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/User.dart';

class AttendanceStatus {
  final bool isSuspended;
  final bool showWarning;

  const AttendanceStatus({
    required this.isSuspended,
    required this.showWarning,
  });
}

class AttendanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<User?> fetchLatestUser(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final snapshot = await _firestore.collection(USERS).doc(userId).get();
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return User.fromJson(snapshot.data()!);
    } catch (e) {
      log('AttendanceService.fetchLatestUser error: $e');
      return null;
    }
  }

  static Future<void> touchLastActiveDate(User user) async {
    final today = _todayString();
    user.lastActiveDate = today;
    try {
      await _firestore.collection(USERS).doc(user.userID).update({
        'lastActiveDate': today,
      });
      await _firestore
          .collection(USERS)
          .doc(user.userID)
          .collection('attendance_records')
          .doc(today)
          .set({
        'date': today,
        'status': 'present',
        'lastActiveDate': today,
        'consecutiveAbsenceCount': user.consecutiveAbsenceCount ?? 0,
        'attendanceStatus': user.attendanceStatus ?? 'active',
      }, SetOptions(merge: true));
    } catch (e) {
      log('AttendanceService.touchLastActiveDate error: $e');
    }
  }

  static Future<AttendanceStatus> evaluateAndUpdateAttendance(
    User user,
  ) async {
    final today = _todayString();
    final lastActive = _parseDate(user.lastActiveDate);
    final overrideToday = user.lastAdminOverrideDate == today;

    if (lastActive == null) {
      user.lastActiveDate = today;
      user.attendanceStatus = 'active';
      user.consecutiveAbsenceCount = 0;
      await _updateUserFields(user.userID, {
        'lastActiveDate': today,
        'attendanceStatus': 'active',
        'consecutiveAbsenceCount': 0,
      });
      await _writeAttendanceRecord(
        user.userID,
        today,
        status: 'present',
        attendanceStatus: 'active',
        consecutiveAbsenceCount: 0,
        lastActiveDate: today,
      );
      return const AttendanceStatus(
        isSuspended: false,
        showWarning: false,
      );
    }

    final dayGap = _dayGap(lastActive, _todayDateTime());
    final isSuspended = user.suspended == true ||
        (user.attendanceStatus?.toLowerCase() == 'suspended');

    if (overrideToday) {
      return AttendanceStatus(
        isSuspended: isSuspended,
        showWarning:
            user.attendanceStatus?.toLowerCase() == 'warned' && !isSuspended,
      );
    }

    await _backfillAbsentRecords(user.userID, lastActive, today);
    final consecutiveAbsences = dayGap > 1 ? dayGap - 1 : 0;
    user.consecutiveAbsenceCount = consecutiveAbsences;

    if (dayGap >= 3 && !isSuspended) {
      user.suspended = true;
      user.attendanceStatus = 'suspended';
      user.suspensionDate = DateTime.now().millisecondsSinceEpoch;
      await _updateUserFields(user.userID, {
        'suspended': true,
        'suspension_date': user.suspensionDate,
        'attendanceStatus': 'suspended',
        'consecutiveAbsenceCount': consecutiveAbsences,
      });
      return const AttendanceStatus(
        isSuspended: true,
        showWarning: false,
      );
    }

    if (dayGap == 2 &&
        user.lastAbsenceWarningDate != today &&
        !isSuspended) {
      user.lastAbsenceWarningDate = today;
      user.attendanceStatus = 'warned';
      await _updateUserFields(user.userID, {
        'lastAbsenceWarningDate': today,
        'attendanceStatus': 'warned',
        'consecutiveAbsenceCount': consecutiveAbsences,
      });
      return const AttendanceStatus(
        isSuspended: false,
        showWarning: true,
      );
    }

    if (dayGap <= 1 && !isSuspended) {
      user.attendanceStatus = 'active';
      await _updateUserFields(user.userID, {
        'attendanceStatus': 'active',
        'consecutiveAbsenceCount': 0,
      });
    }

    return AttendanceStatus(
      isSuspended: isSuspended,
      showWarning: false,
    );
  }

  static Future<void> _updateUserFields(
    String userId,
    Map<String, dynamic> data,
  ) async {
    if (userId.isEmpty) return;
    try {
      await _firestore.collection(USERS).doc(userId).update(data);
    } catch (e) {
      log('AttendanceService._updateUserFields error: $e');
    }
  }

  static DateTime _todayDateTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static int _dayGap(DateTime from, DateTime to) {
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return toDate.difference(fromDate).inDays;
  }

  static String _todayString() => _formatDate(DateTime.now());

  static Future<void> _writeAttendanceRecord(
    String userId,
    String date, {
    required String status,
    required String attendanceStatus,
    required int consecutiveAbsenceCount,
    required String lastActiveDate,
  }) async {
    await _firestore
        .collection(USERS)
        .doc(userId)
        .collection('attendance_records')
        .doc(date)
        .set({
      'date': date,
      'status': status,
      'attendanceStatus': attendanceStatus,
      'consecutiveAbsenceCount': consecutiveAbsenceCount,
      'lastActiveDate': lastActiveDate,
    }, SetOptions(merge: true));
  }

  static Future<void> _backfillAbsentRecords(
    String userId,
    DateTime lastActive,
    String todayString,
  ) async {
    final today = _parseDate(todayString);
    if (today == null) return;
    final start = DateTime(lastActive.year, lastActive.month, lastActive.day)
        .add(const Duration(days: 1));
    final end = DateTime(today.year, today.month, today.day);
    if (!start.isBefore(end)) return;

    DateTime cursor = start;
    int consecutiveCount = 1;
    while (cursor.isBefore(end)) {
      final date = _formatDate(cursor);
      final status = consecutiveCount >= 2 ? 'suspended' : 'warned';
      await _firestore
          .collection(USERS)
          .doc(userId)
          .collection('attendance_records')
          .doc(date)
          .set({
        'date': date,
        'status': 'absent',
        'attendanceStatus': status,
        'consecutiveAbsenceCount': consecutiveCount,
        'lastActiveDate': _formatDate(lastActive),
      }, SetOptions(merge: true));
      cursor = cursor.add(const Duration(days: 1));
      consecutiveCount += 1;
    }
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
