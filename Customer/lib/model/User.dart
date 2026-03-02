import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/AddressModel.dart';

class User with ChangeNotifier {
  String email;
  String firstName;
  String lastName;
  UserSettings settings;
  String phoneNumber;
  bool active;
  Timestamp? lastOnlineTimestamp;
  Timestamp? createdAt;
  Timestamp? updatedAt;
  String userID;
  String profilePictureURL;
  String appIdentifier;
  String fcmToken;
  UserLocation location;
  List<AddressModel>? shippingAddress = [];
  String role;
  String carName;
  String carNumber;
  String carPictureURL;
  List<dynamic>? inProgressOrderID;
  String? vendorID;
  num? rotation;
  dynamic walletAmount;

  // Referral-related fields
  String? referralCode; // Unique referral code for this user
  String? referredBy; // User ID who referred this user (write-once)
  bool hasCompletedFirstOrder; // Flag to track first order completion

  // Backend-managed referral flags (client should only read these)
  bool isReferralPath; // Whether user is on referral path (backend computed)
  bool
      isPromoDisabled; // Whether promo is disabled due to referral (backend computed)
  String? referralRewardAmount; // Reward amount from backend settings

  // First-order coupon eligibility
  bool hasOrderedBefore; // Flag to determine first-order coupon eligibility

  // Referral wallet amount (separate from regular wallet)
  double referralWalletAmount; // Referral credits usable only for orders

  User(
      {this.email = '',
      this.userID = '',
      this.profilePictureURL = '',
      this.firstName = '',
      this.phoneNumber = '',
      this.lastName = '',
      this.active = true,
      this.walletAmount = 0.0,
      this.referralCode,
      this.referredBy,
      this.hasCompletedFirstOrder = false,
      this.isReferralPath = false,
      this.isPromoDisabled = false,
      this.referralRewardAmount,
      this.hasOrderedBefore = false,
      this.referralWalletAmount = 0.0,
      this.rotation,
      this.vendorID,
      lastOnlineTimestamp,
      settings,
      this.fcmToken = '',
      location,
      this.shippingAddress,
      this.role = USER_ROLE_DRIVER,
      this.carName = '',
      this.carNumber = '',
      this.carPictureURL = '',
      this.createdAt,
      this.updatedAt,
      this.inProgressOrderID})
      : this.lastOnlineTimestamp = lastOnlineTimestamp ?? Timestamp.now(),
        this.settings = settings ?? UserSettings(),
        this.appIdentifier =
            'Flutter Uber Eats Consumer ${Platform.operatingSystem}',
        this.location = location ?? UserLocation();

  String fullName() {
    return ((email.isEmpty) && (phoneNumber.isEmpty))
        ? 'Login to Manage'
        : '$firstName $lastName';
  }

  /// Sets the referredBy field (write-once operation)
  /// Returns true if successfully set, false if already set
  bool setReferredBy(String referrerId) {
    if (this.referredBy == null || this.referredBy!.isEmpty) {
      this.referredBy = referrerId;
      return true;
    }
    return false; // Already set, cannot change
  }

  /// Marks the first order as completed
  void markFirstOrderCompleted() {
    this.hasCompletedFirstOrder = true;
  }

