import 'dart:convert';

import 'package:flutter/foundation.dart';
//import 'package:foodie_customer/model/FlutterWaveSettingDataModel.dart';
import 'package:foodie_customer/model/paytmSettingData.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model/paypalSettingData.dart';

class UserPreference {
  static late SharedPreferences _preferences;

  static Future init() async {
    _preferences = await SharedPreferences.getInstance();
  }

  static const _userId = "userId";
 
  static setUserId({required String userID}) {
    debugPrint(userID);
    _preferences.setString(_userId, userID);
  }

  static String walletKey = "walletKey";

  static setWalletData(bool isEnable) async {
    await _preferences.setBool(walletKey, isEnable);
  }

  static getWalletData() {
    final bool? isEnable = _preferences.getBool(walletKey);
    return isEnable;
  }

  static String paypalKey = "paypalKey";

  static setPayPalData(PaypalSettingData payPalSettingModel) async {
    final jsonData = jsonEncode(payPalSettingModel);
    await _preferences.setString(paypalKey, jsonData);
  }

  static getPayPalData() {
    final String? jsonData = _preferences.getString(paypalKey);
    if (jsonData != null)
      return PaypalSettingData.fromJson((jsonDecode(jsonData)));
  }



  //static String flutterWaveStack = "flutterWaveStack";

  //static setFlutterWaveData(FlutterWaveSettingData flutterWaveSettingData) async {
  //  debugPrint(flutterWaveSettingData.toString());
  //  final jsonData = jsonEncode(flutterWaveSettingData);
  //  await _preferences.setString(flutterWaveStack, jsonData);
  //}

  //static Future<FlutterWaveSettingData> getFlutterWaveData() async {
  //  final String? jsonData = _preferences.getString(flutterWaveStack);
  //  final flutterWaveData = jsonDecode(jsonData!);
  //  return FlutterWaveSettingData.fromJson(flutterWaveData);
  //}

  static String _paytmKey = "paytmKey";

  static setPaytmData(PaytmSettingData paytmSettingModel) async {
    final jsonData = jsonEncode(paytmSettingModel);
    await _preferences.setString(_paytmKey, jsonData);
  }

  static getPaytmData() async {
    final String? jsonData = _preferences.getString(_paytmKey);
    final paytmData = jsonDecode(jsonData!);
    return PaytmSettingData.fromJson(paytmData);
  }

  static const _orderId = "orderId";

  static setOrderId({required String orderId}) {
    _preferences.setString(_orderId, orderId);
  }

  static getOrderId() {
    final String? orderId = _preferences.getString(_orderId);
    return orderId != null ? orderId : "";
  }

  static const _paymentId = "paymentId";

  static setPaymentId({required String paymentId}) {
    _preferences.setString(_paymentId, paymentId);
  }

  static getPaymentId() {
    final String? paymentId = _preferences.getString(_paymentId);
    return paymentId != null ? paymentId : "";
  }

  // Rejected banner view tracking
  static const String _rejectedBannersViewedKey = "rejected_banners_viewed";

  /// Mark a rejected order banner as viewed for a specific user and order
  static Future<void> markRejectedBannerAsViewed(
      String userId, String orderId) async {
    if (userId.isEmpty || orderId.isEmpty) return;

    try {
      final String? existingJson = _preferences.getString(_rejectedBannersViewedKey);
      Map<String, dynamic> viewedMap = {};

      if (existingJson != null && existingJson.isNotEmpty) {
        viewedMap = jsonDecode(existingJson) as Map<String, dynamic>;
      }

      // Get or create list for this user
      List<dynamic> userOrderIds = viewedMap[userId] as List<dynamic>? ?? [];

      // Add order ID if not already present
      if (!userOrderIds.contains(orderId)) {
        userOrderIds.add(orderId);
        viewedMap[userId] = userOrderIds;
        await _preferences.setString(
            _rejectedBannersViewedKey, jsonEncode(viewedMap));
      }
    } catch (e) {
      debugPrint('Error marking rejected banner as viewed: $e');
    }
  }

  /// Check if a rejected order banner has been viewed for a specific user and order
  static bool isRejectedBannerViewed(String userId, String orderId) {
    if (userId.isEmpty || orderId.isEmpty) return false;

    try {
      final String? existingJson = _preferences.getString(_rejectedBannersViewedKey);
      if (existingJson == null || existingJson.isEmpty) return false;

      final Map<String, dynamic> viewedMap = jsonDecode(existingJson) as Map<String, dynamic>;
      final List<dynamic>? userOrderIds = viewedMap[userId] as List<dynamic>?;

      if (userOrderIds == null) return false;
      return userOrderIds.contains(orderId);
    } catch (e) {
      debugPrint('Error checking rejected banner view status: $e');
      return false;
    }
  }

  // Permanently hidden banners (final statuses)
  static const String _permanentlyHiddenBannersKey = "permanently_hidden_banners";

  /// Mark an order banner as permanently hidden (for final statuses)
  static Future<void> markOrderBannerAsPermanentlyHidden(
      String userId, String orderId) async {
    if (userId.isEmpty || orderId.isEmpty) return;

    try {
      final String? existingJson =
          _preferences.getString(_permanentlyHiddenBannersKey);
      Map<String, dynamic> hiddenMap = {};

      if (existingJson != null && existingJson.isNotEmpty) {
        hiddenMap = jsonDecode(existingJson) as Map<String, dynamic>;
      }

      // Get or create list for this user
      List<dynamic> userOrderIds =
          hiddenMap[userId] as List<dynamic>? ?? [];

      // Add order ID if not already present
      if (!userOrderIds.contains(orderId)) {
        userOrderIds.add(orderId);
        hiddenMap[userId] = userOrderIds;
        await _preferences.setString(
            _permanentlyHiddenBannersKey, jsonEncode(hiddenMap));
      }
    } catch (e) {
      debugPrint('Error marking order banner as permanently hidden: $e');
    }
  }

