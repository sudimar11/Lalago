import 'package:cloud_firestore/cloud_firestore.dart';

class AddonPromoModel {
  final String addonPromoId;
  final String restaurantId;
  final String triggerType;
  final String triggerProductId;
  final String triggerProductName;
  final String addonProductId;
  final String addonProductName;
  final String addonName;
  final String addonDescription;
  final double regularPrice;
  final double addonPrice;
  final int maxQuantityPerOrder;
  final String? imageUrl;
  final String status;

  AddonPromoModel({
    required this.addonPromoId,
    required this.restaurantId,
    this.triggerType = 'product',
    required this.triggerProductId,
    required this.triggerProductName,
    required this.addonProductId,
    required this.addonProductName,
    required this.addonName,
    this.addonDescription = '',
    required this.regularPrice,
    required this.addonPrice,
    required this.maxQuantityPerOrder,
    this.imageUrl,
    this.status = 'active',
  });

  static AddonPromoModel fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    double readDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int readInt(dynamic v) {
      if (v == null) return 1;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 1;
    }

    return AddonPromoModel(
      addonPromoId: doc.id,
      restaurantId: (data['restaurantId'] ?? '').toString(),
      triggerType: (data['triggerType'] ?? 'product').toString(),
      triggerProductId: (data['triggerProductId'] ?? '').toString(),
      triggerProductName: (data['triggerProductName'] ?? '').toString(),
      addonProductId: (data['addonProductId'] ?? '').toString(),
      addonProductName: (data['addonProductName'] ?? '').toString(),
      addonName: (data['addonName'] ?? '').toString(),
      addonDescription: (data['addonDescription'] ?? '').toString(),
      regularPrice: readDouble(data['regularPrice']),
      addonPrice: readDouble(data['addonPrice']),
      maxQuantityPerOrder: readInt(data['maxQuantityPerOrder']),
      imageUrl: data['imageUrl']?.toString(),
      status: (data['status'] ?? 'active').toString(),
    );
  }

  bool get isActive => status == 'active';
}
