import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/main.dart';

class AttendanceRiderSummary {
  final String riderId;
  final String name;
  final String lastActiveDate;
  final int consecutiveAbsenceCount;
  final String attendanceStatus;
  final bool suspended;
  final bool checkedInToday;
  final bool checkedOutToday;
  final double performance;
  /// Today's check-in time (e.g. "08:30") when checked in; empty otherwise.
  final String lastCheckedInTime;

  const AttendanceRiderSummary({
    required this.riderId,
    required this.name,
    required this.lastActiveDate,
    required this.consecutiveAbsenceCount,
    required this.attendanceStatus,
    required this.suspended,
    this.checkedInToday = false,
    this.checkedOutToday = false,
    this.performance = 100.0,
    this.lastCheckedInTime = '',
  });

  /// Active today = checked in and not checked out (same as Active Riders Live Map).
  bool get activeToday => checkedInToday && !checkedOutToday;
}

class AttendanceRecord {
  final String date;
  final String status;
  final int consecutiveAbsenceCount;
  final String attendanceStatus;

  const AttendanceRecord({
    required this.date,
    required this.status,
    required this.consecutiveAbsenceCount,
    required this.attendanceStatus,
  });
}

/// Summary of a rider's attendance over a date range.
class AttendanceRangeSummary {
  final int presentDays;
  final int absentDays;
  final int totalDaysInRange;

  const AttendanceRangeSummary({
    required this.presentDays,
    required this.absentDays,
    required this.totalDaysInRange,
  });

  int get noRecordDays => totalDaysInRange - presentDays - absentDays;

  String toDisplayString() {
    final parts = <String>[];
    if (presentDays > 0) parts.add('$presentDays present');
    if (absentDays > 0) parts.add('$absentDays absent');
    if (noRecordDays > 0) parts.add('$noRecordDays no record');
    return parts.isEmpty ? 'No records' : parts.join(', ');
  }
}

class AttendanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<List<AttendanceRiderSummary>> fetchRiders() async {
    final snapshot = await _firestore
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .get();

