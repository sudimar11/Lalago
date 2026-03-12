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
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final String? createdBy;

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
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'restaurantId': restaurantId,
      'triggerType': triggerType,
      'triggerProductId': triggerProductId,
      'triggerProductName': triggerProductName,
      'addonProductId': addonProductId,
      'addonProductName': addonProductName,
      'addonName': addonName,
      'addonDescription': addonDescription,
      'regularPrice': regularPrice,
      'addonPrice': addonPrice,
      'maxQuantityPerOrder': maxQuantityPerOrder,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      'status': status,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
    };
  }

  static AddonPromoModel fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    double readDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    Timestamp? readTimestamp(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v;
      if (v is Map && v['_seconds'] != null) {
        return Timestamp(
          (v['_seconds'] as num).toInt(),
          ((v['_nanoseconds'] as num?) ?? 0).toInt(),
        );
      }
      return null;
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
      createdAt: readTimestamp(data['createdAt']),
      updatedAt: readTimestamp(data['updatedAt']),
      createdBy: data['createdBy']?.toString(),
    );
  }
}
