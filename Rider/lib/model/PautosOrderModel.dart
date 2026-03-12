import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/AddressModel.dart';
import 'package:foodie_driver/model/User.dart';

class PautosOrderModel {
  String id;
  String authorID;
  String shoppingList;
  double maxBudget;
  String? preferredStore;
  AddressModel address;
  String status;
  Timestamp createdAt;
  String? driverID;
  String? driverName;
  double? actualItemCost;
  String? receiptPhotoUrl;
  List<int>? itemsFound;
  double? deliveryFee;
  double? serviceFee;
  double? totalAmount;
  String? paymentMethod;
  Timestamp? completedAt;

  PautosOrderModel({
    required this.id,
    required this.authorID,
    required this.shoppingList,
    required this.maxBudget,
    this.preferredStore,
    required this.address,
    required this.status,
    required this.createdAt,
    this.driverID,
    this.driverName,
    this.actualItemCost,
    this.receiptPhotoUrl,
    this.itemsFound,
    this.deliveryFee,
    this.serviceFee,
    this.totalAmount,
    this.paymentMethod,
    this.completedAt,
  });

  factory PautosOrderModel.fromJson(Map<String, dynamic> json) {
    final address = json['address'] != null
        ? AddressModel.fromJson(
            Map<String, dynamic>.from(json['address'] as Map))
        : AddressModel(location: UserLocation(latitude: 0, longitude: 0));
    return PautosOrderModel(
      id: json['id']?.toString() ?? '',
      authorID: json['authorID']?.toString() ?? '',
      shoppingList: json['shoppingList']?.toString() ?? '',
      maxBudget: (json['maxBudget'] is num
              ? (json['maxBudget'] as num).toDouble()
              : double.tryParse(json['maxBudget']?.toString() ?? '0') ?? 0.0),
      preferredStore: json['preferredStore']?.toString(),
      address: address,
      status: json['status']?.toString() ?? 'Request Posted',
      createdAt: json['createdAt'] is Timestamp
          ? json['createdAt'] as Timestamp
          : Timestamp.now(),
      driverID: json['driverID']?.toString(),
      driverName: json['driverName']?.toString(),
      actualItemCost: json['actualItemCost'] != null
          ? (json['actualItemCost'] as num).toDouble()
          : null,
      receiptPhotoUrl: json['receiptPhotoUrl']?.toString(),
      itemsFound: json['itemsFound'] is List
          ? (json['itemsFound'] as List)
              .map((e) => (e as num).toInt())
              .toList()
          : null,
      deliveryFee: json['deliveryFee'] != null
          ? (json['deliveryFee'] as num).toDouble()
          : null,
      serviceFee: json['serviceFee'] != null
          ? (json['serviceFee'] as num).toDouble()
          : null,
      totalAmount: json['totalAmount'] != null
          ? (json['totalAmount'] as num).toDouble()
          : null,
      paymentMethod: json['paymentMethod']?.toString(),
      completedAt: json['completedAt'] is Timestamp
          ? json['completedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorID': authorID,
      'shoppingList': shoppingList,
      'maxBudget': maxBudget,
      'preferredStore': preferredStore,
      'address': address.toJson(),
      'status': status,
      'createdAt': createdAt,
      if (driverID != null) 'driverID': driverID,
      if (driverName != null) 'driverName': driverName,
      if (actualItemCost != null) 'actualItemCost': actualItemCost,
      if (receiptPhotoUrl != null) 'receiptPhotoUrl': receiptPhotoUrl,
      if (itemsFound != null && itemsFound!.isNotEmpty) 'itemsFound': itemsFound,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (serviceFee != null) 'serviceFee': serviceFee,
      if (totalAmount != null) 'totalAmount': totalAmount,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (completedAt != null) 'completedAt': completedAt,
    };
  }
}
