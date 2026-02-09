import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_order_completion.freezed.dart';
part 'pending_order_completion.g.dart';

@freezed
class PendingOrderCompletion with _$PendingOrderCompletion {
  const factory PendingOrderCompletion({
    required String orderId,
    required double earning,
    required double totalCommission,
    required double totalPayment,
    required double incentive,
    required double deliveryCharge,
    required double tipAmount,
    required double platformCommission,
    required double restaurantCommission,
    required double totalEarning,
    required int totalItemCount,
    required double itemsTotal,
    required Map<String, dynamic> orderData,
    required DateTime createdAt,
    @Default(0) int retryCount,
    @Default(false) bool isProcessing,
  }) = _PendingOrderCompletion;

  factory PendingOrderCompletion.fromJson(Map<String, dynamic> json) =>
      _$PendingOrderCompletionFromJson(json);
}