    final riders = <AttendanceRiderSummary>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final firstName = (data['firstName'] ?? '').toString();
      final lastName = (data['lastName'] ?? '').toString();
      final name = _fullName(firstName, lastName);
      final performance = (data['driver_performance'] as num?)?.toDouble() ??
          100.0;
      final lastCheckedInTime =
          (data['todayCheckInTime'] ?? '').toString().trim();
      riders.add(
        AttendanceRiderSummary(
          riderId: doc.id,
          name: name.isEmpty ? 'Unknown Rider' : name,
          lastActiveDate: (data['lastActiveDate'] ?? '').toString(),
          consecutiveAbsenceCount:
              (data['consecutiveAbsenceCount'] ?? 0) as int,
          attendanceStatus:
              (data['attendanceStatus'] ?? 'active').toString(),
          suspended: data['suspended'] == true,
          checkedInToday: data['checkedInToday'] == true,
          checkedOutToday: data['checkedOutToday'] == true,
          performance: performance,
          lastCheckedInTime: lastCheckedInTime,
        ),
      );
    }

    riders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return riders;
  }

  static Future<Map<String, String>> fetchAttendanceStatusForDate(
    String date,
  ) async {
    final snapshot = await _firestore
        .collectionGroup('attendance_records')
        .where('date', isEqualTo: date)
        .get();

    final result = <String, String>{};
    for (final doc in snapshot.docs) {
      final parentId = doc.reference.parent.parent?.id;
      if (parentId == null) continue;
      final data = doc.data();
      result[parentId] = (data['status'] ?? '').toString();
    }
    return result;
  }

  /// Fetches attendance for a date range from attendance_history (check-in based).
  /// Present = checked in that day (has actualCheckInTime, not isAbsent).
  /// Absent = isAbsent or no check-in record.
  /// Requires Firestore index on attendance_history (collection group) + date.
  static Future<Map<String, AttendanceRangeSummary>>
      fetchAttendanceStatusForDateRange(
    String startDate,
    String endDate,
  ) async {
    final snapshot = await _firestore
        .collectionGroup('attendance_history')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .get();

    final totalDays = _daysBetween(startDate, endDate);
    final byRider = <String, Map<String, bool>>{};

    for (final doc in snapshot.docs) {
      final parentId = doc.reference.parent.parent?.id;
      if (parentId == null) continue;
      final data = doc.data();
      final date = (data['date'] ?? '').toString();
      final isAbsent = data['isAbsent'] == true;
      final actualCheckIn = (data['actualCheckInTime'] ?? '').toString();
      final hasCheckedIn = actualCheckIn.trim().isNotEmpty;
      final isPresent = !isAbsent && hasCheckedIn;
      byRider.putIfAbsent(parentId, () => {})[date] = isPresent;
    }

    final result = <String, AttendanceRangeSummary>{};
    for (final entry in byRider.entries) {
      int present = 0;
      int absent = 0;
      for (final isPresent in entry.value.values) {
        if (isPresent) {
          present++;
        } else {
          absent++;
        }
      }
      result[entry.key] = AttendanceRangeSummary(
        presentDays: present,
        absentDays: absent,
        totalDaysInRange: totalDays,
      );
    }
    return result;
  }

  static int _daysBetween(String start, String end) {
    final s = _parseDate(start);
    final e = _parseDate(end);
    if (s == null || e == null) return 0;
    return e.difference(s).inDays + 1;
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

  /// Fetches attendance history from attendance_history (check-in based).
  static Future<List<AttendanceRecord>> fetchAttendanceHistory(
    String riderId,
  ) async {
    final snapshot = await _firestore
        .collection(USERS)
        .doc(riderId)
        .collection('attendance_history')
        .orderBy('date', descending: true)
        .limit(30)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      final isAbsent = data['isAbsent'] == true;
      final actualCheckIn = (data['actualCheckInTime'] ?? '').toString();
      final hasCheckedIn = actualCheckIn.trim().isNotEmpty;
      final isPresent = !isAbsent && hasCheckedIn;
      final status = isPresent ? 'present' : 'absent';
      String attendanceStatus = 'active';
      if (data['isExcused'] == true) {
        attendanceStatus = 'excused';
      } else if (isAbsent) {
        attendanceStatus = 'absent';
      } else if (data['isLate'] == true) {
        attendanceStatus = 'late';
      } else if (data['isOnTime'] == true) {
        attendanceStatus = 'on-time';
      }
      return AttendanceRecord(
        date: (data['date'] ?? '').toString(),
        status: status,
        consecutiveAbsenceCount: 0,
        attendanceStatus: attendanceStatus,
      );
    }).toList();
  }

  static Future<void> applyManualStatusChange({
    required String riderId,
    required String newStatus,
    required String reason,
    required bool resetAbsences,
  }) async {
    final now = DateTime.now();
    final today = _formatDate(now);
    final adminId = MyAppState.currentUser?.userID ?? '';
    final adminName = MyAppState.currentUser?.fullName() ?? 'Admin';

    final riderRef = _firestore.collection(USERS).doc(riderId);
    final riderSnapshot = await riderRef.get();
    final previousStatus =
        (riderSnapshot.data()?['attendanceStatus'] ?? 'active').toString();

    final updates = <String, dynamic>{
      'attendanceStatus': newStatus,
      'lastAdminOverrideDate': today,
      'lastAdminOverrideBy': adminId.isEmpty ? adminName : adminId,
      'lastAdminOverrideReason': reason,
      'lastAdminOverrideAction': newStatus,
      'suspended': newStatus == 'suspended',
    };

    if (newStatus == 'warned') {
      updates['lastAbsenceWarningDate'] = today;
    }

    if (resetAbsences) {
      updates['consecutiveAbsenceCount'] = 0;
      updates['lastAbsenceWarningDate'] = '';
    }

    await riderRef.update(updates);

    await riderRef.collection('attendance_audit').add({
      'adminId': adminId.isEmpty ? adminName : adminId,
      'adminName': adminName,
      'action': newStatus,
      'reason': reason,
      'timestamp': Timestamp.fromDate(now),
      'previousStatus': previousStatus,
      'newStatus': newStatus,
    });
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _fullName(String first, String last) {
    final name = '${first.trim()} ${last.trim()}'.trim();
    return name;
  }
}
