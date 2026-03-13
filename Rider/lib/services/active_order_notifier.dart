import 'package:flutter/foundation.dart';

/// Shared state for the currently selected order ID when rider has multiple
/// active orders. Used by HomeScreen (writes on switch) and ContainerScreen
/// (reads for OrderLocationService).
class ActiveOrderNotifier {
  ActiveOrderNotifier._();
  static final ActiveOrderNotifier instance = ActiveOrderNotifier._();

  final ValueNotifier<String?> selectedOrderId = ValueNotifier<String?>(null);

  /// Update the selected order. Call from HomeScreen when rider switches orders.
  void setSelectedOrderId(String? orderId) {
    if (selectedOrderId.value != orderId) {
      selectedOrderId.value = orderId;
    }
  }

  /// Clear selection when rider has no active orders.
  void clear() {
    selectedOrderId.value = null;
  }
}
