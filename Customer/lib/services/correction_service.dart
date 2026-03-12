import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for storing and fetching AI chat corrections.
/// Privacy: stores only userId, query, response, correction; no personal info.
const aiCorrectionsCollection = 'ai_corrections';

/// Tausug words used for relevance matching (subset for correction lookup).
const tausugDetectionWords = [
  'tiyula', 'tiula', 'pastil', 'pyanggang', 'tiyulah itum',
  'satti', 'juring', 'lumpia', 'putli', 'durul', 'kaun',
  'mangaun', 'hawnu', 'unu', 'masarap', 'mananam', 'malimu',
  'malara', 'mapa\'it', 'maslum', 'maasin',
];

class CorrectionService {
  static final _firestore = FirebaseFirestore.instance;

  /// Stores a correction. Call with empty correction for positive feedback.
  static Future<void> store({
    required String userId,
    required String userQuery,
    required String aiResponse,
    required String userCorrection,
    required List<String> detectedTausug,
  }) async {
    await _firestore.collection(aiCorrectionsCollection).add({
      'userId': userId,
      'userQuery': userQuery,
      'aiResponse': aiResponse,
      'userCorrection': userCorrection,
      'detectedTausug': detectedTausug,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Returns a hint string from recent corrections relevant to the query.
  /// Uses client-side filtering to avoid Firestore composite indexes.
  static Future<String> getRelevantCorrectionHint(String userQuery) async {
    final lower = userQuery.toLowerCase();
    final queryWords = tausugDetectionWords
        .where((w) => lower.contains(w))
        .toList();
    if (queryWords.isEmpty) return '';

    try {
      final snapshot = await _firestore
          .collection(aiCorrectionsCollection)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

    final hints = <String>[];
    for (final doc in snapshot.docs) {
      final d = doc.data();
      final correction = (d['userCorrection'] ?? '').toString();
      if (correction.isEmpty) continue;

      final storedTausug =
          (d['detectedTausug'] as List?)?.cast<String>() ?? [];
      final overlap = queryWords
          .any((w) => storedTausug.any((s) => s == w || s.contains(w)));
      if (!overlap) continue;

      final originalQuery = (d['userQuery'] ?? '').toString();
      hints.add('When asked "$originalQuery", users suggested: "$correction"');
      if (hints.length >= 5) break;
    }

    if (hints.isEmpty) return '';
    return 'Based on previous user feedback:\n${hints.join('\n')}\n\n';
    } catch (e) {
      return '';
    }
  }
}
