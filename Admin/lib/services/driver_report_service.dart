import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/driver_report.dart';

class DriverReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get stream of all driver reports
  static Stream<QuerySnapshot> getDriverReportsStream() {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get driver reports filtered by status
  static Stream<QuerySnapshot> getDriverReportsByStatus(String status) {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get driver reports filtered by driver ID
  static Stream<QuerySnapshot> getDriverReportsByDriver(String driverId) {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get driver reports filtered by order ID
  static Stream<QuerySnapshot> getDriverReportsByOrder(String orderId) {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .where('orderId', isEqualTo: orderId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get driver reports filtered by date range
  static Stream<QuerySnapshot> getDriverReportsByDateRange(
    DateTime start,
    DateTime end,
  ) {
    final startTimestamp = Timestamp.fromDate(start);
    final endTimestamp = Timestamp.fromDate(end);
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
        .where('createdAt', isLessThanOrEqualTo: endTimestamp)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get a single report by ID
  static Future<DriverReport?> getReportById(String reportId) async {
    try {
      final doc = await _firestore.collection(REPORTS).doc(reportId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['type'] == 'driver_report') {
          return DriverReport.fromJson(data, doc.id);
        }
      }
      return null;
    } catch (e) {
      print('Error getting report by ID: $e');
      return null;
    }
  }

  /// Update report status only (read-only for orders/drivers)
  static Future<void> updateReportStatus(
    String reportId,
    String status,
    String adminId,
  ) async {
    try {
      await _firestore.collection(REPORTS).doc(reportId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminId,
      });
    } catch (e) {
      throw Exception('Failed to update report status: $e');
    }
  }

  /// Add admin note to report (read-only for orders/drivers)
  static Future<void> addAdminNote(
    String reportId,
    String note,
    String adminId,
    String adminName,
  ) async {
    try {
      final reportDoc = await _firestore.collection(REPORTS).doc(reportId).get();
      if (!reportDoc.exists) {
        throw Exception('Report not found');
      }

      final data = reportDoc.data()!;
      List<dynamic> existingNotes = data['adminNotes'] ?? [];

      final newNote = AdminNote(
        note: note,
        adminId: adminId,
        adminName: adminName,
        createdAt: Timestamp.now(),
      );

      existingNotes.add(newNote.toJson());

      await _firestore.collection(REPORTS).doc(reportId).update({
        'adminNotes': existingNotes,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminId,
      });
    } catch (e) {
      throw Exception('Failed to add admin note: $e');
    }
  }

  /// Get count of pending reports
  static Stream<int> getPendingReportsCount() {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'driver_report')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get count of reports by status
  static Future<int> getReportsCountByStatus(String status) async {
    try {
      final snapshot = await _firestore
          .collection(REPORTS)
          .where('type', isEqualTo: 'driver_report')
          .where('status', isEqualTo: status)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting reports count by status: $e');
      return 0;
    }
  }

  /// Get all reports count
  static Future<int> getAllReportsCount() async {
    try {
      final snapshot = await _firestore
          .collection(REPORTS)
          .where('type', isEqualTo: 'driver_report')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting all reports count: $e');
      return 0;
    }
  }
}

