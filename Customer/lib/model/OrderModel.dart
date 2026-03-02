import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/localDatabase.dart';

import 'TaxModel.dart';

class OrderModel {
  String authorID, paymentMethod;

  User author;

  User? driver;

  String? driverID;

  List<CartProduct> products;

  Timestamp createdAt;

  String vendorID;

  VendorModel vendor;
  String status;
  AddressModel? address;
  String id;
  num? discount;
  String? couponCode;
  String? couponId, notes;
  String? tipValue;
  String? adminCommission;
  String? adminCommissionType;
  List<TaxModel>? taxModel;
  String? deliveryCharge;
  Map<String, dynamic>? specialDiscount;
  String? estimatedTimeToPrepare;
  Timestamp? scheduleTime;

  // Referral system fields
  bool isReferralPath; // Single source of truth for referral orders
  String? referralAuditNote; // Audit note explaining referral vs promo decision
  String? rejectionReason; // Reason provided by restaurant for order rejection

  // Enhanced failure tracking
  String? failureType;
  String? failureReason;
  Map<String, dynamic>? failureDetails;
  bool? recoveryAttempted;
  bool? recoverySuccessful;
  String? recoveredOrderId;
  List<Map<String, dynamic>>? alternativeSuggestions;

  // First-order coupon tracking
  String? appliedCouponId; // Coupon ID if first-order coupon was applied
  double? couponDiscountAmount; // Discount amount from first-order coupon

  // Single-discount policy tracking
  String? appliedDiscountType; // Type of discount applied ("first_order", "happy_hour", "none")
  double? appliedDiscountAmount; // Amount of promo discount applied

  // Manual coupon fields
  String? manualCouponCode;
  String? manualCouponId;
  double? manualCouponDiscountAmount;
  String? manualCouponImage;

  // Referral wallet usage
  double? referralWalletAmountUsed; // Amount of referral wallet used in this order

  double _tryParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  double _itemsTotal() {
    double total = 0.0;
    for (final p in products) {
      final price = _tryParseDouble(p.price);
      final extrasPrice = _tryParseDouble(p.extras_price);
      total += p.quantity * (price + extrasPrice);
    }
    return total;
  }

  double get totalAmount {
    final itemsTotal = _itemsTotal();
    final discountAmount = _tryParseDouble(discount);
    final specialDiscountAmount =
        _tryParseDouble(specialDiscount?['special_discount']);
    final deliveryAmount = _tryParseDouble(deliveryCharge);
    final tipAmount = _tryParseDouble(tipValue);

    final total = itemsTotal +
        deliveryAmount +
        tipAmount -
        discountAmount -
        specialDiscountAmount;
    return total < 0 ? 0.0 : total;
  }

  OrderModel(
      {this.address,
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
      this.adminCommissionType,
      this.deliveryCharge,
      this.specialDiscount,
      this.estimatedTimeToPrepare,
      this.vendorID = '',
      this.scheduleTime,
      this.taxModel,
      this.isReferralPath = false,
      this.referralAuditNote,
      this.rejectionReason,
      this.failureType,
      this.failureReason,
      this.failureDetails,
      this.recoveryAttempted,
      this.recoverySuccessful,
      this.recoveredOrderId,
      this.alternativeSuggestions,
      this.appliedCouponId,
      this.couponDiscountAmount,
      this.appliedDiscountType,
      this.appliedDiscountAmount,
      this.manualCouponCode,
      this.manualCouponId,
      this.manualCouponDiscountAmount,
      this.manualCouponImage,
      this.referralWalletAmountUsed})
      : this.author = author ?? User(),
        this.createdAt = createdAt ?? Timestamp.now(),
        this.vendor = vendor ?? VendorModel();

  /// Normalizes a Firestore product map so CartProduct.fromJson accepts it
  /// (handles int/null for String fields).
  static Map<String, dynamic> _normalizeProductJson(Map<String, dynamic> p) {
    final v = (Object? x) => x?.toString() ?? '';
    final vOpt = (Object? x) => x == null ? null : x.toString();
    final q = p['quantity'];
    final qInt = q is int
        ? q
        : (q is num
            ? q.toInt()
            : int.tryParse(q?.toString() ?? '0') ?? 0);
    return <String, dynamic>{
      'id': v(p['id']),
      'category_id': v(p['category_id']),
      'name': v(p['name']),
      'photo': v(p['photo']),
      'price': v(p['price']),
      'discountPrice': vOpt(p['discountPrice']),
      'vendorID': v(p['vendorID']),
      'quantity': qInt,
      'extras_price': vOpt(p['extras_price']),
      'extras': p['extras'],
      if (p['variant_info'] != null) 'variant_info': p['variant_info'],
      'bundleId': vOpt(p['bundleId']),
      'bundleName': vOpt(p['bundleName']),
      'addonPromoId': vOpt(p['addonPromoId']),
      'addonPromoName': vOpt(p['addonPromoName']),
    };
  }

