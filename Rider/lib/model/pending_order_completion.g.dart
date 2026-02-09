// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_order_completion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PendingOrderCompletionImpl _$$PendingOrderCompletionImplFromJson(
        Map<String, dynamic> json) =>
    _$PendingOrderCompletionImpl(
      orderId: json['orderId'] as String,
      earning: (json['earning'] as num).toDouble(),
      totalCommission: (json['totalCommission'] as num).toDouble(),
      totalPayment: (json['totalPayment'] as num).toDouble(),
      incentive: (json['incentive'] as num).toDouble(),
      deliveryCharge: (json['deliveryCharge'] as num).toDouble(),
      tipAmount: (json['tipAmount'] as num).toDouble(),
      platformCommission: (json['platformCommission'] as num).toDouble(),
      restaurantCommission: (json['restaurantCommission'] as num).toDouble(),
      totalEarning: (json['totalEarning'] as num).toDouble(),
      totalItemCount: (json['totalItemCount'] as num).toInt(),
      itemsTotal: (json['itemsTotal'] as num).toDouble(),
      orderData: json['orderData'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      isProcessing: json['isProcessing'] as bool? ?? false,
    );

Map<String, dynamic> _$$PendingOrderCompletionImplToJson(
        _$PendingOrderCompletionImpl instance) =>
    <String, dynamic>{
      'orderId': instance.orderId,
      'earning': instance.earning,
      'totalCommission': instance.totalCommission,
      'totalPayment': instance.totalPayment,
      'incentive': instance.incentive,
      'deliveryCharge': instance.deliveryCharge,
      'tipAmount': instance.tipAmount,
      'platformCommission': instance.platformCommission,
      'restaurantCommission': instance.restaurantCommission,
      'totalEarning': instance.totalEarning,
      'totalItemCount': instance.totalItemCount,
      'itemsTotal': instance.itemsTotal,
      'orderData': instance.orderData,
      'createdAt': instance.createdAt.toIso8601String(),
      'retryCount': instance.retryCount,
      'isProcessing': instance.isProcessing,
    };
