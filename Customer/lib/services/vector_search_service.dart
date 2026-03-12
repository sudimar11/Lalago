import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:foodie_customer/constants.dart';

/// Calls Cloud Function for vector similarity search.
/// Falls back to empty list on error so caller can use keyword search.
class VectorSearchService {
  VectorSearchService() : _functions = FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Searches products via vector similarity. Returns same format as
  /// AiProductSearchService.searchProducts. Empty list on error.
  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final stopwatch = Stopwatch()..start();
    try {
      final callable = _functions.httpsCallable(
        'vectorSearchProducts',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call<Map<String, dynamic>>({'query': trimmed});
      final data = result.data as Map<String, dynamic>? ?? {};
      final error = data['error'] as String?;
      if (error != null && error.isNotEmpty) {
        debugPrint('[VECTOR_SEARCH] Error from callable: $error');
        return [];
      }
      final products = data['products'];
      if (products is! List) return [];
      final list = products
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .map((p) {
            final url = (p['imageUrl'] ?? '').toString();
            if (url.isNotEmpty) {
              p['imageUrl'] = getImageVAlidUrl(url);
            }
            return p;
          })
          .toList();
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      debugPrint('[VECTOR_SEARCH] query="$query" duration=${ms}ms count=${list.length}');
      if (ms > 500) {
        debugPrint('[VECTOR_SEARCH] Slow: ${ms}ms exceeds 500ms target');
      }
      return list;
    } on FirebaseFunctionsException catch (e) {
      stopwatch.stop();
      debugPrint('[VECTOR_SEARCH] FirebaseFunctionsException: ${e.code} ${e.message}');
      return [];
    } on TimeoutException catch (_) {
      stopwatch.stop();
      debugPrint('[VECTOR_SEARCH] Timeout');
      return [];
    } catch (e) {
      stopwatch.stop();
      debugPrint('[VECTOR_SEARCH] Error: $e');
      return [];
    }
  }
}
