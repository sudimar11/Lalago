import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/services/localDatabase.dart';

/// Wraps CartDatabase.watchProducts and exposes cart items and item count
/// for granular Consumer/Selector rebuilds.
class CartStateNotifier extends ChangeNotifier {
  CartStateNotifier(this._cartDb) {
    _subscription = _cartDb.watchProducts.listen((items) {
      _items = items;
      _itemCount = items.fold<int>(0, (sum, p) => sum + p.quantity);
      notifyListeners();
    });
  }

  final CartDatabase _cartDb;
  StreamSubscription<List<CartProduct>>? _subscription;
  List<CartProduct> _items = [];
  int _itemCount = 0;

  List<CartProduct> get items => List.unmodifiable(_items);
  int get itemCount => _itemCount;

  CartDatabase get cartDatabase => _cartDb;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
