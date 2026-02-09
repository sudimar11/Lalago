import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/customer_suggestion.dart';
import 'package:brgy/model/driver_report.dart';

class CustomerSuggestionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get stream of all customer suggestions
  static Stream<QuerySnapshot> getSuggestionsStream() {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'service_suggestion')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get suggestions filtered by status
  static Stream<QuerySnapshot> getSuggestionsByStatus(String status) {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'service_suggestion')
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get suggestions filtered by category
  static Stream<QuerySnapshot> getSuggestionsByCategory(String category) {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'service_suggestion')
        .where('category', isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get suggestions filtered by date range
  static Stream<QuerySnapshot> getSuggestionsByDateRange(
    DateTime start,
    DateTime end,
  ) {
    final startTimestamp = Timestamp.fromDate(start);
    final endTimestamp = Timestamp.fromDate(end);
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'service_suggestion')
        .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
        .where('createdAt', isLessThanOrEqualTo: endTimestamp)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get a single suggestion by ID
  static Future<CustomerSuggestion?> getSuggestionById(
    String suggestionId,
  ) async {
    try {
      final doc = await _firestore
          .collection(REPORTS)
          .doc(suggestionId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['type'] == 'service_suggestion') {
          return CustomerSuggestion.fromJson(data, doc.id);
        }
      }
      return null;
    } catch (e) {
      print('Error getting suggestion by ID: $e');
      return null;
    }
  }

  /// Update suggestion status only (read-only for customers/orders)
  static Future<void> updateSuggestionStatus(
    String suggestionId,
    SuggestionStatus status,
    String adminId,
    String adminName,
  ) async {
    try {
      await _firestore.collection(REPORTS).doc(suggestionId).update({
        'status': status.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'reviewedByName': adminName,
      });
    } catch (e) {
      throw Exception('Failed to update suggestion status: $e');
    }
  }

  /// Add admin note to suggestion (read-only for customers/orders)
  static Future<void> addAdminNote(
    String suggestionId,
    String note,
    String adminId,
    String adminName,
  ) async {
    try {
      final suggestionDoc = await _firestore
          .collection(REPORTS)
          .doc(suggestionId)
          .get();
      if (!suggestionDoc.exists) {
        throw Exception('Suggestion not found');
      }

      final data = suggestionDoc.data()!;
      List<dynamic> existingNotes = data['adminNotes'] ?? [];

      final newNote = AdminNote(
        note: note,
        adminId: adminId,
        adminName: adminName,
        createdAt: Timestamp.now(),
      );

      existingNotes.add(newNote.toJson());

      await _firestore.collection(REPORTS).doc(suggestionId).update({
        'adminNotes': existingNotes,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'reviewedByName': adminName,
      });
    } catch (e) {
      throw Exception('Failed to add admin note: $e');
    }
  }

  /// Get count of new suggestions
  static Stream<int> getNewSuggestionsCount() {
    return _firestore
        .collection(REPORTS)
        .where('type', isEqualTo: 'service_suggestion')
        .where('status', isEqualTo: 'new')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get count of suggestions by status
  static Future<int> getSuggestionsCountByStatus(String status) async {
    try {
      final snapshot = await _firestore
          .collection(REPORTS)
          .where('type', isEqualTo: 'service_suggestion')
          .where('status', isEqualTo: status)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting suggestions count by status: $e');
      return 0;
    }
  }

  /// Get all suggestions count
  static Future<int> getAllSuggestionsCount() async {
    try {
      final snapshot = await _firestore
          .collection(REPORTS)
          .where('type', isEqualTo: 'service_suggestion')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting all suggestions count: $e');
      return 0;
    }
  }
}

