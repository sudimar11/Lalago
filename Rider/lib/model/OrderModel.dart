import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/AddressModel.dart';
import 'package:foodie_driver/model/OrderProductModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/model/VendorModel.dart';

import 'TaxModel.dart';

class OrderModel {
  String authorID, paymentMethod;

  User author;

  User? driver;

  String? driverID;

  List<OrderProductModel> products;

  Timestamp createdAt;

  String vendorID;

  VendorModel vendor;

  String status;

  AddressModel address;

  String id;
  num? discount;
  String? couponCode;
  String? couponId, notes;

  // var extras = [];
  //String? extra_size;
  String? tipValue;
  String? adminCommission;
  String? adminCommissionType;
  final bool? takeAway;
  List<TaxModel>? taxModel;
  String? deliveryCharge;
  Map<String, dynamic>? specialDiscount;
  Timestamp? triggerDelevery;
  String? estimatedTimeToPrepare;
  Timestamp? scheduleTime;
  List<dynamic>? rejectedByDrivers = [];
  bool? restaurantArrivalConfirmed;
  bool? customerArrivalDetected;

  // Driver earnings fields (calculated when order is completed)
  String? originalDeliveryFee;
  double? driverEarnings;
  double? discountAmount;
  double? adminPromoCost;

  OrderModel(
      {address,
      author,
      this.driver,
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
      this.vendorID = '',
      this.triggerDelevery,
      this.estimatedTimeToPrepare,
      this.scheduleTime,
      this.rejectedByDrivers,
      this.taxModel,
      this.restaurantArrivalConfirmed,
      this.customerArrivalDetected,
      this.originalDeliveryFee,
      this.driverEarnings,
      this.discountAmount,
      this.adminPromoCost})
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
      discount: double.parse(parsedJson['discount'].toString()),
      couponCode: parsedJson['couponCode'] != null
          ? (parsedJson['couponCode'] is String
              ? parsedJson['couponCode']
              : parsedJson['couponCode'].toString())
          : '',
      couponId: parsedJson['couponId'] != null
          ? (parsedJson['couponId'] is String
              ? parsedJson['couponId']
              : parsedJson['couponId'].toString())
          : '',
      notes: (parsedJson["notes"] != null &&
              parsedJson["notes"].toString().isNotEmpty)
          ? parsedJson["notes"]
          : "",
      vendor: parsedJson.containsKey('vendor')
          ? VendorModel.fromJson(parsedJson['vendor'])
          : VendorModel(),
      vendorID: parsedJson['vendorID'] ?? '',
      driver: parsedJson.containsKey('driver')
          ? parsedJson['driver'] != null
              ? User.fromJson(parsedJson['driver'])
              : null
          : null,
      driverID: parsedJson.containsKey('driverID')
          ? (parsedJson['driverID'] is String
              ? parsedJson['driverID']
              : parsedJson['driverID']?.toString())
          : null,
      adminCommission: parsedJson["adminCommission"] != null
          ? (parsedJson["adminCommission"] is String
              ? parsedJson["adminCommission"]
              : parsedJson["adminCommission"].toString())
          : "",
      adminCommissionType: parsedJson["adminCommissionType"] != null
          ? (parsedJson["adminCommissionType"] is String
              ? parsedJson["adminCommissionType"]
              : parsedJson["adminCommissionType"].toString())
          : "",
      tipValue: parsedJson["tip_amount"] != null
          ? (parsedJson["tip_amount"] is String
              ? parsedJson["tip_amount"]
              : parsedJson["tip_amount"].toString())
          : "",
      specialDiscount: parsedJson["specialDiscount"] ?? {},

      takeAway: parsedJson["takeAway"] != null ? parsedJson["takeAway"] : false,
      //extras: parsedJson["extras"]!=null?parsedJson["extras"]:[],
      // extra_size: parsedJson["extras_price"]!=null?parsedJson["extras_price"]:"",
      deliveryCharge: parsedJson["deliveryCharge"] != null
          ? (parsedJson["deliveryCharge"] is String
              ? parsedJson["deliveryCharge"]
              : parsedJson["deliveryCharge"].toString())
          : null,
      paymentMethod: parsedJson["payment_method"] ?? '',
      estimatedTimeToPrepare: parsedJson["estimatedTimeToPrepare"] != null
          ? (parsedJson["estimatedTimeToPrepare"] is String
              ? parsedJson["estimatedTimeToPrepare"]
              : parsedJson["estimatedTimeToPrepare"].toString())
          : '',
      triggerDelevery: parsedJson["triggerDelevery"] ?? Timestamp.now(),
      scheduleTime: parsedJson["scheduleTime"],
      rejectedByDrivers: parsedJson["rejectedByDrivers"],
      taxModel: taxList,
      restaurantArrivalConfirmed: parsedJson["restaurantArrivalConfirmed"],
      customerArrivalDetected: parsedJson["customerArrivalDetected"],
      originalDeliveryFee: parsedJson["originalDeliveryFee"] != null
          ? (parsedJson["originalDeliveryFee"] is String
              ? parsedJson["originalDeliveryFee"]
              : parsedJson["originalDeliveryFee"].toString())
          : null,
      driverEarnings: parsedJson["driverEarnings"] != null
          ? (parsedJson["driverEarnings"] is num
              ? (parsedJson["driverEarnings"] as num).toDouble()
              : double.tryParse(
                      parsedJson["driverEarnings"].toString()) ??
                  0.0)
          : null,
      discountAmount: parsedJson["discountAmount"] != null
          ? (parsedJson["discountAmount"] is num
              ? (parsedJson["discountAmount"] as num).toDouble()
              : double.tryParse(
                      parsedJson["discountAmount"].toString()) ??
                  0.0)
          : null,
      adminPromoCost: parsedJson["adminPromoCost"] != null
          ? (parsedJson["adminPromoCost"] is num
              ? (parsedJson["adminPromoCost"] as num).toDouble()
              : double.tryParse(
                      parsedJson["adminPromoCost"].toString()) ??
                  0.0)
          : null,
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
      "triggerDelevery": this.triggerDelevery,
      "driverID": this.driverID,
      "driver": driver != null ? this.driver!.toJson() : null,
      "estimatedTimeToPrepare": this.estimatedTimeToPrepare,
      "scheduleTime": this.scheduleTime,
      "rejectedByDrivers": this.rejectedByDrivers,
      "restaurantArrivalConfirmed": this.restaurantArrivalConfirmed,
      "customerArrivalDetected": this.customerArrivalDetected,
      "originalDeliveryFee": this.originalDeliveryFee,
      "driverEarnings": this.driverEarnings,
      "discountAmount": this.discountAmount,
      "adminPromoCost": this.adminPromoCost,
    };
  }
}