  factory OrderModel.fromJson(Map<String, dynamic> parsedJson) {
    List<CartProduct> products = <CartProduct>[];
    if (parsedJson.containsKey('products') &&
        parsedJson['products'] is List<dynamic>) {
      for (final e in parsedJson['products'] as List<dynamic>) {
        if (e is! Map<String, dynamic>) continue;
        try {
          products.add(CartProduct.fromJson(_normalizeProductJson(e)));
        } catch (_) {
          // Skip product if parse fails (e.g. variant_info or unknown field).
        }
      }
    }

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
          ? double.tryParse(parsedJson['discount'].toString()) ?? 0.0
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
      driver: parsedJson['driver'] != null
          ? User.fromJson(parsedJson['driver'])
          : null,
      driverID:
          parsedJson.containsKey('driverID') ? parsedJson['driverID'] : null,
      adminCommission: parsedJson["adminCommission"] != null
          ? parsedJson["adminCommission"].toString()
          : "",
      adminCommissionType: parsedJson["adminCommissionType"] != null
          ? parsedJson["adminCommissionType"].toString()
          : "",
      tipValue: parsedJson["tip_amount"] != null
          ? parsedJson["tip_amount"].toString()
          : "",
      specialDiscount: parsedJson["specialDiscount"] ?? {},

      //extras: parsedJson["extras"]!=null?parsedJson["extras"]:[],
      // extra_size: parsedJson["extras_price"]!=null?parsedJson["extras_price"]:"",
      deliveryCharge: parsedJson["deliveryCharge"] != null
          ? parsedJson["deliveryCharge"].toString()
          : "0.0",
      paymentMethod: parsedJson["payment_method"] ?? '',
      estimatedTimeToPrepare: parsedJson["estimatedTimeToPrepare"] != null
          ? parsedJson["estimatedTimeToPrepare"].toString()
          : '',
      scheduleTime: parsedJson["scheduleTime"],
      taxModel: taxList,

      // Referral system fields
      isReferralPath: parsedJson['isReferralPath'] is bool
          ? parsedJson['isReferralPath']
          : false,
      referralAuditNote: parsedJson['referralAuditNote'],
      rejectionReason: parsedJson['rejectionReason'],
      failureType: parsedJson['failureType'],
      failureReason: parsedJson['failureReason'],
      failureDetails: parsedJson['failureDetails'] != null
          ? Map<String, dynamic>.from(parsedJson['failureDetails'] as Map)
          : null,
      recoveryAttempted: parsedJson['recoveryAttempted'] as bool?,
      recoverySuccessful: parsedJson['recoverySuccessful'] as bool?,
      recoveredOrderId: parsedJson['recoveredOrderId'],
      alternativeSuggestions: parsedJson['alternativeSuggestions'] != null
          ? (parsedJson['alternativeSuggestions'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : null,

      // First-order coupon tracking
      appliedCouponId: parsedJson['appliedCouponId'],
      couponDiscountAmount: parsedJson['couponDiscountAmount'] != null
          ? (parsedJson['couponDiscountAmount'] is num
              ? (parsedJson['couponDiscountAmount'] as num).toDouble()
              : double.tryParse(
                      parsedJson['couponDiscountAmount'].toString()) ??
                  0.0)
          : null,

      // Single-discount policy tracking
      appliedDiscountType: parsedJson['appliedDiscountType'],
      appliedDiscountAmount: parsedJson['appliedDiscountAmount'] != null
          ? (parsedJson['appliedDiscountAmount'] is num
              ? (parsedJson['appliedDiscountAmount'] as num).toDouble()
              : double.tryParse(
                      parsedJson['appliedDiscountAmount'].toString()) ??
                  0.0)
          : null,

      // Manual coupon fields
      manualCouponCode: parsedJson['manualCouponCode'],
      manualCouponId: parsedJson['manualCouponId'],
      manualCouponDiscountAmount: parsedJson['manualCouponDiscountAmount'] != null
          ? (parsedJson['manualCouponDiscountAmount'] is num
              ? (parsedJson['manualCouponDiscountAmount'] as num).toDouble()
              : double.tryParse(
                      parsedJson['manualCouponDiscountAmount'].toString()) ??
                  0.0)
          : null,
      manualCouponImage: parsedJson['manualCouponImage'],
      referralWalletAmountUsed: parsedJson['referralWalletAmountUsed'] != null
          ? (parsedJson['referralWalletAmountUsed'] is num
              ? (parsedJson['referralWalletAmountUsed'] as num).toDouble()
              : double.tryParse(
                      parsedJson['referralWalletAmountUsed'].toString()) ??
                  0.0)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address == null ? null : this.address!.toJson(),
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
      "deliveryCharge": this.deliveryCharge,
      'totalAmount': totalAmount,
      'total': totalAmount,
      "specialDiscount": this.specialDiscount,
      "estimatedTimeToPrepare": this.estimatedTimeToPrepare,
      "scheduleTime": this.scheduleTime,

      // Referral system fields
      "isReferralPath": this.isReferralPath,
      "referralAuditNote": this.referralAuditNote,
      "rejectionReason": this.rejectionReason,
      "failureType": this.failureType,
      "failureReason": this.failureReason,
      "failureDetails": this.failureDetails,
      "recoveryAttempted": this.recoveryAttempted,
      "recoverySuccessful": this.recoverySuccessful,
      "recoveredOrderId": this.recoveredOrderId,
      "alternativeSuggestions": this.alternativeSuggestions,

      // First-order coupon tracking
      "appliedCouponId": this.appliedCouponId,
      "couponDiscountAmount": this.couponDiscountAmount,

      // Single-discount policy tracking
      "appliedDiscountType": this.appliedDiscountType,
      "appliedDiscountAmount": this.appliedDiscountAmount,

      // Manual coupon fields
      "manualCouponCode": this.manualCouponCode,
      "manualCouponId": this.manualCouponId,
      "manualCouponDiscountAmount": this.manualCouponDiscountAmount,
      "manualCouponImage": this.manualCouponImage,
      "referralWalletAmountUsed": this.referralWalletAmountUsed,
    };
  }
}
