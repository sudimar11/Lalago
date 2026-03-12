import 'dart:async';

import 'package:flutter/foundation.dart';

/// Exposes the order ID to highlight when "food ready" is received.
/// Used by OrdersBlankScreen/RefreshableOrderList to show visual highlight.
class FoodReadyHighlightService {
  FoodReadyHighlightService._();

  static final FoodReadyHighlightService instance = FoodReadyHighlightService._();

  final ValueNotifier<String?> highlightedOrderId = ValueNotifier<String?>(null);

  Timer? _clearTimer;

  void setHighlighted(String orderId) {
    highlightedOrderId.value = orderId;
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 30), () {
      if (highlightedOrderId.value == orderId) {
        highlightedOrderId.value = null;
      }
      _clearTimer = null;
    });
  }

  void clearHighlight([String? orderId]) {
    if (orderId == null || highlightedOrderId.value == orderId) {
      highlightedOrderId.value = null;
    }
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