  /// Check if an order banner is permanently hidden
  static bool isOrderBannerPermanentlyHidden(String userId, String orderId) {
    if (userId.isEmpty || orderId.isEmpty) return false;

    try {
      final String? existingJson =
          _preferences.getString(_permanentlyHiddenBannersKey);
      if (existingJson == null || existingJson.isEmpty) return false;

      final Map<String, dynamic> hiddenMap =
          jsonDecode(existingJson) as Map<String, dynamic>;
      final List<dynamic>? userOrderIds = hiddenMap[userId] as List<dynamic>?;

      if (userOrderIds == null) return false;
      return userOrderIds.contains(orderId);
    } catch (e) {
      debugPrint('Error checking permanently hidden banner status: $e');
      return false;
    }
  }

  // User-closed banners (orderId -> statusWhenClosed; re-show when status changes)
  static const String _userClosedBannersKey = "user_closed_banners";

  /// Mark an order banner as closed by the user for the current status.
  static Future<void> markOrderBannerClosed(
      String userId, String orderId, String statusWhenClosed) async {
    if (userId.isEmpty || orderId.isEmpty) return;

    try {
      final String? existingJson =
          _preferences.getString(_userClosedBannersKey);
      Map<String, dynamic> root = {};

      if (existingJson != null && existingJson.isNotEmpty) {
        root = jsonDecode(existingJson) as Map<String, dynamic>;
      }

      Map<String, dynamic> userMap =
          (root[userId] as Map<String, dynamic>?) ?? {};
      userMap[orderId] = statusWhenClosed;
      root[userId] = userMap;
      await _preferences.setString(_userClosedBannersKey, jsonEncode(root));
    } catch (e) {
      debugPrint('Error marking order banner as closed: $e');
    }
  }

  /// True if the user closed the banner for this order and status has not changed.
  /// When status has changed, returns false and clears the stored entry.
  static bool isOrderBannerClosed(
      String userId, String orderId, String currentStatus) {
    if (userId.isEmpty || orderId.isEmpty) return false;

    try {
      final String? existingJson =
          _preferences.getString(_userClosedBannersKey);
      if (existingJson == null || existingJson.isEmpty) return false;

      final Map<String, dynamic> root =
          jsonDecode(existingJson) as Map<String, dynamic>;
      final Map<String, dynamic>? userMap =
          root[userId] as Map<String, dynamic>?;
      if (userMap == null) return false;

      final Object? stored = userMap[orderId];
      if (stored == null) return false;
      final String storedStatus = stored as String;

      if (storedStatus == currentStatus) return true;

      // Status changed: clear this entry so banner shows again; clear async.
      _clearOrderBannerClosed(userId, orderId);
      return false;
    } catch (e) {
      debugPrint('Error checking user-closed banner status: $e');
      return false;
    }
  }

  static Future<void> _clearOrderBannerClosed(
      String userId, String orderId) async {
    try {
      final String? existingJson =
          _preferences.getString(_userClosedBannersKey);
      if (existingJson == null || existingJson.isEmpty) return;

      final Map<String, dynamic> root =
          jsonDecode(existingJson) as Map<String, dynamic>;
      final Map<String, dynamic>? userMap =
          root[userId] as Map<String, dynamic>?;
      if (userMap == null || !userMap.containsKey(orderId)) return;

      userMap.remove(orderId);
      root[userId] = userMap;
      await _preferences.setString(_userClosedBannersKey, jsonEncode(root));
    } catch (e) {
      debugPrint('Error clearing user-closed banner: $e');
    }
  }

  // Completion dialog tracking
  static const String _completionDialogsShownKey = "completion_dialogs_shown";

  /// Mark a completion dialog as shown for a specific user and order
  static Future<void> markCompletionDialogShown(
      String userId, String orderId) async {
    if (userId.isEmpty || orderId.isEmpty) return;

    try {
      final String? existingJson =
          _preferences.getString(_completionDialogsShownKey);
      Map<String, dynamic> shownMap = {};

      if (existingJson != null && existingJson.isNotEmpty) {
        shownMap = jsonDecode(existingJson) as Map<String, dynamic>;
      }

      // Get or create list for this user
      List<dynamic> userOrderIds = shownMap[userId] as List<dynamic>? ?? [];

      // Add order ID if not already present
      if (!userOrderIds.contains(orderId)) {
        userOrderIds.add(orderId);
        shownMap[userId] = userOrderIds;
        await _preferences.setString(
            _completionDialogsShownKey, jsonEncode(shownMap));
      }
    } catch (e) {
      debugPrint('Error marking completion dialog as shown: $e');
    }
  }

  /// Check if a completion dialog has been shown for a specific user and order
  static bool isCompletionDialogShown(String userId, String orderId) {
    if (userId.isEmpty || orderId.isEmpty) return false;

    try {
      final String? existingJson =
          _preferences.getString(_completionDialogsShownKey);
      if (existingJson == null || existingJson.isEmpty) return false;

      final Map<String, dynamic> shownMap =
          jsonDecode(existingJson) as Map<String, dynamic>;
      final List<dynamic>? userOrderIds = shownMap[userId] as List<dynamic>?;

      if (userOrderIds == null) return false;
      return userOrderIds.contains(orderId);
    } catch (e) {
      debugPrint('Error checking completion dialog shown status: $e');
      return false;
    }
  }
}
