import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for user-taught Tausug word mappings.
/// Same Firestore collection as Customer app (tausug_teachings).
const tausugTeachingsCollection = 'tausug_teachings';

/// Result of parsing a teaching message.
class TeachingResult {
  const TeachingResult({
    required this.tausugWord,
    required this.englishMeaning,
  });

  final String tausugWord;
  final String englishMeaning;
}

class TausugTeachingsService {
  static final _firestore = FirebaseFirestore.instance;

  static const _triggers = ['correction', 'teach', 'learn', 'teaching'];

  static bool isTeachingMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (_triggers.any((t) => lower.startsWith(t))) return true;
    if (RegExp(r'\bmeans\b', caseSensitive: false).hasMatch(trimmed)) return true;
    if (RegExp(r'\bis\s+called\b', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  static TeachingResult? parseTeachingMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    String text = trimmed;
    for (final t in _triggers) {
      final lower = text.toLowerCase();
      if (lower.startsWith(t)) {
        text = text.substring(t.length).trim();
        if (text.startsWith(':') || text.startsWith(',')) {
          text = text.substring(1).trim();
        }
        break;
      }
    }

    final meansMatch = RegExp(
      '^["\']?(.+?)["\']?\\s+means\\s+(.+)\$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (meansMatch != null) {
      final quoteRegex = RegExp('^["\']|["\']\$');
      final word = meansMatch.group(1)!.trim().replaceAll(quoteRegex, '');
      final meaning = meansMatch.group(2)!.trim().replaceAll(quoteRegex, '');
      if (word.isNotEmpty && meaning.isNotEmpty) {
        return TeachingResult(tausugWord: word, englishMeaning: meaning);
      }
    }

    final calledMatch = RegExp(
      '^["\']?(.+?)["\']?\\s+is\\s+called\\s+(.+)\$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (calledMatch != null) {
      final quoteRegex = RegExp('^["\']|["\']\$');
      final word = calledMatch.group(1)!.trim().replaceAll(quoteRegex, '');
      final meaning = calledMatch.group(2)!.trim().replaceAll(quoteRegex, '');
      if (word.isNotEmpty && meaning.isNotEmpty) {
        return TeachingResult(tausugWord: word, englishMeaning: meaning);
      }
    }

    return null;
  }

  static Future<DocumentReference> store({
    required String userId,
    required String tausugWord,
    required String englishMeaning,
    bool verified = false,
  }) async {
    final ref = await _firestore.collection(tausugTeachingsCollection).add({
      'userId': userId,
      'tausugWord': tausugWord.trim(),
      'englishMeaning': englishMeaning.trim(),
      'verified': verified,
      'timestamp': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  static Future<int> getTeachingCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(tausugTeachingsCollection)
          .where('userId', isEqualTo: userId)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentTeachings(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(tausugTeachingsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> getTeachingsHintForQuery(
    String userQuery, {
    Map<String, String> sessionCache = const {},
  }) async {
    final lower = userQuery.toLowerCase();
    final hints = <String>[];

    for (final e in sessionCache.entries) {
      if (lower.contains(e.key.toLowerCase())) {
        hints.add("- '${e.key}' means '${e.value}' (recently taught)");
      }
    }

    try {
      final snapshot = await _firestore
          .collection(tausugTeachingsCollection)
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      final seen = <String>{};
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final verified = d['verified'] as bool? ?? false;
        final word = ((d['tausugWord'] ?? '') as String).trim();
        final meaning = ((d['englishMeaning'] ?? '') as String).trim();
        if (word.isEmpty || meaning.isEmpty) continue;
        final key = '${word.toLowerCase()}|$meaning';
        if (seen.contains(key)) continue;
        final inCache = sessionCache.keys
            .any((k) => k.toLowerCase() == word.toLowerCase());
        if (inCache) continue;
        if (!lower.contains(word.toLowerCase())) continue;
        seen.add(key);
        hints.add("- '${word}' means '${meaning}'${verified ? ' (verified)' : ''}");
        if (hints.length >= 10) break;
      }
    } catch (_) {}

    if (hints.isEmpty) return '';
    return 'Learned Tausug words (use for context):\n${hints.join('\n')}\n\n';
  }
}
