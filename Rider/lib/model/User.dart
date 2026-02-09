import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/AddressModel.dart';

class User with ChangeNotifier {
  String email;
  String firstName;
  String lastName;
  UserSettings settings;
  String phoneNumber;
  bool isActive;
  bool active;

  Timestamp? lastOnlineTimestamp;
  Timestamp? createdAt;
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
  List<dynamic>? orderRequestData;
  UserBankDetails userBankDetails;
  bool get isReallyActive => (active == true) || (isActive == true);
  bool multipleOrders;

  num walletAmount;
  num? rotation;
  String? checkInTime;
  String? checkOutTime;
  bool? checkedInToday;
  String? todayCheckInTime;
  String? todayCheckOutTime;
  bool? checkedOutToday;
  bool? isOnline;
  num? totalVouchers;
  num? todayVoucherEarned;
  double? driverPerformance;
  int? remainingExcuses;
  List<String>? excusedDays;
  bool? suspended;
  int? suspensionDate;
  String? lastActiveDate;
  String? lastAbsenceWarningDate;
  String? attendanceStatus;
  int? consecutiveAbsenceCount;
  String? lastAdminOverrideDate;
  String? lastAdminOverrideBy;
  String? lastAdminOverrideReason;
  String? lastAdminOverrideAction;

  User(
      {this.email = '',
      this.userID = '',
      this.profilePictureURL = '',
      this.firstName = '',
      this.phoneNumber = '',
      this.lastName = '',
      this.isActive = false,
      this.active = true,
      lastOnlineTimestamp,
      settings,
      this.fcmToken = '',
      location,
      this.shippingAddress,
      geoFireData,
      coordinates,
      this.rotation,
      this.role = USER_ROLE_DRIVER,
      this.carName = 'Uber Car',
      this.carNumber = 'No Plates',
      this.carPictureURL = DEFAULT_CAR_IMAGE,
      this.inProgressOrderID,
      this.walletAmount = 0.0,
      userBankDetails,
      this.createdAt,
      this.orderRequestData,
      this.multipleOrders = false,
      this.checkInTime,
      this.checkOutTime,
      this.checkedInToday,
      this.todayCheckInTime,
      this.todayCheckOutTime,
      this.checkedOutToday,
      this.isOnline,
      this.totalVouchers = 0.0,
      this.todayVoucherEarned = 0.0,
      this.driverPerformance = 100.0,
      this.remainingExcuses,
      this.excusedDays,
      this.suspended,
      this.suspensionDate,
      this.lastActiveDate,
      this.lastAbsenceWarningDate,
      this.attendanceStatus,
      this.consecutiveAbsenceCount,
      this.lastAdminOverrideDate,
      this.lastAdminOverrideBy,
      this.lastAdminOverrideReason,
      this.lastAdminOverrideAction})
      : this.lastOnlineTimestamp = lastOnlineTimestamp ?? Timestamp.now(),
        this.settings = settings ?? UserSettings(),
        this.appIdentifier =
            'Flutter Uber Eats Driver ${Platform.operatingSystem}',
        this.userBankDetails = userBankDetails ?? UserBankDetails(),
        this.location = location ?? UserLocation() {
    // Initialize isOnline based on checkedInToday if not provided
    if (this.isOnline == null) {
      this.isOnline = checkedInToday ?? false;
    }
  }

  String fullName() {
    return '$firstName $lastName';
  }

