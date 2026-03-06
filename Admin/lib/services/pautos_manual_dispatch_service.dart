import 'package:cloud_functions/cloud_functions.dart';

/// Service for manual PAUTOS assignment from Admin dispatcher.
class PautosManualDispatchService {
  static const _collection = 'pautos_orders';

  /// Assign a PAUTOS order to a specific driver via Cloud Function.
  Future<bool> assignPautosOrder({
    required String orderId,
    required String driverId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pautosManualAssign');
      await callable.call({'orderId': orderId, 'driverId': driverId});
      return true;
    } on FirebaseFunctionsException catch (_) {
      return false;
    }
  }
}
