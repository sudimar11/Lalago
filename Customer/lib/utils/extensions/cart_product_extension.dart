import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/model/variant_info.dart';
import 'package:foodie_customer/services/localDatabase.dart';

extension CartProductExtension on CartProduct {
  String get safeDiscountPrice => discountPrice ?? "";

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