  factory User.fromJson(Map<String, dynamic> parsedJson) {
    // shippingAddress list
    List<AddressModel>? shippingAddressList;
    if (parsedJson['shippingAddress'] is Iterable) {
      shippingAddressList = [];
      for (var v in parsedJson['shippingAddress']) {
        try {
          if (v is Map<String, dynamic>) {
            shippingAddressList.add(AddressModel.fromJson(v));
          } else {
            // attempt to convert if it's dynamic
            shippingAddressList
                .add(AddressModel.fromJson(Map<String, dynamic>.from(v)));
          }
        } catch (_) {
          // skip malformed entry
        }
      }
    }

    // wallet amount normalized to double
    double walletAmt = 0.0;
    if (parsedJson['wallet_amount'] != null) {
      final wa = parsedJson['wallet_amount'];
      if (wa is num) {
        walletAmt = wa.toDouble();
      } else if (wa is String) {
        walletAmt = double.tryParse(wa) ?? 0.0;
      }
    }

    // rotation normalized to double
    double rotationVal = 0.0;
    if (parsedJson['rotation'] != null) {
      final r = parsedJson['rotation'];
      if (r is num) {
        rotationVal = r.toDouble();
      } else if (r is String) {
        rotationVal = double.tryParse(r) ?? 0.0;
      }
    }

    // geoFireData with fallback
    GeoFireData geoFireData;
    if (parsedJson.containsKey('g') && parsedJson['g'] is Map) {
      try {
        geoFireData =
            GeoFireData.fromJson(Map<String, dynamic>.from(parsedJson['g']));
      } catch (_) {
        geoFireData = GeoFireData(geohash: "", geoPoint: GeoPoint(0.0, 0.0));
      }
    } else {
      geoFireData = GeoFireData(geohash: "", geoPoint: GeoPoint(0.0, 0.0));
    }

    // userBankDetails
    UserBankDetails userBankDetails;
    if (parsedJson.containsKey('userBankDetails') &&
        parsedJson['userBankDetails'] is Map) {
      try {
        userBankDetails = UserBankDetails.fromJson(
            Map<String, dynamic>.from(parsedJson['userBankDetails']));
      } catch (_) {
        userBankDetails = UserBankDetails();
      }
    } else {
      userBankDetails = UserBankDetails();
    }

    // settings
    UserSettings settings;
    if (parsedJson.containsKey('settings') && parsedJson['settings'] is Map) {
      try {
        settings = UserSettings.fromJson(
            Map<String, dynamic>.from(parsedJson['settings']));
      } catch (_) {
        settings = UserSettings();
      }
    } else {
      settings = UserSettings();
    }

    // location
    UserLocation location;
    if (parsedJson.containsKey('location') && parsedJson['location'] is Map) {
      try {
        location = UserLocation.fromJson(
            Map<String, dynamic>.from(parsedJson['location']));
      } catch (_) {
        location = UserLocation();
      }
    } else {
      location = UserLocation();
    }

    return User(
      email: parsedJson['email'] ?? '',
      walletAmount: walletAmt,
      coordinates: parsedJson['coordinates'] ?? GeoPoint(0.0, 0.0),
      geoFireData: geoFireData,
      rotation: rotationVal,
      userBankDetails: userBankDetails,
      firstName: parsedJson['firstName'] ?? '',
      lastName: parsedJson['lastName'] ?? '',
      isActive: parsedJson['isActive'] ?? false,
      active: parsedJson['active'] ?? false,
      lastOnlineTimestamp: parsedJson['lastOnlineTimestamp'],
      settings: settings,
      phoneNumber: parsedJson['phoneNumber'] ?? '',
      userID: parsedJson['id'] ?? parsedJson['userID'] ?? '',
      profilePictureURL: parsedJson['profilePictureURL'] ?? '',
      fcmToken: parsedJson['fcmToken'] ?? '',
      location: location,
      shippingAddress: shippingAddressList,
      role: parsedJson['role'] ?? '',
      carName: parsedJson['carName'] ?? '',
      carNumber: parsedJson['carNumber'] ?? '',
      carPictureURL: parsedJson['carPictureURL'] ?? '',
      inProgressOrderID: parsedJson['inProgressOrderID'] ?? [],
      createdAt: parsedJson['createdAt'],
      orderRequestData: parsedJson['orderRequestData'] ?? [],
      multipleOrders: parsedJson['multipleOrders'] ?? false,
      checkInTime: parsedJson['checkInTime'],
      checkOutTime: parsedJson['checkOutTime'],
      checkedInToday: parsedJson['checkedInToday'],
      todayCheckInTime: parsedJson['todayCheckInTime'],
      todayCheckOutTime: parsedJson['todayCheckOutTime'],
      checkedOutToday: parsedJson['checkedOutToday'],
      isOnline: parsedJson['isOnline'],
      totalVouchers: parsedJson['totalVouchers'] ?? 0.0,
      todayVoucherEarned: parsedJson['todayVoucherEarned'] ?? 0.0,
      driverPerformance: parsedJson['driver_performance'] != null
          ? (parsedJson['driver_performance'] as num).toDouble()
          : 100.0,
      remainingExcuses: parsedJson['remainingExcuses'] != null
          ? (parsedJson['remainingExcuses'] as num).toInt()
          : null,
      excusedDays: parsedJson['excusedDays'] != null
          ? List<String>.from(parsedJson['excusedDays'])
          : null,
      suspended: parsedJson['suspended'] ?? false,
      suspensionDate: parsedJson['suspension_date'] != null
          ? (parsedJson['suspension_date'] as num).toInt()
          : null,
      lastActiveDate: parsedJson['lastActiveDate'],
      lastAbsenceWarningDate: parsedJson['lastAbsenceWarningDate'],
      attendanceStatus: parsedJson['attendanceStatus'],
      consecutiveAbsenceCount: parsedJson['consecutiveAbsenceCount'] != null
          ? (parsedJson['consecutiveAbsenceCount'] as num).toInt()
          : null,
      lastAdminOverrideDate: parsedJson['lastAdminOverrideDate'],
      lastAdminOverrideBy: parsedJson['lastAdminOverrideBy'],
      lastAdminOverrideReason: parsedJson['lastAdminOverrideReason'],
      lastAdminOverrideAction: parsedJson['lastAdminOverrideAction'],
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'email': this.email,
      'firstName': this.firstName,
      'lastName': this.lastName,
      'settings': this.settings.toJson(),
      'phoneNumber': this.phoneNumber,
      'wallet_amount': this.walletAmount,
      "userBankDetails": this.userBankDetails.toJson(),
      'id': this.userID,
      'isActive': this.isActive,
      'active': this.active,
      'lastOnlineTimestamp': this.lastOnlineTimestamp,
      'profilePictureURL': this.profilePictureURL,
      'appIdentifier': this.appIdentifier,
      'fcmToken': this.fcmToken,
      'location': this.location.toJson(),
      'shippingAddress': shippingAddress != null
          ? shippingAddress!.map((v) => v.toJson()).toList()
          : null,
      'role': this.role,
      'createdAt': this.createdAt,
      'multipleOrders': this.multipleOrders,
      'checkInTime': this.checkInTime,
      'checkOutTime': this.checkOutTime,
      'checkedInToday': this.checkedInToday,
      'todayCheckInTime': this.todayCheckInTime,
      'todayCheckOutTime': this.todayCheckOutTime,
      'checkedOutToday': this.checkedOutToday,
      'isOnline': this.isOnline,
      'totalVouchers': this.totalVouchers,
      'todayVoucherEarned': this.todayVoucherEarned,
      'driver_performance': this.driverPerformance,
      'remainingExcuses': this.remainingExcuses,
      'excusedDays': this.excusedDays,
      'suspended': this.suspended,
      'suspension_date': this.suspensionDate,
      'lastActiveDate': this.lastActiveDate,
      'lastAbsenceWarningDate': this.lastAbsenceWarningDate,
      'attendanceStatus': this.attendanceStatus,
      'consecutiveAbsenceCount': this.consecutiveAbsenceCount,
      'lastAdminOverrideDate': this.lastAdminOverrideDate,
      'lastAdminOverrideBy': this.lastAdminOverrideBy,
      'lastAdminOverrideReason': this.lastAdminOverrideReason,
      'lastAdminOverrideAction': this.lastAdminOverrideAction,
    };
    if (this.role == USER_ROLE_DRIVER) {
      json.addAll({
        'role': this.role,
        'carName': this.carName,
        'carNumber': this.carNumber,
        'carPictureURL': this.carPictureURL,
        'rotation': this.rotation,
        'orderRequestData': this.orderRequestData,
        'inProgressOrderID': this.inProgressOrderID,
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

  UserSettings(
      {this.pushNewMessages = true,
      this.orderUpdates = true,
      this.newArrivals = true,
      this.promotions = true});

  factory UserSettings.fromJson(Map<dynamic, dynamic> parsedJson) {
    return UserSettings(
      pushNewMessages: parsedJson['pushNewMessages'] ?? true,
      orderUpdates: parsedJson['orderUpdates'] ?? true,
      newArrivals: parsedJson['newArrivals'] ?? true,
      promotions: parsedJson['promotions'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushNewMessages': this.pushNewMessages,
      'orderUpdates': this.orderUpdates,
      'newArrivals': this.newArrivals,
      'promotions': this.promotions,
    };
  }
}

class GeoFireData {
  String? geohash;
  GeoPoint? geoPoint;

  GeoFireData({this.geohash, this.geoPoint});

  factory GeoFireData.fromJson(Map<dynamic, dynamic> parsedJson) {
    return GeoFireData(
      geohash: parsedJson['geohash'] ?? '',
      geoPoint: parsedJson['geopoint'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geohash': this.geohash,
      'geopoint': this.geoPoint,
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
      'latitude': this.latitude,
      'longitude': this.longitude,
    };
  }
}

class UserBankDetails {
  String bankName;
  String branchName;
  String holderName;
  String accountNumber;
  String otherDetails;

  UserBankDetails({
    this.bankName = '',
    this.otherDetails = '',
    this.branchName = '',
    this.accountNumber = '',
    this.holderName = '',
  });

  factory UserBankDetails.fromJson(Map<String, dynamic> parsedJson) {
    return UserBankDetails(
      bankName: parsedJson['bankName'] ?? '',
      branchName: parsedJson['branchName'] ?? '',
      holderName: parsedJson['holderName'] ?? '',
      accountNumber: parsedJson['accountNumber'] ?? '',
      otherDetails: parsedJson['otherDetails'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankName': this.bankName,
      'branchName': this.branchName,
      'holderName': this.holderName,
      'accountNumber': this.accountNumber,
      'otherDetails': this.otherDetails,
    };
  }
}
