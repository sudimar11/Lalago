import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_restaurant/model/AddressModel.dart';
import 'package:foodie_restaurant/model/OrderProductModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';

import 'TaxModel.dart';

class OrderModel {
  int? preparationTime; // Add this field
  Timestamp? driverAcceptedAt; // When driver accepted the order
  int? preparationTimeInMinutes; // Preparation time in minutes

  String authorID, paymentMethod;

  User author;

  List<OrderProductModel> products;

  Timestamp createdAt;

  String vendorID;
  final String? driverID;
  VendorModel vendor;
  String status;
  AddressModel address;
  String id;
  num? discount;
  String? couponCode;
  String? couponId, notes;
  String? tipValue;
  String? adminCommission;
  String? adminCommissionType;
  final bool? takeAway;
  List<TaxModel>? taxModel;
  String? deliveryCharge;
  Map<String, dynamic>? specialDiscount;
  String? estimatedTimeToPrepare;
  Timestamp? scheduleTime;

  OrderModel(
      {address,
      author,
      this.driverID,
      this.authorID = '',
      this.paymentMethod = '',
      createdAt,
      this.id = '',
      this.products = const [],
      this.status = '',
      this.discount = 0,
      this.couponCode = '',
      this.couponId = '',
      this.notes = '',
      vendor,
      /*this.extras = const [], this.extra_size,*/ this.tipValue,
      this.adminCommission,
      this.takeAway = false,
      this.adminCommissionType,
      this.deliveryCharge,
      this.specialDiscount,
      this.estimatedTimeToPrepare,
      this.vendorID = '',
      this.scheduleTime,
      this.driverAcceptedAt,
      this.preparationTimeInMinutes,
      this.taxModel})
      : this.address = address ?? AddressModel(),
        this.author = author ?? User(),
        this.createdAt = createdAt ?? Timestamp.now(),
        this.vendor = vendor ?? VendorModel();

  factory OrderModel.fromJson(Map<String, dynamic> parsedJson) {
    List<OrderProductModel> products = parsedJson.containsKey('products')
        ? List<OrderProductModel>.from((parsedJson['products'] as List<dynamic>)
            .map((e) => OrderProductModel.fromJson(e))).toList()
        : [].cast<OrderProductModel>();

    List<TaxModel>? taxList;
    if (parsedJson['taxSetting'] != null) {
      taxList = <TaxModel>[];
      parsedJson['taxSetting'].forEach((v) {
        taxList!.add(TaxModel.fromJson(v));
      });
    }
    return OrderModel(
      address: parsedJson.containsKey('address')
          ? AddressModel.fromJson(parsedJson['address'])
          : AddressModel(),
      author: parsedJson.containsKey('author')
          ? User.fromJson(parsedJson['author'])
          : User(),
      authorID: parsedJson['authorID'] ?? '',
      createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
      id: parsedJson['id'] ?? '',
      products: products,
      status: parsedJson['status'] ?? '',
      discount: parsedJson['discount'] != null
          ? (parsedJson['discount'] is num
              ? parsedJson['discount']
              : double.tryParse(parsedJson['discount'].toString()) ?? 0.0)
          : 0.0,
      couponCode: parsedJson['couponCode'] ?? '',
      couponId: parsedJson['couponId'] ?? '',
      notes: (parsedJson["notes"] != null &&
              parsedJson["notes"].toString().isNotEmpty)
          ? parsedJson["notes"]
          : "",
      vendor: parsedJson.containsKey('vendor')
          ? VendorModel.fromJson(parsedJson['vendor'])
          : VendorModel(),
      vendorID: parsedJson['vendorID'] ?? '',
      adminCommission: parsedJson["adminCommission"] != null
          ? (parsedJson["adminCommission"] is num
              ? parsedJson["adminCommission"].toString()
              : parsedJson["adminCommission"].toString())
          : "",
      adminCommissionType: parsedJson["adminCommissionType"] != null
          ? (parsedJson["adminCommissionType"] is num
              ? parsedJson["adminCommissionType"].toString()
              : parsedJson["adminCommissionType"].toString())
          : "",
      tipValue: parsedJson["tip_amount"] != null
          ? (parsedJson["tip_amount"] is num
              ? parsedJson["tip_amount"].toString()
              : parsedJson["tip_amount"].toString())
          : "",
      specialDiscount: parsedJson["specialDiscount"] ?? {},

      takeAway: parsedJson["takeAway"] != null ? parsedJson["takeAway"] : false,
      //extras: parsedJson["extras"]!=null?parsedJson["extras"]:[],
      // extra_size: parsedJson["extras_price"]!=null?parsedJson["extras_price"]:"",
      deliveryCharge: parsedJson["deliveryCharge"],
      paymentMethod: parsedJson["payment_method"] ?? '',
      estimatedTimeToPrepare: parsedJson["estimatedTimeToPrepare"] ?? '',
      scheduleTime: parsedJson["scheduleTime"],
      driverID: parsedJson["driverID"],
      driverAcceptedAt: parsedJson["driverAcceptedAt"],
      preparationTimeInMinutes: parsedJson["preparationTimeInMinutes"],

      taxModel: taxList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': this.address.toJson(),
      'author': this.author.toJson(),
      'authorID': this.authorID,
      'createdAt': this.createdAt,
      'payment_method': this.paymentMethod,
      'id': this.id,
      'products': this.products.map((e) => e.toJson()).toList(),
      'status': this.status,
      'discount': this.discount,
      'couponCode': this.couponCode,
      'couponId': this.couponId,
      'notes': this.notes,
      'vendor': this.vendor.toJson(),
      'vendorID': this.vendorID,
      'adminCommission': this.adminCommission,
      'adminCommissionType': this.adminCommissionType,
      "tip_amount": this.tipValue,
      "taxSetting":
          taxModel != null ? taxModel!.map((v) => v.toJson()).toList() : null,
      "takeAway": this.takeAway,
      "deliveryCharge": this.deliveryCharge,
      "specialDiscount": this.specialDiscount,
      "estimatedTimeToPrepare": this.estimatedTimeToPrepare,
      "scheduleTime": this.scheduleTime,
      "driverID": this.driverID,
      "driverAcceptedAt": this.driverAcceptedAt,
      "preparationTimeInMinutes": this.preparationTimeInMinutes,
    };
  }

  double get totalAmount {
    double total = 0.0;
    for (var product in products) {
      total += product.quantity * double.parse(product.price);
      if (product.extrasPrice != null && product.extrasPrice!.isNotEmpty) {
        total += product.quantity * double.parse(product.extrasPrice!);
      }
    }
    return total;
  }
}