  factory User.fromJson(Map<String, dynamic> parsedJson) {
    List<AddressModel>? shippingAddressList = [];
    if (parsedJson['shippingAddress'] != null) {
      shippingAddressList = <AddressModel>[];
      parsedJson['shippingAddress'].forEach((v) {
        shippingAddressList!.add(AddressModel.fromJson(v));
      });
    }

    final dynamic rawRole = parsedJson['role'];
    final String roleValue =
        (rawRole ?? USER_ROLE_CUSTOMER).toString().trim();

    return User(
        walletAmount: parsedJson['wallet_amount'] ?? 0.0,
        email: parsedJson['email'] ?? '',
        firstName: parsedJson['firstName'] ?? '',
        lastName: parsedJson['lastName'] ?? '',
        active: parsedJson['active'] is bool ? parsedJson['active'] : true,
        lastOnlineTimestamp: parsedJson['lastOnlineTimestamp'],
        settings: parsedJson.containsKey('settings')
            ? UserSettings.fromJson(parsedJson['settings'])
            : UserSettings(),
        phoneNumber: parsedJson['phoneNumber'] ?? '',
        userID: parsedJson['id'] ?? parsedJson['userID'] ?? '',
        profilePictureURL: parsedJson['profilePictureURL'] ?? '',
        fcmToken: parsedJson['fcmToken'] ?? '',
        location: parsedJson.containsKey('location')
            ? UserLocation.fromJson(parsedJson['location'])
            : UserLocation(),
        shippingAddress: shippingAddressList,
        role: roleValue.isEmpty ? USER_ROLE_CUSTOMER : roleValue,
        carName: parsedJson['carName'] ?? '',
        carNumber: parsedJson['carNumber'] ?? '',
        carPictureURL: parsedJson['carPictureURL'] ?? '',
        inProgressOrderID: parsedJson['inProgressOrderID'] ?? [],
        rotation: parsedJson['rotation'] ?? 0.0,
        createdAt: parsedJson['createdAt'],
        updatedAt: parsedJson['updatedAt'],
        vendorID: parsedJson['vendorID'] ?? '',
        referralCode: parsedJson['referralCode'],
        referredBy: parsedJson['referredBy'],
        hasCompletedFirstOrder: parsedJson['hasCompletedFirstOrder'] is bool
            ? parsedJson['hasCompletedFirstOrder']
            : false,
        isReferralPath: parsedJson['isReferralPath'] is bool
            ? parsedJson['isReferralPath']
            : false,
        isPromoDisabled: parsedJson['isPromoDisabled'] is bool
            ? parsedJson['isPromoDisabled']
            : false,
        referralRewardAmount: parsedJson['referralRewardAmount'],
        hasOrderedBefore: parsedJson['hasOrderedBefore'] is bool
            ? parsedJson['hasOrderedBefore']
            : false,
        referralWalletAmount: parsedJson['referralWalletAmount'] != null
            ? (parsedJson['referralWalletAmount'] is num
                ? (parsedJson['referralWalletAmount'] as num).toDouble()
                : double.tryParse(
                        parsedJson['referralWalletAmount'].toString()) ??
                    0.0)
            : 0.0);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'wallet_amount': this.walletAmount,
      'email': this.email,
      'firstName': this.firstName,
      'lastName': this.lastName,
      'settings': this.settings.toJson(),
      'phoneNumber': this.phoneNumber,
      'id': this.userID,
      'active': this.active,
      'lastOnlineTimestamp': this.lastOnlineTimestamp,
      'profilePictureURL': this.profilePictureURL,
      'appIdentifier': this.appIdentifier,
      'fcmToken': this.fcmToken,
      'location': this.location.toJson(),
      'role': this.role,
      'createdAt': this.createdAt,
      'updatedAt': this.updatedAt,
      'shippingAddress': shippingAddress != null
          ? shippingAddress!.map((v) => v.toJson()).toList()
          : null,
      // Referral-related fields
      'referralCode': this.referralCode,
      'referredBy': this.referredBy,
      'hasCompletedFirstOrder': this.hasCompletedFirstOrder,
      'isReferralPath': this.isReferralPath,
      'isPromoDisabled': this.isPromoDisabled,
      'referralRewardAmount': this.referralRewardAmount,
      'hasOrderedBefore': this.hasOrderedBefore,
      'referralWalletAmount': this.referralWalletAmount,
    };
    if (this.role == USER_ROLE_DRIVER) {
      json.addAll({
        'role': this.role,
        'carName': this.carName,
        'carNumber': this.carNumber,
        'carPictureURL': this.carPictureURL,
        'rotation': rotation,
        'inProgressOrderID': inProgressOrderID,
      });
    }
    if (this.role == USER_ROLE_VENDOR) {
      json.addAll({
        'vendorID': this.vendorID,
      });
    }
    return json;
  }
}

class UserSettings {
  bool pushNewMessages;

  bool orderUpdates;

  bool newArrivals;

  bool promotions;

  bool ashRecommendations;

  bool ashReorderReminders;

  bool ashHungerReminders;

  bool ashCartReminders;

  bool autoRetryFailedOrders;
  bool allowAlternativeSuggestions;
  String? backupPaymentMethod;
  int maxRetryAttempts;
  List<String> preferredPaymentMethods;

