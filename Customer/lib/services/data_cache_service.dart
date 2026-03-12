import 'package:flutter/foundation.dart';

import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';

/// In-memory session cache for home screen data.
/// Reduces duplicate fetches and enables shared access across sections.
class DataCacheService extends ChangeNotifier {
  DataCacheService._();
  static final DataCacheService _instance = DataCacheService._();
  static DataCacheService get instance => _instance;

  List<VendorCategoryModel>? _categories;
  final Map<String, VendorModel> _vendorsById = {};
  List<ProductModel>? _products;

  List<VendorCategoryModel>? get categories => _categories;
  List<ProductModel>? get products => _products;

  void setCategories(List<VendorCategoryModel> v) {
    _categories = List.from(v);
    notifyListeners();
  }

  void putVendor(VendorModel v) {
    if (v.id.isNotEmpty) {
      _vendorsById[v.id] = v;
    }
  }

  void putVendors(List<VendorModel> vendors) {
    for (final v in vendors) {
      if (v.id.isNotEmpty) _vendorsById[v.id] = v;
    }
  }

  VendorModel? getVendor(String id) => _vendorsById[id];

  void setProducts(List<ProductModel> v) {
    _products = List.from(v);
    notifyListeners();
  }

  /// Clear cache (e.g. on logout or delivery type change).
  void clear() {
    _categories = null;
    _vendorsById.clear();
    _products = null;
    notifyListeners();
  }
}
