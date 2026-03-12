import 'package:cloud_functions/cloud_functions.dart';

class PautosDisputeService {
  static final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<Map<String, dynamic>> getOrderForAdmin(String orderId) async {
    final result = await _functions
        .httpsCallable('pautosGetOrderForAdmin')
        .call({'orderId': orderId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> issueRefund({
    required String orderId,
    required double amount,
    String? reason,
  }) async {
    await _functions.httpsCallable('pautosIssueRefund').call({
      'orderId': orderId,
      'amount': amount,
      'reason': reason ?? '',
    });
  }

  static Future<void> adjustRiderEarnings({
    required String orderId,
    required double adjustmentAmount,
    String? reason,
  }) async {
    await _functions.httpsCallable('pautosAdjustRiderEarnings').call({
      'orderId': orderId,
      'adjustmentAmount': adjustmentAmount,
      'reason': reason ?? '',
    });
  }

  static Future<void> addDisputeNote({
    required String orderId,
    required String note,
  }) async {
    await _functions.httpsCallable('pautosAddDisputeNote').call({
      'orderId': orderId,
      'note': note,
    });
  }
}