  bool quietHoursEnabled;
  int quietHoursStart;
  int quietHoursEnd;

  String preferredLanguage;

  UserSettings({
    this.pushNewMessages = true,
    this.orderUpdates = true,
    this.newArrivals = true,
    this.promotions = true,
    this.ashRecommendations = true,
    this.ashReorderReminders = true,
    this.ashHungerReminders = true,
    this.ashCartReminders = true,
    this.autoRetryFailedOrders = false,
    this.allowAlternativeSuggestions = true,
    this.backupPaymentMethod,
    this.maxRetryAttempts = 2,
    this.preferredPaymentMethods = const [],
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
    this.preferredLanguage = 'en',
  });

  factory UserSettings.fromJson(Map<dynamic, dynamic> parsedJson) {
    return UserSettings(
      pushNewMessages: parsedJson['pushNewMessages'] is bool
          ? parsedJson['pushNewMessages']
          : true,
      orderUpdates: parsedJson['orderUpdates'] is bool
          ? parsedJson['orderUpdates']
          : true,
      newArrivals:
          parsedJson['newArrivals'] is bool ? parsedJson['newArrivals'] : true,
      promotions:
          parsedJson['promotions'] is bool ? parsedJson['promotions'] : true,
      ashRecommendations: parsedJson['ashRecommendations'] is bool
          ? parsedJson['ashRecommendations']
          : true,
      ashReorderReminders: parsedJson['ashReorderReminders'] is bool
          ? parsedJson['ashReorderReminders']
          : true,
      ashHungerReminders: parsedJson['ashHungerReminders'] is bool
          ? parsedJson['ashHungerReminders']
          : true,
      ashCartReminders: parsedJson['ashCartReminders'] is bool
          ? parsedJson['ashCartReminders']
          : true,
      autoRetryFailedOrders: parsedJson['autoRetryFailedOrders'] == true,
      allowAlternativeSuggestions:
          parsedJson['allowAlternativeSuggestions'] != false,
      backupPaymentMethod: parsedJson['backupPaymentMethod'] as String?,
      maxRetryAttempts: parsedJson['maxRetryAttempts'] is int
          ? parsedJson['maxRetryAttempts'] as int
          : 2,
      preferredPaymentMethods: parsedJson['preferredPaymentMethods'] is List
          ? List<String>.from(parsedJson['preferredPaymentMethods'] as List)
          : <String>[],
      quietHoursEnabled: parsedJson['quietHoursEnabled'] is bool
          ? parsedJson['quietHoursEnabled']
          : false,
      quietHoursStart: parsedJson['quietHoursStart'] is int
          ? parsedJson['quietHoursStart']
          : 22,
      quietHoursEnd: parsedJson['quietHoursEnd'] is int
          ? parsedJson['quietHoursEnd']
          : 8,
      preferredLanguage: (parsedJson['preferredLanguage'] as String?) ?? 'en',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushNewMessages': this.pushNewMessages,
      'orderUpdates': this.orderUpdates,
      'newArrivals': this.newArrivals,
      'promotions': this.promotions,
      'ashRecommendations': this.ashRecommendations,
      'ashReorderReminders': this.ashReorderReminders,
      'ashHungerReminders': this.ashHungerReminders,
      'ashCartReminders': this.ashCartReminders,
      'autoRetryFailedOrders': this.autoRetryFailedOrders,
      'allowAlternativeSuggestions': this.allowAlternativeSuggestions,
      'backupPaymentMethod': this.backupPaymentMethod,
      'maxRetryAttempts': this.maxRetryAttempts,
      'preferredPaymentMethods': this.preferredPaymentMethods,
      'quietHoursEnabled': this.quietHoursEnabled,
      'quietHoursStart': this.quietHoursStart,
      'quietHoursEnd': this.quietHoursEnd,
      'preferredLanguage': this.preferredLanguage,
    };
  }
}

class UserLocation {
  double latitude;
  double longitude;

  UserLocation({this.latitude = 0.01, this.longitude = 0.01});

  factory UserLocation.fromJson(Map<dynamic, dynamic> parsedJson) {
    return UserLocation(
      latitude: parsedJson['latitude'] ?? 00.1,
      longitude: parsedJson['longitude'] ?? 00.1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
