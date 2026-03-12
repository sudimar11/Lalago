import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:foodie_restaurant/services/correction_service.dart';

/// Service for storing and fetching Tausug word corrections.
/// Same Firestore collection as Customer app (word_corrections).
const wordCorrectionsCollection = 'word_corrections';

class WordCorrectionService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<DocumentReference> store({
    required String userId,
    required String userQuery,
    required String aiResponse,
    required String correction,
    required List<String> detectedWords,
  }) async {
    final ref = await _firestore.collection(wordCorrectionsCollection).add({
      'userId': userId,
      'userQuery': userQuery,
      'aiResponse': aiResponse,
      'correction': correction,
      'detectedWords': detectedWords,
      'timestamp': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  static Future<int> getCorrectionCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(wordCorrectionsCollection)
          .where('userId', isEqualTo: userId)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<String> getCorrectionHintForQuery(String userQuery) async {
    final lower = userQuery.toLowerCase();
    final queryWords = tausugDetectionWords
        .where((w) => lower.contains(w))
        .toList();
    if (queryWords.isEmpty) return '';

    try {
      final snapshot = await _firestore
          .collection(wordCorrectionsCollection)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final hints = <String>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final correction = (d['correction'] ?? '').toString();
        if (correction.isEmpty) continue;

        final stored =
            (d['detectedWords'] as List?)?.cast<String>() ?? [];
        final overlap = queryWords
            .any((w) => stored.any((s) => s == w || s.contains(w)));
        if (!overlap) continue;

        hints.add('- $correction');
        if (hints.length >= 5) break;
      }

      if (hints.isEmpty) return '';
      return 'Previous corrections:\n${hints.join('\n')}\n\n';
    } catch (e) {
      return '';
    }
  }
}
