import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:foodie_customer/constants.dart';

/// Searches products by name or description for AI chat tool use.
/// Supports Tausug terms via mapping to English equivalents.
class AiProductSearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _tausugToEnglish = <String, List<String>>{
    'pastil': ['rice', 'wrapped rice', 'pastil'],
    'pyanggang': ['chicken', 'grilled chicken', 'spiced chicken'],
    'satti': ['satay', 'grilled meat', 'peanut sauce'],
    'tiyula': ['soup', 'broth'],
    'tiula': ['soup', 'broth'],
    'tiyulah itum': ['black soup', 'burnt coconut soup'],
    'juring': ['spring roll', 'lumpia'],
    'lumpia': ['spring roll', 'juring'],
    'putli': ['dessert', 'sweet rice'],
    'durul': ['snack', 'sweet snack'],
    'kaun': ['eat', 'food'],
    'mangaun': ['eat', 'food'],
    'masarap': ['delicious', 'tasty'],
    'mananam': ['delicious', 'tasty'],
    'malimu': ['sweet'],
    'malara': ['spicy', 'hot'],
    'mapa\'it': ['bitter'],
    'maslum': ['sour'],
    'maasin': ['salty'],
  };

  /// Builds search terms, expanding Tausug words to English equivalents.
  List<String> _buildSearchTerms(String lowerQuery) {
    final terms = <String>[lowerQuery];
    for (final entry in _tausugToEnglish.entries) {
      if (lowerQuery.contains(entry.key)) {
        terms.addAll(entry.value);
        debugPrint(
          'Tausug mapping: "${entry.key}" -> ${entry.value}',
        );
      }
    }
    return terms;
  }

  /// Searches vendor_products by name/description, returns up to 30 matches
  /// with product id, name, price, vendorID, vendorName.
  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return [];

    final searchTerms = _buildSearchTerms(lowerQuery);

    try {
      final snapshot = await _firestore
          .collection(PRODUCTS)
          .where('publish', isEqualTo: true)
          .limit(100)
          .get();

      final matches = <Map<String, dynamic>>[];
      final vendorCache = <String, String>{};

      for (final doc in snapshot.docs) {
        if (matches.length >= 30) break;

        final data = doc.data();
        final name = (data['name'] ?? '').toString().toLowerCase();
        final desc = (data['description'] ?? '').toString().toLowerCase();

        final matchesQuery = searchTerms.any((term) =>
            name.contains(term) || desc.contains(term));
        if (!matchesQuery) continue;

        final vendorID = (data['vendorID'] ?? '').toString();
        String vendorName = '';
        if (vendorID.isNotEmpty) {
          vendorName = vendorCache[vendorID] ??= await _getVendorName(vendorID);
        }

        final photo = (data['photo'] ?? '').toString();
        matches.add({
          'id': (data['id'] ?? doc.id).toString(),
          'name': (data['name'] ?? '').toString(),
          'price': (data['price'] ?? '0').toString(),
          'vendorID': vendorID,
          'vendorName': vendorName,
          'imageUrl': getImageVAlidUrl(photo),
        });
      }

      return matches;
    } catch (e) {
      return [];
    }
  }

  Future<String> _getVendorName(String vendorID) async {
    try {
      final doc = await _firestore.collection(VENDORS).doc(vendorID).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['title'] ?? '').toString();
      }
    } catch (_) {}
    return '';
  }
}
