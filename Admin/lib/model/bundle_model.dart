import 'package:cloud_firestore/cloud_firestore.dart';

class BundleItemModel {
  final String productId;
  final String productName;
  final int quantity;
  final double? priceAtCreation;

  BundleItemModel({
    required this.productId,
    required this.productName,
    this.quantity = 1,
    this.priceAtCreation,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      if (priceAtCreation != null) 'priceAtCreation': priceAtCreation,
    };
  }

  static BundleItemModel fromMap(Map<String, dynamic> map) {
    final q = map['quantity'];
    final qty = q is int
        ? q
        : (q is num ? q.toInt() : int.tryParse(q?.toString() ?? '1') ?? 1);
    final price = map['priceAtCreation'];
    return BundleItemModel(
      productId: (map['productId'] ?? '').toString(),
      productName: (map['productName'] ?? '').toString(),
      quantity: qty,
      priceAtCreation: price is num
          ? price.toDouble()
          : (price != null ? double.tryParse(price.toString()) : null),
    );
  }
}

class BundleModel {
  final String bundleId;
  final String restaurantId;
  final String name;
  final String description;
  final String? imageUrl;
  final List<BundleItemModel> items;
  final double regularPrice;
  final double bundlePrice;
  final double savingsAmount;
  final double savingsPercentage;
  final String status; // 'active' | 'inactive' | 'deleted'
  final Timestamp? startDate;
  final Timestamp? endDate;
  final int? maxPurchasesPerCustomer;
  final int totalPurchasesCount;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String? createdBy;

  BundleModel({
    required this.bundleId,
    required this.restaurantId,
    required this.name,
    this.description = '',
    this.imageUrl,
    required this.items,
    required this.regularPrice,
    required this.bundlePrice,
    required this.savingsAmount,
    required this.savingsPercentage,
    this.status = 'active',
    this.startDate,
    this.endDate,
    this.maxPurchasesPerCustomer,
    this.totalPurchasesCount = 0,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    this.createdBy,
  })  : createdAt = createdAt ?? Timestamp.now(),
        updatedAt = updatedAt ?? Timestamp.now();

  Map<String, dynamic> toJson() {
    return {
      'bundleId': bundleId,
      'restaurantId': restaurantId,
      'name': name,
      'description': description,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      'items': items.map((e) => e.toMap()).toList(),
      'regularPrice': regularPrice,
      'bundlePrice': bundlePrice,
      'savingsAmount': savingsAmount,
      'savingsPercentage': savingsPercentage,
      'status': status,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (maxPurchasesPerCustomer != null)
        'maxPurchasesPerCustomer': maxPurchasesPerCustomer,
      'totalPurchasesCount': totalPurchasesCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
    };
  }

  static BundleModel fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final itemsList = data['items'] as List<dynamic>? ?? [];
    final items = itemsList
        .map((e) => BundleItemModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

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

    final createdAt = readTimestamp(data['createdAt']) ?? Timestamp.now();
    final updatedAt = readTimestamp(data['updatedAt']) ?? Timestamp.now();

    int? maxPurchases;
    if (data['maxPurchasesPerCustomer'] != null) {
      final m = data['maxPurchasesPerCustomer'];
      maxPurchases = m is int ? m : int.tryParse(m.toString());
    }

    int totalCount = 0;
    if (data['totalPurchasesCount'] != null) {
      final t = data['totalPurchasesCount'];
      totalCount = t is int ? t : (int.tryParse(t.toString()) ?? 0);
    }

    return BundleModel(
      bundleId: doc.id,
      restaurantId: (data['restaurantId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      imageUrl: data['imageUrl']?.toString(),
      items: items,
      regularPrice: readDouble(data['regularPrice']),
      bundlePrice: readDouble(data['bundlePrice']),
      savingsAmount: readDouble(data['savingsAmount']),
      savingsPercentage: readDouble(data['savingsPercentage']),
      status: (data['status'] ?? 'active').toString(),
      startDate: readTimestamp(data['startDate']),
      endDate: readTimestamp(data['endDate']),
      maxPurchasesPerCustomer: maxPurchases,
      totalPurchasesCount: totalCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: data['createdBy']?.toString(),
    );
  }
}
