import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/model/variant_info.dart';
import 'package:foodie_customer/services/localDatabase.dart';

extension CartProductExtension on CartProduct {
  String get safeDiscountPrice => discountPrice ?? "";

  /// Parses extras string/list into a filtered list of add-on names.
  List<String> parseExtrasAsList() {
    if (extras == null) return [];
    if (extras is List) return List<String>.from(extras as List);
    final str = extras.toString().trim();
    if (str == '[]' || str.isEmpty) return [];
    final decoded = str
        .replaceAll("[", "")
        .replaceAll("]", "")
        .replaceAll("\"", "");
    if (decoded.isEmpty) return [];
    final parts = decoded.contains(",") ? decoded.split(",") : [decoded];
    return parts
        .map((e) => e.toString().trim())
        .where((s) =>
            s.isNotEmpty &&
            s != 'null' &&
            s != '[]' &&
            s != '\\' &&
            s != r'\\')
        .toList();
  }

  /// Computes line total (price * qty + extras_price * qty).
  double computeLineTotal() {
    double total = (double.tryParse(price) ?? 0) * quantity;
    if (extras_price != null &&
        extras_price!.isNotEmpty &&
        (double.tryParse(extras_price!) ?? 0) != 0) {
      total += double.parse(extras_price!) * quantity;
    }
    return total;
  }

  VariantInfo? parseVariantInfo() {
    if (variant_info == null ||
        variant_info.toString().trim().isEmpty) {
      return null;
    }
    try {
      final str = variant_info.toString().trim();
      if (!str.startsWith('{')) return null;
      return VariantInfo.fromJson(
        jsonDecode(str) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('Error parsing variant_info: $e');
      return null;
    }
  }
}
