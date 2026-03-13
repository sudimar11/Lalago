// ignore_for_file: close_sinks, cancel_subscriptions

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/services/BackendService.dart';
import 'package:foodie_customer/model/AttributesModel.dart';
import 'package:foodie_customer/model/BannerModel.dart';
import 'package:foodie_customer/model/BlockUserModel.dart';
import 'package:foodie_customer/model/BookTableModel.dart';
import 'package:foodie_customer/model/ChatVideoContainer.dart';
import 'package:foodie_customer/model/CodModel.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/DeliveryChargeModel.dart';
import 'package:foodie_customer/model/FavouriteItemModel.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
//import 'package:foodie_customer/model/FlutterWaveSettingDataModel.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/model/PautosOrderModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/Ratingmodel.dart';
import 'package:foodie_customer/model/ReviewAttributeModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/utils/session_manager.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/conversation_model.dart';
import 'package:foodie_customer/model/email_template_model.dart';
import 'package:foodie_customer/model/gift_cards_model.dart';
import 'package:foodie_customer/model/gift_cards_order_model.dart';
import 'package:foodie_customer/model/inbox_model.dart';
import 'package:foodie_customer/model/notification_model.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/paypalSettingData.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/firestore_tx.dart';
import 'package:foodie_customer/model/SearchAnalyticsModel.dart';
import 'package:foodie_customer/model/paytmSettingData.dart';
import 'package:foodie_customer/model/referral_model.dart';
import 'package:foodie_customer/model/pending_referral_model.dart';
import 'package:foodie_customer/services/referral_reward_service.dart';
import 'package:foodie_customer/model/story_model.dart';
import 'package:foodie_customer/model/topupTranHistory.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/reauthScreen/reauth_user_screen.dart';
import 'package:foodie_customer/userPrefrence.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../model/TaxModel.dart';

/// Result of a paginated review fetch.
class ReviewPageResult {
  final List<RatingModel> reviews;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const ReviewPageResult({
    required this.reviews,
    required this.lastDocument,
    required this.hasMore,
  });
}

const String _debugLogPath =
    '/Users/sudimard/Documents/flutter_projects/LalaGo-Customer/.cursor/debug.log';
const String _debugFallbackFileName = 'cursor-debug.log';
const Duration _debugIoTimeout = Duration(milliseconds: 150);
const List<String> _debugLogEndpoints = <String>[
  'http://127.0.0.1:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://localhost:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://100.101.3.145:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://Sudimars-MacBook-Air.local:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
];
const String _runtimeDebugLogPath =
    '/Users/sudimard/Desktop/customer/.cursor/debug.log';
const String _runtimeDebugLogEndpoint =
    'http://127.0.0.1:7243/ingest/de1c04b0-9dd9-4425-b7d2-d38e14e33c57';
const bool _isIosSimulator =
    bool.fromEnvironment('IOS_SIMULATOR', defaultValue: false);
const String _cursorDebugLogPath =
    '/Users/sudimard/Downloads/Lalago/.cursor/debug.log';
const String _cursorDebugLogEndpoint =
    'http://127.0.0.1:7244/ingest/'
    'c9ab929b-94d3-40bd-8785-7deb40c047f7';
const String _cursorDebugLogEndpointEmulator =
    'http://10.0.2.2:7244/ingest/'
    'c9ab929b-94d3-40bd-8785-7deb40c047f7';

Future<void> _appendDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
  if (!kDebugMode) return;
  final payload = <String, Object?>{
    'sessionId': 'debug-session',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  try {
    await File(_debugLogPath).writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {
    for (final endpoint in _debugLogEndpoints) {
      try {
        final client = HttpClient();
        client.connectionTimeout = _debugIoTimeout;
        final request =
            await client.postUrl(Uri.parse(endpoint)).timeout(_debugIoTimeout);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
        await request.close().timeout(_debugIoTimeout);
        client.close();
        break;
      } catch (_) {}
    }
  }
  try {
    final fallbackFile =
        File('${Directory.systemTemp.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {}
  try {
    final tempDir = await getTemporaryDirectory();
    final fallbackFile = File('${tempDir.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {}
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackFile = File('${docsDir.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {}
}

const MethodChannel _keychainChannel = MethodChannel('cursor.debug/keychain');

Future<void> _warmUpKeychain() async {
  if (Platform.isIOS && _isIosSimulator) {
    log('[SIM_KEYCHAIN_BYPASS] skipping keychain warmup on iOS simulator');
    return;
  }
  try {
    await _keychainChannel.invokeMethod<dynamic>('check');
  } catch (_) {}
}

Future<void> _appendRuntimeDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
  if (!kDebugMode) return;
  final payload = <String, Object?>{
    'sessionId': 'debug-session',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  try {
    await File(_runtimeDebugLogPath).writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {
    try {
      final client = HttpClient();
      client.connectionTimeout = _debugIoTimeout;
      final request = await client
          .postUrl(Uri.parse(_runtimeDebugLogEndpoint))
          .timeout(_debugIoTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      await request.close().timeout(_debugIoTimeout);
      client.close();
    } catch (_) {}
  }
}

Future<void> _appendCursorDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
  if (!kDebugMode) return;
  final payload = <String, Object?>{
    'sessionId': 'debug-session',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  try {
    final logFile = File(_cursorDebugLogPath);
    await logFile.parent.create(recursive: true);
    await File(_cursorDebugLogPath).writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    ).timeout(_debugIoTimeout);
  } catch (_) {
    final endpoints = Platform.isAndroid
        ? <String>[_cursorDebugLogEndpointEmulator, _cursorDebugLogEndpoint]
        : <String>[_cursorDebugLogEndpoint];
    for (final endpoint in endpoints) {
      try {
        final client = HttpClient();
        client.connectionTimeout = _debugIoTimeout;
        final request =
            await client.postUrl(Uri.parse(endpoint)).timeout(_debugIoTimeout);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
        await request.close().timeout(_debugIoTimeout);
        client.close();
        break;
      } catch (_) {}
    }
  }
}

/// Result of a paginated product query.
class ProductPageResult {
  final List<ProductModel> products;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;

  const ProductPageResult(this.products, this.lastDocument);
}

class FireStoreUtils {
  static const bool isMessagingEnabled = true;
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();
  final geo = GeoFlutterFire();

  /// Cached FCM token from a previous successful getToken() (e.g. at startup
  /// before user was set). Used so we can save to Firestore once user is available.
  static String? _lastFcmToken;
  static Future<void> _referralTxChain = Future<void>.value();

  static Future<T> _runSerializedReferral<T>(Future<T> Function() operation) {
    final future = _referralTxChain.then((_) => operation());
    _referralTxChain = future.then((_) => null, onError: (_) => null);
    return future;
  }

  static void _setTxBreadcrumb({
    required String name,
    required String params,
  }) {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final stackPreview =
        StackTrace.current.toString().split('\n').take(8).join('\n');

    final crashlytics = FirebaseCrashlytics.instance;
    crashlytics.setCustomKey('last_tx_name', name);
    crashlytics.setCustomKey('last_tx_params', params);
    crashlytics.setCustomKey('last_tx_started_at_ms', startedAt);
    crashlytics.setCustomKey('last_tx_stack', stackPreview);
    crashlytics.log('TX_START $name $params');
  }

  static String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return 'null';
    if (token.length <= 20) return '***';
    return '${token.substring(0, 12)}...${token.substring(token.length - 4)}';
  }

  static Future<String?> safeGetFcmToken() async {
    try {
      if (!isMessagingEnabled) {
        debugPrint(
            '[FCM_DEBUG] safeGetFcmToken skipped (messaging disabled)');
        return _lastFcmToken;
      }
      if (Platform.isIOS) {
        await firebaseMessaging.requestPermission();
        var apnsToken = await firebaseMessaging.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          await Future<void>.delayed(const Duration(seconds: 2));
          apnsToken = await firebaseMessaging.getAPNSToken();
        }
        if (apnsToken == null || apnsToken.isEmpty) {
          debugPrint(
              '[FCM_DEBUG] APNs token unavailable after retry, '
              'using cache=${_lastFcmToken != null}');
          return _lastFcmToken;
        }
      }

      final token = await firebaseMessaging.getToken();
      if (token != null && token.isNotEmpty) {
        _lastFcmToken = token;
        debugPrint(
            '[FCM_DEBUG] token retrieval: OK preview=${_tokenPreview(token)} '
            'len=${token.length}');
        return token;
      }
      debugPrint(
          '[FCM_DEBUG] token retrieval: getToken() null/empty, '
          'using cache=${_lastFcmToken != null}');
      return _lastFcmToken;
    } catch (e) {
      debugPrint('[FCM_DEBUG] token retrieval FAILED: $e, cache=${_lastFcmToken != null}');
      return _lastFcmToken;
    }
  }

  static Future<void> safeInitMessaging() async {
    try {
      if (!isMessagingEnabled) {
        return;
      }
      if (!Platform.isIOS) return;
      await firebaseMessaging.requestPermission();
      final apnsToken = await firebaseMessaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        log('APNs token unavailable during init.');
      }
    } catch (e) {
      log('FCM init failed: $e');
    }
  }

  static Future<void> refreshFcmTokenForUser(User user, {int retryCount = 0}) async {
    if (!isMessagingEnabled) return;
    const maxRetries = 4;
    final delays = [2, 5, 10, 15];
    debugPrint(
        '[FCM_DEBUG] refreshFcmTokenForUser user=${user.userID} retry=$retryCount');
    final token = await safeGetFcmToken();
    if (token == null || token.isEmpty) {
      if (retryCount < maxRetries) {
        final delay = retryCount < delays.length ? delays[retryCount] : 15;
        debugPrint(
            '[FCM_DEBUG] no token yet, retry #${retryCount + 1} in ${delay}s');
        Future.delayed(Duration(seconds: delay), () {
          refreshFcmTokenForUser(user, retryCount: retryCount + 1);
        });
      } else {
        debugPrint(
            '[FCM_DEBUG] refreshFcmTokenForUser gave up after $maxRetries retries');
      }
      return;
    }
    if (user.fcmToken == token) {
      debugPrint(
          '[FCM_DEBUG] token unchanged for user=${user.userID}, saving anyway to ensure Firestore has it');
    }
    user.fcmToken = token;
    try {
      await firestore.collection(USERS).doc(user.userID).update({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      debugPrint(
          '[FCM_DEBUG] token saved to Firestore: users/${user.userID} '
          'preview=${_tokenPreview(token)}');
      unawaited(_updateActiveOrdersFcmToken(user.userID, token));
    } catch (e) {
      debugPrint('[FCM_DEBUG] token saved to Firestore FAILED: $e');
      log('FCM update failed: $e');
      if (retryCount < maxRetries) {
        final delay = retryCount < delays.length ? delays[retryCount] : 15;
        Future.delayed(Duration(seconds: delay), () {
          refreshFcmTokenForUser(user, retryCount: retryCount + 1);
        });
      }
    }
  }

  static Future<void> updateActiveOrdersFcmTokenForUser(
      String customerId, String token) =>
      _updateActiveOrdersFcmToken(customerId, token);

  /// Removes token from user's fcmTokens array. Call on logout.
  static Future<void> removeFcmToken(String userId, String token) async {
    try {
      if (userId.isEmpty || token.isEmpty) return;
      await firestore.collection(USERS).doc(userId).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      debugPrint('[FCM_DEBUG] Token removed from array for user: $userId');
    } catch (e) {
      debugPrint('[FCM_DEBUG] removeFcmToken failed: $e');
    }
  }

  static Future<void> _updateActiveOrdersFcmToken(String customerId, String token) async {
    try {
      final activeStatuses = {
        ORDER_STATUS_PLACED,
        ORDER_STATUS_ACCEPTED,
        ORDER_STATUS_DRIVER_ACCEPTED,
        ORDER_STATUS_SHIPPED,
        ORDER_STATUS_IN_TRANSIT,
      };
      final snapshot = await firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: customerId)
          .limit(30)
          .get();
      int count = 0;
      for (final doc in snapshot.docs) {
        final status = doc.get('status') as String?;
        if (status != null && activeStatuses.contains(status)) {
          await doc.reference.update({'author.fcmToken': token});
          count++;
        }
      }
      if (count > 0) {
        debugPrint('[TOKEN_DEBUG] Customer: updated author.fcmToken for $count active orders');
      }
    } catch (e) {
      debugPrint('[TOKEN_DEBUG] Customer: _updateActiveOrdersFcmToken failed $e');
    }
  }

  late StreamController<User> driverStreamController;
  late StreamSubscription driverStreamSub;

  Stream<User> getDriver(String userId) async* {
    if (userId.isEmpty) {
      debugPrint("Error: Provided userId is empty.");
      return;
    }

    try {
      debugPrint("Initializing driver stream for userId: $userId...");

      driverStreamController = StreamController<User>();

      driverStreamSub = firestore
          .collection(USERS)
          .doc(userId)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.data() != null) {
          debugPrint("Driver data received: ${snapshot.data()}");
          try {
            User? user = User.fromJson(snapshot.data()!);
            debugPrint("Driver parsed successfully: ${user.toJson()}");
            driverStreamController.sink.add(user);
          } catch (e) {
            debugPrint("Error parsing driver data: $e");
          }
        } else {
          debugPrint("No data found for driver with userId: $userId");
        }
      });

      yield* driverStreamController.stream;
    } catch (e) {
      debugPrint("Error in getDriver: $e");
    } finally {
      debugPrint("Cleaning up driver stream for userId: $userId");
      driverStreamSub.cancel();
      driverStreamController.close();
    }
  }

  late StreamController<OrderModel> ordersByIdStreamController;
  late StreamSubscription ordersByIdStreamSub;

  Stream<OrderModel?> getOrderByID(String inProgressOrderID) async* {
    ordersByIdStreamController = StreamController();
    ordersByIdStreamSub = firestore
        .collection(ORDERS)
        .doc(inProgressOrderID)
        .snapshots()
        .listen((onData) async {
      if (onData.data() != null) {
        OrderModel? orderModel = OrderModel.fromJson(onData.data()!);
        ordersByIdStreamController.sink.add(orderModel);
      }
    });
    yield* ordersByIdStreamController.stream;
  }

  static Future<OrderModel?> getOrderByIdOnce(String orderId) async {
    try {
      final doc = await firestore.collection(ORDERS).doc(orderId).get();
      if (doc.exists && doc.data() != null) {
        return OrderModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('FireStoreUtils.getOrderByIdOnce error: $e');
      return null;
    }
  }

  Future<RatingModel?> getOrderReviewsbyID(
      String ordertId, String productId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('orderid', isEqualTo: ordertId)
        .where('productId', isEqualTo: productId)
        .get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        debugPrint('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  static Future<ProductModel?> updateProduct(ProductModel prodduct) async {
    return await firestore
        .collection(PRODUCTS)
        .doc(prodduct.id)
        .set(prodduct.toJson())
        .then((document) {
      return prodduct;
    });
  }

  Future<List<VendorCategoryModel>> getHomePageShowCategory() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery = await firestore
        .collection(VENDORS_CATEGORIES)
        .where("show_in_homepage", isEqualTo: true)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(cuisinesQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  /// Optional: Batched home screen data via Cloud Function. Use as fast path
  /// in HomeScreen init; fallback to individual fetches if this fails.
  static Future<Map<String, dynamic>?> getHomeScreenInitialData(
    String? userId,
    double? lat,
    double? lng,
  ) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('getHomeScreenInitialData');
      final result = await callable.call<Map<String, dynamic>>({
        'userId': userId,
        'lat': lat,
        'lng': lng,
      });
      return result.data;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HOME] getHomeScreenInitialData failed: $e');
      }
      return null;
    }
  }

  Future<List<BannerModel>> getHomeTopBanner() async {
    List<BannerModel> bannerHome = [];
    try {
      debugPrint(
          '[CAROUSEL] getHomeTopBanner: Querying advertisements collection');
      // Query the advertisements collection with correct field names
      QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
          .collection(ADVERTISEMENTS)
          .where("is_enabled", isEqualTo: true)
          .where("is_deleted", isEqualTo: false)
          .orderBy("priority", descending: false)
          .get();

      debugPrint(
          '[CAROUSEL] getHomeTopBanner: Found ${bannerHomeQuery.docs.length} documents');

      final now = DateTime.now();
      await Future.forEach(bannerHomeQuery.docs,
          (QueryDocumentSnapshot<Map<String, dynamic>> document) {
        try {
          final data = document.data();

          // Check date range (start_date and end_date)
          final startDate = data['start_date'] as Timestamp?;
          final endDate = data['end_date'] as Timestamp?;

          if (startDate != null && now.isBefore(startDate.toDate())) {
            debugPrint('[CAROUSEL] Banner ${document.id} not started yet');
            return; // Skip banners that haven't started
          }

          if (endDate != null && now.isAfter(endDate.toDate())) {
            debugPrint('[CAROUSEL] Banner ${document.id} has expired');
            return; // Skip expired banners
          }

          // Map the database fields to BannerModel
          // image_urls is an array, take the first one as photo
          final imageUrls = data['image_urls'] as List<dynamic>?;
          final photo = imageUrls != null && imageUrls.isNotEmpty
              ? imageUrls[0] as String
              : null;

          if (photo == null || photo.isEmpty) {
            debugPrint('[CAROUSEL] Banner ${document.id} has no image URL');
            return; // Skip banners without images
          }

          // Create a mapped object for BannerModel
          final mappedData = {
            'photo': photo,
            'title': data['title'] ?? '',
            'is_publish': data['is_enabled'] ?? false,
            'set_order': data['priority'] ?? 0,
            'redirect_type': null,
            'redirect_id': null,
          };

          bannerHome.add(BannerModel.fromJson(mappedData));
          debugPrint(
              '[CAROUSEL] Successfully added banner: ${data['title']} (photo: ${photo.substring(0, photo.length > 50 ? 50 : photo.length)}...)');
        } catch (e) {
          debugPrint(
              '[CAROUSEL] FireStoreUtils.getHomeTopBanner Parse error: $e');
          debugPrint('[CAROUSEL] Document data: ${document.data()}');
        }
      });

      debugPrint(
          '[CAROUSEL] getHomeTopBanner: Returning ${bannerHome.length} banners');
    } catch (e) {
      debugPrint('[CAROUSEL] FireStoreUtils.getHomeTopBanner Error: $e');
    }
    return bannerHome;
  }

  Future<List<BannerModel>> getHomeMiddleBanner() async {
    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where("position", isEqualTo: "middle")
        .orderBy("set_order", descending: false)
        .get();
    await Future.forEach(bannerHomeQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return bannerHome;
  }

  Future<ProductModel> getProductByID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(PRODUCTS)
        .where('id', isEqualTo: productId)
        .get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      debugPrint('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  static Future<VendorModel?> getVendor(String vid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(VENDORS).doc(vid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return VendorModel.fromJson(userDocument.data()!);
    } else {
      debugPrint("nulllll");
      return null;
    }
  }

  Future<List<FavouriteItemModel>> getFavouritesProductList(
      String userId) async {
    List<FavouriteItemModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites = await firestore
        .collection(FavouriteItem)
        .where('user_id', isEqualTo: userId)
        .get();
    await Future.forEach(favourites.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        lstFavourites.add(FavouriteItemModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FavouriteModel.getCurrencys Parse error $e');
      }
    });
    return lstFavourites;
  }

  static Future<List<AttributesModel>> getAttributes() async {
    List<AttributesModel> attributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await firestore.collection(VENDOR_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        attributesList.add(AttributesModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return attributesList;
  }

  static Future<List<ReviewAttributeModel>> getAllReviewAttributes() async {
    List<ReviewAttributeModel> reviewAttributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await firestore.collection(REVIEW_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewAttributesList
            .add(ReviewAttributeModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewAttributesList;
  }

  Future<List<RatingModel>> getReviewList(String productId) async {
    List<RatingModel> reviewList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(Order_Rating)
        .where('productId', isEqualTo: productId)
        .get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewList.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewList;
  }

  /// Paginated review fetch. Requires Firestore composite index:
  /// Order_Rating: productId (ASC) + createdAt (DESC)
  Future<ReviewPageResult> getReviewListPaginated(
    String productId, {
    int limit = 10,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = firestore
        .collection(Order_Rating)
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final reviews = <RatingModel>[];
    for (final doc in snapshot.docs) {
      try {
        reviews.add(RatingModel.fromJson(doc.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getReviewListPaginated Parse error $e');
      }
    }
    final lastDoc =
        snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return ReviewPageResult(
      reviews: reviews,
      lastDocument: lastDoc,
      hasMore: snapshot.docs.length == limit,
    );
  }

  static Future<List<ProductModel>> getStoreProduct(String storeId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: storeId)
        .where('publish', isEqualTo: true)
        .limit(6)
        .get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        print(document.data());
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getTakeawayStoreProduct(
      String storeId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: storeId)
        .where('publish', isEqualTo: true)
        .limit(6)
        .get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        print(document.data());
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getProductListByCategoryId(
      String categoryId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(PRODUCTS)
        .where('categoryID', isEqualTo: categoryId)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  Future<void> setFavouriteStoreItem(FavouriteItemModel favouriteModel) async {
    await firestore
        .collection(FavouriteItem)
        .add(favouriteModel.toJson())
        .then((value) {});
  }

  void removeFavouriteItem(FavouriteItemModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteItem)
        .where("product_id", isEqualTo: favouriteModel.productId)
        .get()
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance
            .collection(FavouriteItem)
            .doc(element.id)
            .delete()
            .then((value) {
          debugPrint("Success!");
        });
      }
    });
  }

  static Future<User?> getCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return User.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  static Future<NotificationModel?> getNotificationContent(String type) async {
    NotificationModel? notificationModel;
    await firestore
        .collection(dynamicNotification)
        .where('type', isEqualTo: type)
        .get()
        .then((value) {
      print("------>");
      if (value.docs.isNotEmpty) {
        print(value.docs.first.data());

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(
            id: "",
            message: "Notification setup is pending",
            subject: "setup notification",
            type: "");
      }
    });
    return notificationModel;
  }

  static Future<EmailTemplateModel?> getEmailTemplates(String type) async {
    EmailTemplateModel? emailTemplateModel;
    await firestore
        .collection(emailTemplates)
        .where('type', isEqualTo: type)
        .get()
        .then((value) {
      print("------>");
      if (value.docs.isNotEmpty) {
        print(value.docs.first.data());
        emailTemplateModel =
            EmailTemplateModel.fromJson(value.docs.first.data());
      }
    });
    return emailTemplateModel;
  }

  static Future<bool> sendFcmMessage(String type, String token) async {
    try {
      NotificationModel? notificationModel = await getNotificationContent(type);
      print(notificationModel?.toJson());
      var url = 'https://fcm.googleapis.com/fcm/send';
      var header = {
        "Content-Type": "application/json",
        "Authorization": "key=$SERVER_KEY",
      };
      var request = {
        "notification": {
          "title": notificationModel!.subject ?? '',
          "body": notificationModel.message ?? '',
          "sound": "default",
          "android_channel_id": "promo_system",
          // "color": COLOR_PRIMARY,
        },
        "priority": "high",
        'data': <String, dynamic>{'id': '1', 'status': 'done'},
        "click_action": "FLUTTER_NOTIFICATION_CLICK",
        "to": token
      };

      var client = new http.Client();
      await client.post(Uri.parse(url),
          headers: header, body: json.encode(request));
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  static Future<bool> sendChatFcmMessage(
    String title,
    String message,
    String token, {
    String? orderId,
    String? orderStatus,
    String? senderRole,
    String? messageType,
    String? customerId,
    String? tokenSource,
  }) async {
    try {
      final projectId = Firebase.app().options.projectId;
      final region = await _getCloudFunctionRegion();
      final functionUrl =
          'https://$region-$projectId.cloudfunctions.net/sendIndividualNotification';
      final dataPayload = <String, dynamic>{
        'type': 'chat_message',
      };
      if (orderId != null && orderId.isNotEmpty) {
        dataPayload['orderId'] = orderId;
      }
      if (orderStatus != null && orderStatus.isNotEmpty) {
        dataPayload['orderStatus'] = orderStatus;
      }
      if (senderRole != null && senderRole.isNotEmpty) {
        dataPayload['senderRole'] = senderRole;
      }
      if (messageType != null && messageType.isNotEmpty) {
        dataPayload['messageType'] = messageType;
      }
      if (customerId != null && customerId.isNotEmpty) {
        dataPayload['customerId'] = customerId;
      }
      if (tokenSource != null && tokenSource.isNotEmpty) {
        dataPayload['tokenSource'] = tokenSource;
      }
      final payload = <String, dynamic>{
        'title': title,
        'body': message,
        'token': token,
        'data': dataPayload,
        'badge': 1,
        'sound': 'default',
      };

      final tokenPreview = token.length > 24
          ? '${token.substring(0, 12)}...${token.substring(token.length - 4)}'
          : '***';
      debugPrint(
          '[sendChatFcmMessage] functionUrl=$functionUrl '
          'tokenLength=${token.length} tokenPreview=$tokenPreview');

      final response = await http
          .post(
            Uri.parse(functionUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint(
          '[sendChatFcmMessage] response status=${response.statusCode} '
          'body=${response.body}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  static Future<String> _getCloudFunctionRegion() async {
    return 'us-central1';
  }

  Future<String> uploadProductImage(File image, String progress) async {
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('flutter/uberEats/productImages/$uniqueID'
        '.png');
    UploadTask uploadTask = upload.putFile(image);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          '$progress \n${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} / ${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)}KB');
    });
    try {
      await uploadTask.whenComplete(() {});
    } catch (onError) {
      debugPrint((onError as PlatformException).message);
    }
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<User?> updateCurrentUser(User user) async {
    print('🔄 DEBUG: Starting user update in Firestore...');
    print('🔄 DEBUG: User ID: ${user.userID}');
    print('🔄 DEBUG: User email: ${user.email}');
    print('🔄 DEBUG: User profile picture URL: ${user.profilePictureURL}');

    try {
      final userJson = user.toJson();
      print(
          '🔄 DEBUG: User JSON created, size: ${userJson.toString().length} characters');

      return await firestore
          .collection(USERS)
          .doc(user.userID)
          .set(userJson)
          .then((document) {
        print('✅ DEBUG: User updated in Firestore successfully');
        print('🔄 DEBUG: Updating app state...');
        MyAppState.currentUser = user;
        print('✅ DEBUG: App state updated successfully');
        return user;
      });
    } catch (e, stackTrace) {
      print('❌ DEBUG: Error updating user in Firestore: $e');
      print('❌ DEBUG: Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore
        .collection(VENDORS)
        .doc(vendor.id)
        .set(vendor.toJson())
        .then((document) {
      return vendor;
    });
  }

  static Future<String> uploadUserImageToFireStorage(
      File image, String userID) async {
    print('🔄 DEBUG: Starting Firebase upload...');
    print('🔄 DEBUG: User ID: $userID');
    print('🔄 DEBUG: Image path: ${image.path}');
    print('🔄 DEBUG: Image exists: ${await image.exists()}');

    try {
      // Check if image file exists and is readable
      if (!await image.exists()) {
        print('❌ DEBUG: Image file does not exist at path: ${image.path}');
        throw Exception('Image file does not exist');
      }

      // Get file size for debugging
      final fileSize = await image.length();
      print('🔄 DEBUG: File size: $fileSize bytes');

      Reference upload = storage.child('images/$userID.png');
      print('🔄 DEBUG: Firebase storage reference created: images/$userID.png');

      // Add metadata for better error handling
      final metadata = SettableMetadata(
        contentType: 'image/png',
        customMetadata: {
          'uploadedBy': userID,
          'uploadedAt': DateTime.now().toIso8601String(),
          'fileSize': fileSize.toString(),
        },
      );
      print('🔄 DEBUG: Upload metadata created');

      print('🔄 DEBUG: Starting upload task...');
      UploadTask uploadTask = upload.putFile(image, metadata);
      print('🔄 DEBUG: Upload task created, starting upload...');

      // Listen to upload progress for debugging
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress =
            (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        print('🔄 DEBUG: Upload progress: ${progress.toStringAsFixed(2)}%');
        print(
            '🔄 DEBUG: Bytes transferred: ${snapshot.bytesTransferred}/${snapshot.totalBytes}');
      });

      print('🔄 DEBUG: Waiting for upload to complete...');
      var snapshot = await uploadTask.whenComplete(() {
        print('✅ DEBUG: Upload task completed');
      });

      print('🔄 DEBUG: Getting download URL...');
      var downloadUrl = await snapshot.ref.getDownloadURL();
      print('✅ DEBUG: Download URL obtained: $downloadUrl');

      return downloadUrl.toString();
    } catch (e, stackTrace) {
      print('❌ DEBUG: Firebase upload error: $e');
      print('❌ DEBUG: Stack trace: $stackTrace');
      rethrow; // Re-throw to be caught by calling method
    }
  }

  Future<Url> uploadChatImageToFireStorage(
      File image, BuildContext context) async {
    showProgress(context, 'Uploading image...', false);
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('images/$uniqueID.png');
    File? compressedImage = await compressImage(image);
    UploadTask uploadTask = upload.putFile(compressedImage ?? image);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          'Uploading image ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
          '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
          'KB');
    });
    try {
      await uploadTask.whenComplete(() {});
    } catch (onError) {
      debugPrint((onError as PlatformException).message);
    }
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(
        mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
  }

  Future<ChatVideoContainer> uploadChatVideoToFireStorage(
      File video, BuildContext context) async {
    showProgress(context, 'Uploading video...', false);
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('videos/$uniqueID.mp4');
    File compressedVideo = await _compressVideo(video);
    SettableMetadata metadata = SettableMetadata(contentType: 'video');
    UploadTask uploadTask = upload.putFile(compressedVideo, metadata);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          'Uploading video ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
          '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
          'KB');
    });
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    // Video thumbnail generation is temporarily unavailable
    // Return empty string as fallback - thumbnail will not be generated
    String thumbnailDownloadUrl = '';
    hideProgress();
    return ChatVideoContainer(
        videoUrl: Url(
            url: downloadUrl.toString(), mime: metaData.contentType ?? 'video'),
        thumbnailUrl: thumbnailDownloadUrl);
  }

  Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('thumbnails/$uniqueID.png');
    File? compressedImage = await compressImage(file);
    UploadTask uploadTask = upload.putFile(compressedImage ?? file);
    var downloadUrl =
        await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  Stream<User> getUserByID(String id) async* {
    StreamController<User> userStreamController = StreamController();
    firestore.collection(USERS).doc(id).snapshots().listen((user) {
      try {
        User userModel = User.fromJson(user.data() ?? {});
        userStreamController.sink.add(userModel);
      } catch (e) {
        debugPrint(
            'FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* userStreamController.stream;
  }

  static getPaypalSettingData() async {
    firestore
        .collection(Setting)
        .doc("paypalSettings")
        .get()
        .then((paypalData) {
      try {
        PaypalSettingData paypalDataModel =
            PaypalSettingData.fromJson(paypalData.data() ?? {});
        UserPreference.setPayPalData(paypalDataModel);
      } catch (error) {
        debugPrint(error.toString());
      }
    });
  }

  //static getFlutterWaveSettingData() async {
  //  firestore
  //      .collection(Setting)
  //      .doc("flutterWave")
  //      .get()
  //      .then((flutterWaveData) {
  //    try {
  //      FlutterWaveSettingData flutterWaveSettingData =
  //          FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});
  //      UserPreference.setFlutterWaveData(flutterWaveSettingData);
  //    } catch (error) {
  //      debugPrint("error>>>122");
  //      debugPrint(error.toString());
  //    }
  //  });
  //}

  static getPaytmSettingData() async {
    firestore.collection(Setting).doc("PaytmSettings").get().then((paytmData) {
      try {
        PaytmSettingData paytmSettingData =
            PaytmSettingData.fromJson(paytmData.data() ?? {});
        UserPreference.setPaytmData(paytmSettingData);
      } catch (error) {
        debugPrint(error.toString());
      }
    });
  }

  static getWalletSettingData() {
    firestore
        .collection(Setting)
        .doc('walletSettings')
        .get()
        .then((walletSetting) {
      try {
        bool walletEnable = walletSetting.data()!['isEnabled'];
        UserPreference.setWalletData(walletEnable);
      } catch (e) {
        debugPrint(e.toString());
      }
    });
  }

  static const _codCacheKey = 'cod_settings_enabled';

  Future<CodModel?> getCod() async {
    CodModel? result;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final codQuery = await firestore
            .collection(Setting)
            .doc('CODSettings')
            .get()
            .timeout(const Duration(seconds: 10));
        if (codQuery.data() != null) {
          result = CodModel.fromJson(codQuery.data()!);
          _cacheCodEnabled(result.cod);
          if (kDebugMode) {
            log('COD: loaded from Firestore, enabled=${result.cod}');
          }
          return result;
        }
        result = CodModel(cod: false);
        _cacheCodEnabled(false);
        return result;
      } catch (e, st) {
        if (kDebugMode) {
          log('COD: fetch failed (attempt ${attempt + 1}): $e', stackTrace: st);
        }
      }
    }
    result = await _getCachedCodModel();
    if (kDebugMode) {
      log('COD: using fallback, enabled=${result?.cod ?? true}');
    }
    return result ?? CodModel(cod: true);
  }

  Future<void> _cacheCodEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_codCacheKey, enabled);
    } catch (_) {}
  }

  Future<CodModel?> _getCachedCodModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_codCacheKey);
      if (cached != null) return CodModel(cod: cached);
    } catch (_) {}
    return null;
  }

  Future<DeliveryChargeModel?> getDeliveryCharges() async {
    // Prefer New_DeliveryCharge (baseDeliveryCharge + per km beyond threshold)
    DocumentSnapshot<Map<String, dynamic>> newDoc =
        await firestore.collection(Setting).doc('New_DeliveryCharge').get();
    if (newDoc.data() != null) {
      return DeliveryChargeModel.fromJson(newDoc.data()!);
    }
    // Fallback to legacy DeliveryCharge
    DocumentSnapshot<Map<String, dynamic>> codQuery =
        await firestore.collection(Setting).doc('DeliveryCharge').get();
    if (codQuery.data() != null) {
      return DeliveryChargeModel.fromJson(codQuery.data()!);
    }
    return null;
  }

  Future<String?> getRestaurantNearBy() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery =
        await firestore.collection(Setting).doc('RestaurantNearBy').get();
    if (codQuery.data() != null) {
      radiusValue = double.parse(codQuery["radios"].toString());
      debugPrint("--------->$radiusValue");
      return codQuery["radios"].toString();
    } else {
      return "";
    }
  }

  Future<Map<String, dynamic>?> getAdminCommission() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery =
        await firestore.collection(Setting).doc('AdminCommission').get();
    if (codQuery.data() != null) {
      Map<String, dynamic> getValue = {
        "adminCommission": codQuery["fix_commission"].toString(),
        "isAdminCommission": codQuery["isEnabled"],
        'adminCommissionType': codQuery["commissionType"]
      };
      debugPrint(getValue.toString() + "===____");
      return getValue;
    } else {
      return null;
    }
  }

  Future<List<ProductModel>> getAllProducts() async {
    List<ProductModel> products = [];

    try {
      QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
          .collection(PRODUCTS)
          .where('publish', isEqualTo: true)
          .get();

      for (var document in productsQuery.docs) {
        try {
          final data = document.data();
          if (data.isEmpty) continue;

          products.add(ProductModel.fromJson(data));
        } catch (e) {
          debugPrint('Error parsing product ${document.id}: $e');
          debugPrint('Product data: ${document.data()}');
        }
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    }

    return products;
  }

  Future<List<ProductModel>> fetchAllProducts() async {
    List<ProductModel> products = await getAllProducts();
    return products;
  }

  /// Paginated products with publish filter for home screen.
  /// Requires Firestore composite index: publish (ASC) + createdAt (DESC).
  Future<List<ProductModel>> getProductsPaginatedWithPublish({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query<Map<String, dynamic>> query = firestore
          .collection(PRODUCTS)
          .where('publish', isEqualTo: true)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data.isEmpty) return null;
        try {
          return ProductModel.fromJson(data);
        } catch (e) {
          debugPrint('Error parsing product ${doc.id}: $e');
          return null;
        }
      }).whereType<ProductModel>().toList();

      return products;
    } catch (e) {
      debugPrint('Error loading home screen products: $e');
      return [];
    }
  }

  /// Load products for home screen with pagination. Default limit 50.
  Future<List<ProductModel>> getHomeScreenProducts({int limit = 50}) async {
    return getProductsPaginatedWithPublish(limit: limit, lastDocument: null);
  }

  /// Paginated products with publish filter, returns products + cursor for
  /// pagination (e.g. sulit screen).
  Future<ProductPageResult> getProductsPaginatedWithPublishResult({
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
  }) async {
    try {
      Query<Map<String, dynamic>> query = firestore
          .collection(PRODUCTS)
          .where('publish', isEqualTo: true)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data.isEmpty) return null;
        try {
          return ProductModel.fromJson(data);
        } catch (e) {
          debugPrint('Error parsing product ${doc.id}: $e');
          return null;
        }
      }).whereType<ProductModel>().toList();

      final lastDoc =
          snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      return ProductPageResult(products, lastDoc);
    } catch (e) {
      debugPrint('Error loading products with cursor: $e');
      return const ProductPageResult([], null);
    }
  }

  Future<List<String>> getMostOrderedProductIdsForToday({int limit = 30}) async {
    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));

    QuerySnapshot<Map<String, dynamic>> ordersQuery = await firestore
        .collection(ORDERS)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(endOfDay),
        )
        .get();

    final Map<String, int> productCounts =
        _extractProductCountsFromOrders(ordersQuery.docs);

    final sorted = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<String> topIds =
        sorted.take(limit).map((entry) => entry.key).toList();

    return topIds;
  }

  Future<List<String>> getMostOrderedProductIdsForYesterday({
    int limit = 30,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);
    final DateTime startOfYesterday =
        startOfToday.subtract(const Duration(days: 1));
    final DateTime endOfYesterday = startOfToday;

    QuerySnapshot<Map<String, dynamic>> ordersQuery = await firestore
        .collection(ORDERS)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfYesterday),
        )
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(endOfYesterday),
        )
        .get();

    final Map<String, int> productCounts =
        _extractProductCountsFromOrders(ordersQuery.docs);

    final sorted = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<String> topIds =
        sorted.take(limit).map((entry) => entry.key).toList();

    return topIds;
  }

  /// Returns popular products for today with order counts for AI chat.
  Future<List<Map<String, dynamic>>> getPopularProductsWithCountsForToday({
    int limit = 15,
  }) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final ordersQuery = await firestore
        .collection(ORDERS)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(endOfDay),
        )
        .get();

    final productCounts = _extractProductCountsFromOrders(ordersQuery.docs);
    final sorted = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEntries = sorted.take(limit).toList();

    final result = <Map<String, dynamic>>[];
    for (final entry in topEntries) {
      try {
        final doc = await firestore.collection(PRODUCTS).doc(entry.key).get();
        if (!doc.exists || doc.data() == null) continue;

        final data = doc.data()!;
        final vendorID = (data['vendorID'] ?? '').toString();
        String vendorName = '';
        if (vendorID.isNotEmpty) {
          final vendorDoc =
              await firestore.collection(VENDORS).doc(vendorID).get();
          if (vendorDoc.exists && vendorDoc.data() != null) {
            vendorName =
                (vendorDoc.data()!['title'] ?? '').toString();
          }
        }

        final photo = (data['photo'] ?? '').toString();
        result.add({
          'id': entry.key,
          'name': (data['name'] ?? '').toString(),
          'price': (data['price'] ?? '0').toString(),
          'vendorID': vendorID,
          'vendorName': vendorName,
          'imageUrl': getImageVAlidUrl(photo),
          'orderCount': entry.value,
        });
      } catch (_) {}
    }
    return result;
  }

  /// Extracts product IDs and quantities from raw order docs without parsing
  /// OrderModel/CartProduct, which can throw on null fields in Firestore.
  static Map<String, int> _extractProductCountsFromOrders(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final Map<String, int> productCounts = {};
    for (final doc in docs) {
      final products = doc.data()['products'] as List<dynamic>? ?? [];
      for (final item in products) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id == null || id is! String || id.isEmpty) continue;
        final baseId = id.split('~').first;
        final qty = item['quantity'];
        final quantity = qty is int
            ? qty
            : (int.tryParse(qty?.toString() ?? '0') ?? 0);
        if (quantity > 0) {
          productCounts[baseId] = (productCounts[baseId] ?? 0) + quantity;
        }
      }
    }
    return productCounts;
  }

  Future<List<ProductModel>> getAllTakeAWayProducts() async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        .where('publish', isEqualTo: true)
        .limit(200)
        .get();
    await Future.forEach(productsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        debugPrint(
            'productspppp**-123--FireStoreUtils.getAllProducts Parse error $e');
      }
    });

    // Sort products by orderCount in descending order (top orders first)
    products.sort((a, b) {
      int aCount = a.orderCount ?? 0;
      int bCount = b.orderCount ?? 0;
      return bCount.compareTo(aCount);
    });

    return products;
  }

  Future<List<ProductModel>> getAllDelevryProducts() async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        .where("takeawayOption", isEqualTo: false)
        .where('publish', isEqualTo: true)
        .limit(200)
        .get();
    await Future.forEach(productsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        debugPrint(
            'productspppp**-FireStoreUtils.getAllProducts Parse error $e  ${document.data()['id']}');
      }
    });

    // Sort products by orderCount in descending order (top orders first)
    products.sort((a, b) {
      int aCount = a.orderCount ?? 0;
      int bCount = b.orderCount ?? 0;
      return bCount.compareTo(aCount);
    });

    return products;
  }

  Future<bool> blockUser(User blockedUser, String type) async {
    bool isSuccessful = false;
    BlockUserModel blockUserModel = BlockUserModel(
        type: type,
        source: MyAppState.currentUser!.userID,
        dest: blockedUser.userID,
        createdAt: Timestamp.now());
    await firestore
        .collection(REPORTS)
        .add(blockUserModel.toJson())
        .then((onValue) {
      isSuccessful = true;
    });
    return isSuccessful;
  }

  Future<Url> uploadAudioFile(File file, BuildContext context) async {
    showProgress(context, 'Uploading Audio...', false);
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('audio/$uniqueID.mp3');
    SettableMetadata metadata = SettableMetadata(contentType: 'audio');
    UploadTask uploadTask = upload.putFile(file, metadata);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          'Uploading Audio ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
          '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
          'KB');
    });
    try {
      await uploadTask.whenComplete(() {});
    } catch (onError) {
      debugPrint((onError as PlatformException).message);
    }
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(
        mime: metaData.contentType ?? 'audio', url: downloadUrl.toString());
  }

  Future<List<VendorCategoryModel>> getCuisines() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery = await firestore
        .collection(VENDORS_CATEGORIES)
        .where('publish', isEqualTo: true)
        .get();
    debugPrint(
        '🔥 getCuisines() QUERY: Fetched ${cuisinesQuery.docs.length} documents from Firestore');
    await Future.forEach(cuisinesQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    debugPrint(
        '🔥 getCuisines() RESULT: Successfully parsed ${cuisines.length} categories:');
    for (int i = 0; i < cuisines.length; i++) {
      debugPrint('  [$i] id="${cuisines[i].id}" title="${cuisines[i].title}"');
    }
    return cuisines;
  }

  // StreamController<List<VendorModel>>? vendorStreamController;
  //
  // Stream<List<VendorModel>> getVendors1({String? path}) async* {
  //   vendorStreamController = StreamController<List<VendorModel>>.broadcast();
  //   List<VendorModel> vendors = [];
  //   try {
  //     var collectionReference = (path == null || path.isEmpty) ? firestore.collection(VENDORS) : firestore.collection(VENDORS).where("enabledDiveInFuture", isEqualTo: true);
  //     GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosition.location!.location!.latitude, longitude: MyAppState.selectedPosition.location!.location!.longitude);
  //     String field = 'g';
  //     Stream<List<DocumentSnapshot>> stream = geo.collection(collectionRef: collectionReference).within(center: center, radius: radiusValue, field: field, strictMode: true);
  //
  //     stream.listen((List<DocumentSnapshot> documentList) {
  //       // doSomething()
  //       documentList.forEach((DocumentSnapshot document) {
  //         final data = document.data() as Map<String, dynamic>;
  //         vendors.add(VendorModel.fromJson(data));
  //       });
  //       if (!vendorStreamController!.isClosed) {
  //         vendorStreamController!.add(vendors);
  //       }
  //     });
  //   } catch (e) {
  //     print('FavouriteModel $e');
  //   }
  //   yield* vendorStreamController!.stream;
  // }

  closeVendorStream() {
    if (allResaturantStreamController != null) {
      allResaturantStreamController!.close();
    }
  }

  /// Fetches daily acceptance rate from vendors/{vendorId}/dailyMetrics.
  /// Returns map of date (yyyy-MM-dd) to acceptance rate 0-100.
  static Future<Map<String, double>> getVendorDailyAcceptanceRates(
    String vendorId, {
    int lastDays = 30,
  }) async {
    final result = <String, double>{};
    final now = DateTime.now();
    for (var i = 0; i < lastDays; i++) {
      final d = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final doc = await FirebaseFirestore.instance
          .collection(VENDORS)
          .doc(vendorId)
          .collection('dailyMetrics')
          .doc(dateStr)
          .get();
      if (doc.exists && doc.data() != null) {
        final rate = doc.data()!['acceptanceRate'];
        if (rate != null) {
          result[dateStr] = (rate is num) ? rate.toDouble() : 0.0;
        }
      }
    }
    return result;
  }

  /// Returns similar vendors (same category) sorted by acceptance rate desc.
  static Future<List<VendorModel>> getSimilarVendors(
    String excludeVendorId,
    String? categoryId,
    {int limit = 3}
  ) async {
    final all = await FirebaseFirestore.instance
        .collection(VENDORS)
        .limit(100)
        .get();
    final list = <VendorModel>[];
    for (final doc in all.docs) {
      if (doc.id == excludeVendorId) continue;
      try {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final v = VendorModel.fromJson(data);
        if (v.id.isEmpty) continue;
        if (categoryId != null &&
            categoryId.isNotEmpty &&
            v.categoryID != categoryId) {
          continue;
        }
        list.add(v);
      } catch (_) {}
    }
    list.sort((a, b) {
      final ra = a.acceptanceRate ?? 0;
      final rb = b.acceptanceRate ?? 0;
      return rb.compareTo(ra);
    });
    return list.take(limit).toList();
  }

  Future<List<VendorModel>> getVendors() async {
    List<VendorModel> vendors = [];
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(VENDORS).limit(200).get();
    await Future.forEach(vendorsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendors.add(VendorModel.fromJson(document.data()));
        print("*-*-/*-*-" + document["title"].toString());
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return vendors;
  }

  StreamSubscription? ordersStreamSub;
  StreamController<List<OrderModel>>? ordersStreamController;

  Stream<List<OrderModel>> getOrders(String userID) async* {
    print('🔍 FirebaseHelper.getOrders: Starting with userID: $userID');
    List<OrderModel> orders = [];
    ordersStreamController = StreamController();
    ordersStreamSub = firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: userID)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((onData) async {
      print(
          '🔍 FirebaseHelper.getOrders: Received ${onData.docs.length} documents from Firestore');
      orders.clear();
      int successCount = 0;
      int errorCount = 0;

      await Future.forEach(onData.docs,
          (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          print('🔍 Processing order document: ${element.id}');
          final data = element.data();
          print('🔍 Document status: ${data['status']}');
          print('🔍 Document authorID: ${data['authorID']}');

          OrderModel orderModel = OrderModel.fromJson(data);
          if (!orders.contains(orderModel)) {
            orders.add(orderModel);
            successCount++;
            print(
                '✅ Successfully parsed order: ${orderModel.id} - Status: ${orderModel.status}');
          } else {
            print('⚠️ Duplicate order found: ${orderModel.id}');
          }
        } catch (e, s) {
          errorCount++;
          print('❌ Parse error for ${element.id}: $e');
          print('❌ Stack trace: $s');
          final data = element.data();
          print(
              '❌ Failed document - Status: ${data['status']}, AuthorID: ${data['authorID']}');

          // Try to identify the specific field causing issues
          try {
            print('❌ Testing individual fields:');
            print('  - products: ${data['products']?.length ?? 0} items');
            print('  - vendor: ${data['vendor'] != null ? 'exists' : 'null'}');
            print('  - author: ${data['author'] != null ? 'exists' : 'null'}');
            print(
                '  - address: ${data['address'] != null ? 'exists' : 'null'}');
            print(
                '  - discount: ${data['discount']} (${data['discount'].runtimeType})');
            print(
                '  - takeAway: ${data['takeAway']} (${data['takeAway']?.runtimeType})');
          } catch (debugError) {
            print('❌ Error during field debugging: $debugError');
          }
        }
      });

      print(
          '🔍 FirebaseHelper.getOrders: Processing complete - Success: $successCount, Errors: $errorCount, Total orders: ${orders.length}');
      ordersStreamController!.sink.add(orders);
    }, onError: (error) {
      print('❌ FirebaseHelper.getOrders: Stream error: $error');
      ordersStreamController!.addError(error);
    });
    yield* ordersStreamController!.stream;
  }

  Stream<List<BookTableModel>> getBookingOrders(
      String userID, bool isUpComing) async* {
    List<BookTableModel> orders = [];

    if (isUpComing) {
      StreamController<List<BookTableModel>> upcomingordersStreamController =
          StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isGreaterThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs,
            (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        upcomingordersStreamController.sink.add(orders);
      });
      yield* upcomingordersStreamController.stream;
    } else {
      StreamController<List<BookTableModel>> bookedordersStreamController =
          StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isLessThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs,
            (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        bookedordersStreamController.sink.add(orders);
      });
      yield* bookedordersStreamController.stream;
    }
  }

  closeOrdersStream() {
    if (ordersStreamSub != null) {
      ordersStreamSub!.cancel();
    }
    if (ordersStreamController != null) {
      ordersStreamController!.close();
    }
  }

  Future<void> setFavouriteRestaurant(FavouriteModel favouriteModel) async {
    await firestore
        .collection(FavouriteRestaurant)
        .add(favouriteModel.toJson())
        .then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  void removeFavouriteRestaurant(FavouriteModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteRestaurant)
        .where("restaurant_id", isEqualTo: favouriteModel.restaurantId)
        .get()
        .then((value) {
      value.docs.forEach((element) {
        FirebaseFirestore.instance
            .collection(FavouriteRestaurant)
            .doc(element.id)
            .delete()
            .then((value) {
          print("Success!");
        });
      });
    });
  }

  StreamController<List<VendorModel>>? allResaturantStreamController;

  Stream<List<VendorModel>> getAllRestaurants({String? path}) async* {
    allResaturantStreamController =
        StreamController<List<VendorModel>>.broadcast();
    List<VendorModel> vendors = [];

    try {
      var collectionReference = (path == null || path.isEmpty)
          ? firestore.collection(VENDORS)
          : firestore
              .collection(VENDORS)
              .where("enabledDiveInFuture", isEqualTo: true);
      GeoFirePoint center = geo.point(
          latitude: MyAppState.selectedPosition.location!.latitude,
          longitude: MyAppState.selectedPosition.location!.longitude);

      String field = 'g';
      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(
              center: center,
              radius: radiusValue,
              field: field,
              strictMode: true);

      stream.listen((List<DocumentSnapshot> documentList) {
        if (documentList.isEmpty) {
          allResaturantStreamController!.close();
          return;
        }

        final userLocation = MyAppState.selectedPosition.location;
        if (userLocation == null) {
          for (var document in documentList) {
            final data = document.data() as Map<String, dynamic>;
            vendors.add(VendorModel.fromJson(data));
          }
          allResaturantStreamController!.add(vendors);
          return;
        }

        final userLat = userLocation.latitude;
        final userLng = userLocation.longitude;
        final List<VendorModel> list = [];
        for (var document in documentList) {
          final data = document.data() as Map<String, dynamic>;
          list.add(VendorModel.fromJson(data));
        }
        list.sort((VendorModel a, VendorModel b) {
          final distA = Geolocator.distanceBetween(
            userLat,
            userLng,
            a.latitude,
            a.longitude,
          );
          final distB = Geolocator.distanceBetween(
            userLat,
            userLng,
            b.latitude,
            b.longitude,
          );
          return distA.compareTo(distB);
        });
        vendors
          ..clear()
          ..addAll(list);
        allResaturantStreamController!.add(vendors);
      });
    } catch (e) {
      print('FavouriteModel $e');
    }

    yield* allResaturantStreamController!.stream;
  }

  StreamController<List<VendorModel>>? allCategoryResaturantStreamController;

  Stream<List<VendorModel>> getCategoryRestaurants(String categoryId) async* {
    // Create a new StreamController for each category call to avoid overwriting
    final categoryStreamController =
        StreamController<List<VendorModel>>.broadcast();
    List<VendorModel> vendors = [];

    try {
      var collectionReference = firestore
          .collection(VENDORS)
          .where('categoryID', isEqualTo: categoryId);

      GeoFirePoint center = geo.point(
          latitude: MyAppState.selectedPosition.location!.latitude,
          longitude: MyAppState.selectedPosition.location!.longitude);

      debugPrint(
          '📍 getCategoryRestaurants(categoryId="$categoryId"): Starting query with location filter (radius=$radiusValue km)');

      String field = 'g';
      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(
              center: center,
              radius: radiusValue,
              field: field,
              strictMode: true);

      stream.listen((List<DocumentSnapshot> documentList) {
        if (documentList.isEmpty) {
          debugPrint(
              '❌ getCategoryRestaurants(categoryId="$categoryId"): NO restaurants found within radius $radiusValue km - closing stream');
          categoryStreamController.close();
          return;
        }

        // Reset vendors list for each emission to avoid duplicates
        vendors.clear();
        for (var document in documentList) {
          final data = document.data() as Map<String, dynamic>;
          vendors.add(VendorModel.fromJson(data));
        }
        debugPrint(
            '✅ getCategoryRestaurants(categoryId="$categoryId"): Found ${vendors.length} restaurants within radius, emitting stream');
        categoryStreamController
            .add(vendors.take(20).toList()); // Limit for low-memory devices
      });
    } catch (e) {
      debugPrint(
          '❌ getCategoryRestaurants(categoryId="$categoryId") ERROR: $e');
      print('FavouriteModel $e');
      categoryStreamController.close();
    }

    yield* categoryStreamController.stream;
  }

  /// Non-geo fallback for category restaurants when stream returns empty.
  Future<List<VendorModel>> getCategoryRestaurantsPaginated(
    String categoryId, {
    int limit = 20,
  }) async {
    try {
      final snapshot = await firestore
          .collection(VENDORS)
          .where('categoryID', isEqualTo: categoryId)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => VendorModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('getCategoryRestaurantsPaginated error: $e');
      return [];
    }
  }

  StreamController<List<VendorModel>>? newArrivalStreamController;

  Stream<List<VendorModel>> getVendorsForNewArrival({String? path}) async* {
    List<VendorModel> vendors = [];

    newArrivalStreamController =
        StreamController<List<VendorModel>>.broadcast();
    var collectionReference = (path == null || path.isEmpty)
        ? firestore.collection(VENDORS)
        : firestore
            .collection(VENDORS)
            .where("enabledDiveInFuture", isEqualTo: true);
    GeoFirePoint center = geo.point(
        latitude: MyAppState.selectedPosition.location!.latitude,
        longitude: MyAppState.selectedPosition.location!.longitude);
    String field = 'g';
    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(
            center: center,
            radius: radiusValue,
            field: field,
            strictMode: true);
      stream.listen((List<DocumentSnapshot> documentList) {
        vendors.clear();
        for (final document in documentList) {
          final data = document.data() as Map<String, dynamic>;
          vendors.add(VendorModel.fromJson(data));
        }
        // Sort by distance so Nearby Restaurants shows nearest first
        final loc = MyAppState.selectedPosition.location;
        if (loc != null && vendors.length > 1) {
          vendors.sort((VendorModel a, VendorModel b) {
            final distA = Geolocator.distanceBetween(
              loc.latitude, loc.longitude, a.latitude, a.longitude,
            );
            final distB = Geolocator.distanceBetween(
              loc.latitude, loc.longitude, b.latitude, b.longitude,
            );
            return distA.compareTo(distB);
          });
        }
        if (!newArrivalStreamController!.isClosed) {
          newArrivalStreamController!
              .add(vendors.take(20).toList()); // Limit for low-memory devices
        }
      });

    yield* newArrivalStreamController!.stream;
  }

  closeNewArrivalStream() {
    if (newArrivalStreamController != null) {
      newArrivalStreamController!.close();
    }
  }

  /// Stream of newest restaurants by createdAt (for "New Restaurants" section).
  Stream<List<VendorModel>> getNewestRestaurantsStream({int limit = 15}) {
    return firestore
        .collection(VENDORS)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();
              if (data != null) return VendorModel.fromJson(data);
            } catch (_) {}
            return null;
          })
          .whereType<VendorModel>()
          .toList();
    });
  }

  late StreamController<List<VendorModel>> cusionStreamController;

  Stream<List<VendorModel>> getVendorsByCuisineID(String cuisineID,
      {bool? isDinein}) async* {
    await getRestaurantNearBy();
    cusionStreamController = StreamController<List<VendorModel>>.broadcast();
    List<VendorModel> vendors = [];
    var collectionReference = isDinein!
        ? firestore
            .collection(VENDORS)
            .where('categoryID', isEqualTo: cuisineID)
            .where("enabledDiveInFuture", isEqualTo: true)
        : firestore
            .collection(VENDORS)
            .where('categoryID', isEqualTo: cuisineID);
    GeoFirePoint center = geo.point(
        latitude: MyAppState.selectedPosition.location!.latitude,
        longitude: MyAppState.selectedPosition.location!.longitude);
    String field = 'g';
    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(
            center: center,
            radius: radiusValue,
            field: field,
            strictMode: true);
    stream.listen((List<DocumentSnapshot> documentList) {
      Future.forEach(documentList, (DocumentSnapshot element) {
        final data = element.data() as Map<String, dynamic>;
        vendors.add(VendorModel.fromJson(data));
        cusionStreamController.add(vendors);
      });
      cusionStreamController.close();
    });

    yield* cusionStreamController.stream;
  }

  static Future<String> getplaceholderimage() async {
    try {
      DocumentSnapshot snap = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('placeholderImage')
          .get();

      if (snap.exists && snap.data() != null) {
        var data = snap.data() as Map<String, dynamic>;
        if (data['url'] != null && data['url'] is String) {
          return data['url'];
        }
      }
    } catch (e) {
      debugPrint("getplaceholderimage error: $e");
    }

    // fallback to Firebase Storage placeholder from lalago-v2 project with access token
    return 'https://firebasestorage.googleapis.com/v0/b/lalago-v2.firebasestorage.app/o/images%2Fplace_holder_offer.png?alt=media&token=e8e7233b-8df2-4cd6-be48-6bf067550324';
  }

  Future<CurrencyModel?> getCurrency() async {
    CurrencyModel? currencyModel;
    await firestore
        .collection(Currency)
        .where("isActive", isEqualTo: true)
        .get()
        .then((value) {
      if (value.docs.isNotEmpty) {
        currencyModel = CurrencyModel.fromJson(value.docs.first.data());
      }
    });
    return currencyModel;
  }

  Future<List<OfferModel>> getPublicCoupons() async {
    List<OfferModel> coupons = [];

    try {
      print('Starting Firestore Query to fetch public coupons...');

      // Query Firestore
      QuerySnapshot<Map<String, dynamic>> couponsQuery = await firestore
          .collection(COUPON)
          .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
          .where("isEnabled", isEqualTo: true)
          .where("isPublic", isEqualTo: true)
          .get();

      print('Total Documents Fetched: ${couponsQuery.docs.length}');

      // Process Each Document
      for (var document in couponsQuery.docs) {
        print('Processing Document ID: ${document.id}');
        print('Raw Document Data: ${document.data()}');

        try {
          // Check for valid data
          if (document.exists && document.data().isNotEmpty) {
            var offer = OfferModel.fromJson(document.data());
            coupons.add(offer);
            print('Successfully Parsed OfferModel: ${offer.restaurantId}');
          } else {
            print('Document ${document.id} is empty or invalid.');
          }
        } catch (e) {
          print('Error parsing coupon document ${document.id}: $e');
        }
      }

      print('Total Valid Coupons Added: ${coupons.length}');
    } catch (e) {
      print('Error fetching public coupons: $e');
    }

    return coupons;
  }

  Future<List<OfferModel>> getAllCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery = await firestore
        .collection(COUPON)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .where("isEnabled", isEqualTo: true)
        .get();
    await Future.forEach(couponsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<StoryModel>> getStory() async {
    List<StoryModel> story = [];
    QuerySnapshot<Map<String, dynamic>> storyQuery =
        await firestore.collection(STORY).get();
    await Future.forEach(storyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        story.add(StoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return story;
  }

  Future<int> countVendorProductsByVendorIdOnly(String vendorID) async {
    final q = firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        .limit(101);
    final snap = await q.get();
    return snap.docs.length;
  }

  /// Fallback when publish filter returns 0 but products exist (e.g. publish
  /// false or missing). Queries by vendorID only. Uses documentId for ordering
  /// so docs without createdAt are included.
  Future<ProductPageResult> getVendorProductsVendorIdOnly(
    String vendorID, {
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    int limit = 20,
  }) async {
    List<ProductModel> products = [];
    Query<Map<String, dynamic>> q = firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        .orderBy(FieldPath.documentId);
    if (lastDocument != null) {
      q = q.startAfterDocument(lastDocument);
    }
    q = q.limit(limit);
    final productsQuery = await q.get();
    for (final document in productsQuery.docs) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FireStoreUtils.getVendorProducts Parse error $e');
        }
      }
    }
    final lastDoc =
        productsQuery.docs.isNotEmpty ? productsQuery.docs.last : null;
    return ProductPageResult(products, lastDoc);
  }

  Future<ProductPageResult> getVendorProductsTakeAWay(
    String vendorID, {
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    int limit = 20,
  }) async {
    List<ProductModel> products = [];
    Query<Map<String, dynamic>> q = firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        .where('publish', isEqualTo: true)
        .orderBy('createdAt', descending: true);
    if (lastDocument != null) {
      q = q.startAfterDocument(lastDocument);
    }
    q = q.limit(limit);
    final productsQuery = await q.get();
    for (final document in productsQuery.docs) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FireStoreUtils.getVendorProducts Parse error $e');
        }
      }
    }
    final lastDoc =
        productsQuery.docs.isNotEmpty ? productsQuery.docs.last : null;
    return ProductPageResult(products, lastDoc);
  }

  Future<ProductPageResult> getVendorProductsDelivery(
    String vendorID, {
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    int limit = 20,
  }) async {
    List<ProductModel> products = [];
    Query<Map<String, dynamic>> q = firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        .where('publish', isEqualTo: true)
        .orderBy('createdAt', descending: true);
    if (lastDocument != null) {
      q = q.startAfterDocument(lastDocument);
    }
    q = q.limit(limit);
    final productsQuery = await q.get();
    for (final document in productsQuery.docs) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FireStoreUtils.getVendorProducts Parse error $e');
        }
      }
    }
    final lastDoc =
        productsQuery.docs.isNotEmpty ? productsQuery.docs.last : null;
    return ProductPageResult(products, lastDoc);
  }

  Future<List<OfferModel>> getOfferByVendorID(String vendorID) async {
    List<OfferModel> offers = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(COUPON)
        .where("resturant_id", isEqualTo: vendorID)
        .where("isEnabled", isEqualTo: true)
        .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(bannerHomeQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FireStoreUtils.getOfferByVendorID Parse error $e');
        }
      }
    });
    return offers;
  }

  Future<VendorCategoryModel?> getVendorCategoryById(
      String vendorCategoryID) async {
    VendorCategoryModel? vendorCategoryModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(VENDORS_CATEGORIES)
        .where('id', isEqualTo: vendorCategoryID)
        .where('publish', isEqualTo: true)
        .get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        vendorCategoryModel =
            VendorCategoryModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FireStoreUtils.getVendorCategoryById Parse error $e');
      }
    }
    return vendorCategoryModel;
  }

  /// Fetches multiple categories by ID in batch. Firestore whereIn max is 30.
  Future<List<VendorCategoryModel>> getVendorCategoriesByIds(
    List<String> categoryIds,
  ) async {
    if (categoryIds.isEmpty) return [];
    const chunkSize = 30;
    final List<VendorCategoryModel> result = [];
    final Map<String, int> orderMap = {
      for (var i = 0; i < categoryIds.length; i++) categoryIds[i]: i,
    };
    for (var i = 0; i < categoryIds.length; i += chunkSize) {
      final chunk = categoryIds
          .skip(i)
          .take(chunkSize)
          .toList();
      final query = await firestore
          .collection(VENDORS_CATEGORIES)
          .where('id', whereIn: chunk)
          .where('publish', isEqualTo: true)
          .get();
      for (final doc in query.docs) {
        try {
          result.add(VendorCategoryModel.fromJson(doc.data()));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('getVendorCategoriesByIds Parse error $e');
          }
        }
      }
    }
    result.sort(
      (a, b) => (orderMap[a.id] ?? 0).compareTo(orderMap[b.id] ?? 0),
    );
    return result;
  }

  Future<VendorModel> getVendorByVendorID(String vendorID) async {
    late VendorModel vendor;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(VENDORS)
        .where('id', isEqualTo: vendorID)
        .get();
    try {
      if (vendorsQuery.docs.length > 0) {
        vendor = VendorModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return vendor;
  }

  Future<List<RatingModel>> getReviewsbyVendorID(String vendorId) async {
    List<RatingModel> vendorreview = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('VendorId', isEqualTo: vendorId)
        // .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(vendorsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      print(document);
      try {
        vendorreview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getOrders Parse error ${document.id} $e');
      }
    });
    return vendorreview;
  }

  Future<ProductModel> getProductByProductID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(PRODUCTS)
        .where('id', isEqualTo: productId)
        .where('publish', isEqualTo: true)
        .get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  Future<VendorCategoryModel?> getVendorCategoryByCategoryId(
      String vendorCategoryID) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore
        .collection(VENDORS_CATEGORIES)
        .doc(vendorCategoryID)
        .get();
    if (documentReference.data() != null && documentReference.exists) {
      print("dataaaaaa aaa ");
      return VendorCategoryModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<ReviewAttributeModel?> getVendorReviewAttribute(
      String attrubuteId) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference =
        await firestore.collection(REVIEW_ATTRIBUTES).doc(attrubuteId).get();
    if (documentReference.data() != null && documentReference.exists) {
      print("dataaaaaa aaa ");
      return ReviewAttributeModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  static Future<RatingModel?> updateReviewbyId(
      RatingModel ratingproduct) async {
    return await firestore
        .collection(Order_Rating)
        .doc(ratingproduct.id)
        .set(ratingproduct.toJson())
        .then((document) {
      return ratingproduct;
    });
  }

  static Future addRestaurantInbox(InboxModel inboxModel) async {
    return await firestore
        .collection("chat_restaurant")
        .doc(inboxModel.orderId)
        .set(inboxModel.toJson())
        .then((document) {
      return inboxModel;
    });
  }

  static Future<void> addRestaurantChat(ConversationModel conversation) async {
    await FirebaseFirestore.instance
        .collection("chat_restaurant")
        .doc(conversation.orderId)
        .collection("thread")
        .doc(conversation.id)
        .set({
      "id": conversation.id,
      "message": conversation.message,
      "senderId": conversation.senderId,
      "receiverId": conversation.receiverId,
      "createdAt": conversation.createdAt,
      "url": conversation.url != null ? conversation.url!.toJson() : null,
      "orderId": conversation.orderId,
      "messageType": conversation.messageType,
      "videoThumbnail": conversation.videoThumbnail,
      "isRead": false, // ✅ THIS LINE ADDS isRead TO FIRESTORE
    });
  }

  static Future addDriverInbox(InboxModel inboxModel) async {
    return await firestore
        .collection("chat_driver")
        .doc(inboxModel.orderId)
        .set(inboxModel.toJson())
        .then((document) {
      return inboxModel;
    });
  }

  static Future addDriverChat(ConversationModel conversationModel) async {
    return await firestore
        .collection("chat_driver")
        .doc(conversationModel.orderId)
        .collection("thread")
        .doc(conversationModel.id)
        .set(conversationModel.toJson())
        .then((document) {
      return conversationModel;
    });
  }

  Future<List<FavouriteModel>> getFavouriteRestaurant(String userId) async {
    List<FavouriteModel> favouriteItem = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(FavouriteRestaurant)
        .where('user_id', isEqualTo: userId)
        .get();
    await Future.forEach(vendorsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        favouriteItem.add(FavouriteModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return favouriteItem;
  }

  Future<OrderModel> placeOrder(OrderModel orderModel) async {
    DocumentReference documentReference =
        firestore.collection(ORDERS).doc(UserPreference.getOrderId());
    orderModel.id = documentReference.id;
    final json = orderModel.toJson();
    json['sessionId'] = SessionManager.sessionId;
    await documentReference.set(json);

    // Reserve manual coupon if one was applied
    final manualCouponId = orderModel.manualCouponId;
    if (manualCouponId != null && manualCouponId.isNotEmpty) {
      await CouponService.reserveCoupon(manualCouponId);
    }

    // Process order completion with backend integration
    if (orderModel.authorID != null && orderModel.authorID!.isNotEmpty) {
      await processOrderCompletionWithBackend(
          orderModel.id, orderModel.authorID!);
    }

    return orderModel;
  }

  /// Processes order completion with backend integration
  /// Process referral rewards when order is completed
  static Future<void> processReferralRewardsOnOrderCompletion(
      String orderId, String userId) async {
    try {
      // Get the order to check if it's the first completed order
      final orderDoc = await firestore.collection(ORDERS).doc(orderId).get();
      if (!orderDoc.exists) {
        log('Order not found: $orderId');
        return;
      }

      final orderData = orderDoc.data();
      if (orderData == null) {
        log('Order data is null: $orderId');
        return;
      }

      final orderStatus = orderData['status'] as String? ?? '';

      // Only process if order is completed
      if (orderStatus != ORDER_STATUS_COMPLETED) {
        return;
      }

      // Get user to check if this is their first completed order
      final user = await getCurrentUser(userId);
      if (user == null) {
        log('User not found: $userId');
        return;
      }

      // Check if this is the user's first completed order
      final completedOrders = await firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: userId)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .get();

      final isFirstCompletedOrder = completedOrders.docs.length == 1 &&
          completedOrders.docs.first.id == orderId;

      if (isFirstCompletedOrder && !user.hasCompletedFirstOrder) {
        // Mark first order as completed
        await firestore.collection(USERS).doc(userId).update({
          'hasCompletedFirstOrder': true,
        });

        // Process referral reward if user was referred
        if (user.referredBy != null && user.referredBy!.isNotEmpty) {
          await ReferralRewardService.processReferralReward(
            refereeUserId: userId,
            orderId: orderId,
          );
        }
      }
    } catch (e, stackTrace) {
      log('Error processing referral rewards: $e\n$stackTrace');
    }
  }

  static Future<void> processOrderCompletionWithBackend(
      String orderId, String userId) async {
    try {
      // Check if this order has first-order coupon applied
      final orderDoc = await firestore.collection(ORDERS).doc(orderId).get();
      if (orderDoc.exists) {
        final orderData = orderDoc.data();
        if (orderData != null) {
          final appliedCouponId = orderData['appliedCouponId'] as String?;
          if (appliedCouponId == 'FIRST_ORDER_AUTO') {
            // Update hasOrderedBefore when first-order coupon order is completed
            await _updateHasOrderedBefore(userId);
          }
        }
      }

      // Call backend to process rewards
      Map<String, dynamic>? result =
          await BackendService.processOrderCompletion(orderId, userId);

      if (result != null) {
        print('✅ Order completion processed by backend: $result');

        // Update local user data if wallet was credited
        if (result['rewardApplied'] == true && MyAppState.currentUser != null) {
          // Refresh user data from Firebase
          User? updatedUser =
              await getCurrentUser(MyAppState.currentUser!.userID);
          if (updatedUser != null) {
            MyAppState.currentUser = updatedUser;
          }
        }
      } else {
        print('⚠️ Backend order completion failed, using fallback logic');
        // Fallback to client-side logic if needed
        await _processOrderCompletionFallback(orderId, userId);
      }
    } catch (e) {
      print('❌ Error in backend order completion: $e');
      // Fallback to client-side logic
      await _processOrderCompletionFallback(orderId, userId);
    }
  }

  /// Fallback order completion logic (client-side)
  static Future<void> _processOrderCompletionFallback(
      String orderId, String userId) async {
    try {
      User? user = await getCurrentUser(userId);
      if (user == null) return;

      // Check if this is the user's first completed order
      final completedOrders = await firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: userId)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .get();

      final isFirstCompletedOrder = completedOrders.docs.length == 1 &&
          completedOrders.docs.first.id == orderId;

      // Mark first order as completed if this is the first completed order
      if (isFirstCompletedOrder && !user.hasCompletedFirstOrder) {
        user.hasCompletedFirstOrder = true;
        await updateCurrentUser(user);
        print('✅ Fallback: Marked first order as completed');

        // Process referral reward if user was referred
        if (user.referredBy != null && user.referredBy!.isNotEmpty) {
          await ReferralRewardService.processReferralReward(
            refereeUserId: userId,
            orderId: orderId,
          );
        }
      }
    } catch (e) {
      print('❌ Error in fallback order completion: $e');
    }
  }

  Future<GiftCardsOrderModel> placeGiftCardOrder(
      GiftCardsOrderModel giftCardsOrderModel) async {
    await firestore
        .collection(GIFT_PURCHASES)
        .doc(giftCardsOrderModel.id)
        .set(giftCardsOrderModel.toJson());
    return giftCardsOrderModel;
  }

  Future<List<GiftCardsOrderModel>> getGiftHistory() async {
    List<GiftCardsOrderModel> giftCardsOrderList = [];
    await firestore
        .collection(GIFT_PURCHASES)
        .where("userid", isEqualTo: MyAppState.currentUser!.userID)
        .get()
        .then((value) {
      for (var element in value.docs) {
        GiftCardsOrderModel giftCardsOrderModel =
            GiftCardsOrderModel.fromJson(element.data());
        giftCardsOrderList.add(giftCardsOrderModel);
      }
    });
    return giftCardsOrderList;
  }

  Future<GiftCardsOrderModel?> checkRedeemCode(String giftCode) async {
    GiftCardsOrderModel? giftCardsOrderModel;
    await firestore
        .collection(GIFT_PURCHASES)
        .where("giftCode", isEqualTo: giftCode)
        .get()
        .then((value) {
      if (value.docs.isNotEmpty) {
        giftCardsOrderModel =
            GiftCardsOrderModel.fromJson(value.docs.first.data());
      }
    });
    return giftCardsOrderModel;
  }

  Future<OrderModel> placeOrderWithTakeAWay(OrderModel orderModel) async {
    DocumentReference documentReference;
    if (orderModel.id.isEmpty) {
      documentReference = firestore.collection(ORDERS).doc();
      orderModel.id = documentReference.id;
    } else {
      documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    }
    final json = orderModel.toJson();
    json['sessionId'] = SessionManager.sessionId;
    await documentReference.set(json);
    return orderModel;
  }

  Future<BookTableModel> bookTable(BookTableModel orderModel) async {
    DocumentReference documentReference =
        firestore.collection(ORDERS_TABLE).doc();
    orderModel.id = documentReference.id;
    await documentReference.set(orderModel.toJson());
    return orderModel;
  }

  Future<String> createPautosOrder(PautosOrderModel order) async {
    final ref = firestore.collection(PAUTOS_ORDERS).doc();
    order.id = ref.id;
    await ref.set(order.toJson());
    return order.id;
  }

  Stream<List<PautosOrderModel>> getPautosOrdersByAuthor(String authorID) {
    return firestore
        .collection(PAUTOS_ORDERS)
        .where('authorID', isEqualTo: authorID)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final data = d.data();
              data['id'] = d.id;
              return PautosOrderModel.fromJson(data);
            })
            .toList());
  }

  Stream<PautosOrderModel?> getPautosOrderStream(String orderId) {
    return firestore
        .collection(PAUTOS_ORDERS)
        .doc(orderId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return null;
          final data = doc.data()!;
          data['id'] = doc.id;
          return PautosOrderModel.fromJson(data);
        });
  }

  static createOrder() async {
    DocumentReference documentReference = firestore.collection(ORDERS).doc();
    final orderId = documentReference.id;
    UserPreference.setOrderId(orderId: orderId);
  }

  static Future createPaymentId() async {
    DocumentReference documentReference = firestore.collection(Wallet).doc();
    final paymentId = documentReference.id;
    UserPreference.setPaymentId(paymentId: paymentId);
    return paymentId;
  }

  static Future<List<TopupTranHistoryModel>> getTopUpTransaction() async {
    final userId = MyAppState.currentUser!.userID; //UserPreference.getUserId();
    List<TopupTranHistoryModel> topUpHistoryList = [];
    QuerySnapshot<Map<String, dynamic>> documentReference = await firestore
        .collection(Wallet)
        .where('user_id', isEqualTo: userId)
        .get();
    await Future.forEach(documentReference.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        topUpHistoryList.add(TopupTranHistoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return topUpHistoryList;
  }

  static Future topUpWalletAmount(
      {String paymentMethod = "test",
      bool isTopup = true,
      required amount,
      required id,
      orderId = ""}) async {
    print("this is te payment id");
    print(id);
    print(MyAppState.currentUser!.userID);

    TopupTranHistoryModel historyModel = TopupTranHistoryModel(
        amount: amount,
        id: id,
        orderId: orderId,
        userId: MyAppState.currentUser!.userID,
        date: Timestamp.now(),
        isTopup: isTopup,
        paymentMethod: paymentMethod,
        paymentStatus: "success",
        transactionUser: "user");
    await firestore
        .collection(Wallet)
        .doc(id)
        .set(historyModel.toJson())
        .then((value) {
      firestore.collection(Wallet).doc(id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print("nato");
        print(documentData.data());
      });
    });

    return "updated Amount";
  }

  static Future updateWalletAmount({required amount}) async {
    dynamic walletAmount = 0;
    final userId = MyAppState.currentUser!.userID; //UserPreference.getUserId();
    await firestore.collection(USERS).doc(userId).get().then((value) async {
      DocumentSnapshot<Map<String, dynamic>> userDocument = value;
      if (userDocument.data() != null && userDocument.exists) {
        try {
          print(userDocument.data());
          User user = User.fromJson(userDocument.data()!);
          MyAppState.currentUser = user;
          print(user.lastName.toString() + "=====.....(user.wallet_amount");
          print("add ${user.lastName} + $amount");
          await firestore
              .collection(USERS)
              .doc(userId)
              .update({"wallet_amount": user.walletAmount + amount}).then(
                  (value) => print("north"));
          /*print(user.wallet_amount);


          walletAmount = user.wallet_amount! + amount;*/
          DocumentSnapshot<Map<String, dynamic>> newUserDocument =
              await firestore.collection(USERS).doc(userId).get();
          MyAppState.currentUser = User.fromJson(newUserDocument.data()!);
          print(MyAppState.currentUser);
        } catch (error) {
          print(error);
          if (error.toString() ==
              "Bad state: field does not exist within the DocumentSnapshotPlatform") {
            print("does not exist");
            //await firestore.collection(USERS).doc(userId).update({"wallet_amount": 0});
            //walletAmount = 0;
          } else {
            print("went wrong!!");
            walletAmount = "ERROR";
          }
        }
        print("data val");
        print(walletAmount);
        return walletAmount; //User.fromJson(userDocument.data()!);
      } else {
        return 0.111;
      }
    });
  }

  static sendTopUpMail(
      {required String amount,
      required String paymentMethod,
      required String tractionId}) async {
    EmailTemplateModel? emailTemplateModel =
        await FireStoreUtils.getEmailTemplates(walletTopup);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}",
        MyAppState.currentUser!.firstName + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll(
        "{date}", DateFormat('yyyy-MM-dd').format(Timestamp.now().toDate()));
    newString = newString.replaceAll("{amount}", amountShow(amount: amount));
    newString =
        newString.replaceAll("{paymentmethod}", paymentMethod.toString());
    newString = newString.replaceAll("{transactionid}", tractionId.toString());
    newString = newString.replaceAll("{newwalletbalance}.",
        amountShow(amount: MyAppState.currentUser!.walletAmount.toString()));
    await sendMail(
        subject: emailTemplateModel.subject,
        isAdmin: emailTemplateModel.isSendToAdmin,
        body: newString,
        recipients: [MyAppState.currentUser!.email]);
  }

  static sendOrderEmail({required OrderModel orderModel}) async {
    String firstHTML = """
       <table style="width: 100%; border-collapse: collapse; border: 1px solid rgb(0, 0, 0);">
    <thead>
        <tr>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Product Name<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Quantity<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Extra Item Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Total<br></th>
        </tr>
    </thead>
    <tbody>
    """;

    EmailTemplateModel? emailTemplateModel =
        await FireStoreUtils.getEmailTemplates(newOrderPlaced);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}",
        MyAppState.currentUser!.firstName + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{orderid}", orderModel.id);
    newString = newString.replaceAll("{date}",
        DateFormat('yyyy-MM-dd').format(orderModel.createdAt.toDate()));
    newString = newString.replaceAll(
      "{address}",
      '${orderModel.address!.getFullAddress()}',
    );
    newString = newString.replaceAll(
      "{paymentmethod}",
      orderModel.paymentMethod,
    );

    double deliveryCharge = 0.0;
    double total = 0.0;
    double specialDiscount = 0.0;
    double discount = 0.0;
    double taxAmount = 0.0;
    double tipValue = 0.0;
    String specialLabel =
        '(${orderModel.specialDiscount!['special_discount_label']}${orderModel.specialDiscount!['specialType'] == "amount" ? currencyModel!.symbol : "%"})';
    List<String> htmlList = [];

    if (orderModel.deliveryCharge != null) {
      deliveryCharge = double.parse(orderModel.deliveryCharge.toString());
    }
    if (orderModel.tipValue != null) {
      tipValue = double.parse(orderModel.tipValue.toString());
    }
    orderModel.products.forEach((element) {
      if (element.extras_price != null &&
          element.extras_price!.isNotEmpty &&
          double.parse(element.extras_price!) != 0.0) {
        total += element.quantity * double.parse(element.extras_price!);
      }
      total += element.quantity * double.parse(element.price);

      List<dynamic>? addon;
      final e = element.extras;
      if (e is List) {
        addon = e;
      } else if (e is String && e.isNotEmpty && e != '[]') {
        try {
          final decoded = jsonDecode(e);
          addon = decoded is List
              ? List<dynamic>.from(decoded)
              : [decoded];
        } catch (_) {
          addon = [e];
        }
      }
      String extrasDisVal = '';
      if (addon != null) {
        for (int i = 0; i < addon.length; i++) {
          extrasDisVal +=
              '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
        }
      }
      String product = """
        <tr>
            <td style="width: 20%; border-top: 1px solid rgb(0, 0, 0);">${element.name}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${element.quantity}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.extras_price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: ((element.quantity * double.parse(element.extras_price!) + (element.quantity * double.parse(element.price)))).toString())}</td>
        </tr>
        <tr>
            <td style="width: 20%;">${extrasDisVal.isEmpty ? "" : "Extra Item : $extrasDisVal"}</td>
        </tr>
    """;
      htmlList.add(product);
    });

    if (orderModel.specialDiscount!.isNotEmpty) {
      specialDiscount = double.parse(
          orderModel.specialDiscount!['special_discount'].toString());
    }

    if (orderModel.couponId != null && orderModel.couponId!.isNotEmpty) {
      discount = double.parse(orderModel.discount.toString());
    }

    List<String> taxHtmlList = [];
    if (taxList != null) {
      for (var element in taxList!) {
        taxAmount = taxAmount +
            calculateTax(
                amount: (total - discount - specialDiscount).toString(),
                taxModel: element);
        String taxHtml =
            """<span style="font-size: 1rem;">${element.title}: ${amountShow(amount: calculateTax(amount: (total - discount - specialDiscount).toString(), taxModel: element).toString())}${taxList!.indexOf(element) == taxList!.length - 1 ? "</span>" : "<br></span>"}""";
        taxHtmlList.add(taxHtml);
      }
    }

    var totalamount =
        orderModel.deliveryCharge == null || orderModel.deliveryCharge!.isEmpty
            ? total + taxAmount - discount - specialDiscount
            : total +
                taxAmount +
                double.parse(orderModel.deliveryCharge!) +
                double.parse(orderModel.tipValue!) -
                discount -
                specialDiscount;

    newString = newString.replaceAll(
        "{subtotal}", amountShow(amount: total.toString()));
    newString =
        newString.replaceAll("{coupon}", orderModel.couponId.toString());
    newString = newString.replaceAll(
        "{discountamount}", amountShow(amount: orderModel.discount.toString()));
    newString = newString.replaceAll("{specialcoupon}", specialLabel);
    newString = newString.replaceAll("{specialdiscountamount}",
        amountShow(amount: specialDiscount.toString()));
    newString = newString.replaceAll(
        "{shippingcharge}", amountShow(amount: deliveryCharge.toString()));
    newString = newString.replaceAll(
        "{tipamount}", amountShow(amount: tipValue.toString()));
    newString = newString.replaceAll(
        "{totalAmount}", amountShow(amount: totalamount.toString()));

    String tableHTML = htmlList.join();
    String lastHTML = "</tbody></table>";
    newString = newString.replaceAll(
        "{productdetails}", firstHTML + tableHTML + lastHTML);
    newString = newString.replaceAll("{taxdetails}", taxHtmlList.join());
    newString = newString.replaceAll("{newwalletbalance}.",
        amountShow(amount: MyAppState.currentUser!.walletAmount.toString()));

    String subjectNewString = emailTemplateModel.subject.toString();
    subjectNewString = subjectNewString.replaceAll("{orderid}", orderModel.id);
    await sendMail(
        subject: subjectNewString,
        isAdmin: emailTemplateModel.isSendToAdmin,
        body: newString,
        recipients: [MyAppState.currentUser!.email]);
  }

  /// Watches order status changes and automatically processes referral completion
  /// when an order is marked as completed for customers with pending referrals
  /// Also updates hasOrderedBefore when first-order coupon orders are completed
  /// Also finalizes manual coupon usage when order status changes
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrderStatus(
      String orderID) async* {
    yield* firestore
        .collection(ORDERS)
        .doc(orderID)
        .snapshots()
        .map((snapshot) {
      // Process referral completion when order status changes to completed
      if (snapshot.exists && snapshot.data() != null) {
        final orderData = snapshot.data()!;
        final status = orderData['status'] as String?;
        final authorID = orderData['authorID'] as String?;

        if (status == ORDER_STATUS_COMPLETED && authorID != null) {
          // Referral awarding is handled server-side (Cloud Function) to avoid
          // overlapping client transactions.

          // Update hasOrderedBefore if first-order coupon was applied
          final appliedCouponId = orderData['appliedCouponId'] as String?;
          if (appliedCouponId == 'FIRST_ORDER_AUTO') {
            _updateHasOrderedBefore(authorID);
          }

          // Finalize manual coupon usage if manual coupon was applied
          final manualCouponId = orderData['manualCouponId'] as String?;
          if (manualCouponId != null && manualCouponId.isNotEmpty) {
            CouponService.finalizeCouponUsage(manualCouponId, orderID, true);
          }
        } else if (status == ORDER_STATUS_CANCELLED ||
            status == ORDER_STATUS_REJECTED) {
          // Revert manual coupon usage if order was cancelled or rejected
          final manualCouponId = orderData['manualCouponId'] as String?;
          if (manualCouponId != null && manualCouponId.isNotEmpty) {
            CouponService.finalizeCouponUsage(manualCouponId, orderID, false);
          }
        }
      }
      return snapshot;
    });
  }

  /// Updates hasOrderedBefore to true for a user
  /// This is called when a first-order coupon order is completed
  static Future<void> _updateHasOrderedBefore(String userId) async {
    try {
      await firestore.collection(USERS).doc(userId).update({
        'hasOrderedBefore': true,
      });
      print('✅ Updated hasOrderedBefore to true for user: $userId');
    } catch (e) {
      print('❌ Error updating hasOrderedBefore: $e');
    }
  }

  /// compress image file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the image after
  /// being compressed(100 = max quality - 0 = low quality)
  /// @param file the image file that will be compressed
  /// @return File a new compressed file with smaller size
  static Future<File?> compressImage(File file) async {
    print('🔄 DEBUG: Starting image compression...');
    print('🔄 DEBUG: Original file path: ${file.path}');
    print('🔄 DEBUG: Original file exists: ${await file.exists()}');

    try {
      // Get original file size
      final originalSize = await file.length();
      print('🔄 DEBUG: Original file size: $originalSize bytes');

      XFile? compressedImage = await FlutterImageCompress.compressAndGetFile(
        file.path,
        "${file.path}_compressed.jpg",
        quality: 25,
      );

      if (compressedImage == null) {
        print('❌ DEBUG: Image compression failed - returned null');
        return null;
      }

      final compressedFile = File(compressedImage.path);
      final compressedSize = await compressedFile.length();
      final compressionRatio =
          ((originalSize - compressedSize) / originalSize * 100);

      print('✅ DEBUG: Image compression completed');
      print('✅ DEBUG: Compressed file path: ${compressedImage.path}');
      print('✅ DEBUG: Compressed file size: $compressedSize bytes');
      print(
          '✅ DEBUG: Compression ratio: ${compressionRatio.toStringAsFixed(2)}%');

      return compressedFile;
    } catch (e, stackTrace) {
      print('❌ DEBUG: Image compression error: $e');
      print('❌ DEBUG: Stack trace: $stackTrace');
      return null;
    }
  }

  /// compress video file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the video after
  /// being compressed
  /// @param file the video file that will be compressed
  /// @return File a new compressed file with smaller size
  Future<File> _compressVideo(File file) async {
    // Video compression is temporarily unavailable
    // Return original file as fallback
    return file;
  }

  static Future<dynamic> loginWithGoogle() async {
    try {
      // Configure GoogleSignIn with Web Client ID (required for Android release builds)
      // This prevents DEVELOPER_ERROR by ensuring proper OAuth client configuration
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: GOOGLE_SIGN_IN_WEB_CLIENT_ID,
        scopes: ['email', 'profile'],
      );
      GoogleSignInAccount? googleUser;
      try {
        googleUser = await googleSignIn.signIn();
      } on PlatformException catch (pe) {
        log("ERROR LOGINWITHGOOGLE: ${pe.toString()}");
        switch (pe.code) {
          case 'sign_in_canceled':
            return 'Google sign-in was cancelled.';
          case 'network_error':
            return 'Network error. Check your internet connection and try again.';
          case 'channel-error':
            return 'Google sign-in is not available on this platform or the plugin is not registered. Please run on Android/iOS and ensure Firebase is configured.';
          case 'sign_in_failed':
          case 'DEVELOPER_ERROR':
            // DEVELOPER_ERROR typically means SHA-1/SHA-256 mismatch or missing Web Client ID
            log("DEVELOPER_ERROR detected: This usually means SHA-1/SHA-256 fingerprints don't match Firebase Console. Please verify:");
            log("1. Release keystore SHA-1/SHA-256 are added to Firebase Console > Project Settings > Your App");
            log("2. google-services.json matches your package name: com.lalago.customer.android");
            log("3. Web Client ID (${GOOGLE_SIGN_IN_WEB_CLIENT_ID}) is correctly configured");
            return 'Google sign-in configuration error. Please contact support with error code: DEVELOPER_ERROR. Make sure SHA-1/SHA-256 fingerprints are registered in Firebase Console.';
          default:
            return 'Google sign-in failed: ${pe.code}';
        }
      }

      if (googleUser == null) {
        return 'Google sign-in was cancelled.';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null || googleAuth.accessToken == null) {
        return 'Missing Google auth token. Is Google provider enabled in Firebase?';
      }

      final auth.AuthCredential credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      auth.UserCredential authResult;
      try {
        authResult =
            await auth.FirebaseAuth.instance.signInWithCredential(credential);
      } on auth.FirebaseAuthException catch (fae) {
        switch (fae.code) {
          case 'account-exists-with-different-credential':
            return 'Account exists with different sign-in method.';
          case 'invalid-credential':
            return 'Invalid credential. Check SHA-1/SHA-256 in Firebase and rebuild the app.';
          case 'operation-not-allowed':
            return 'Google sign-in is disabled in Firebase Authentication.';
          case 'user-disabled':
            return 'This user has been disabled.';
          case 'invalid-provider-id':
            return 'Invalid provider configuration in Firebase.';
          default:
            return 'Firebase auth failed: ${fae.code}';
        }
      }

      User? user = await getCurrentUser(authResult.user?.uid ?? '');

      if (user != null && user.role == USER_ROLE_CUSTOMER) {
        user.role = USER_ROLE_CUSTOMER;
        user.email = authResult.user?.email ?? user.email;
        user.firstName = authResult.user?.displayName?.split(' ').first ?? '';
        user.lastName =
            (authResult.user?.displayName?.split(' ').skip(1).join(' ')) ?? '';
        user.profilePictureURL =
            authResult.user?.photoURL ?? user.profilePictureURL;

        // Ensure user has referral code via backend
        await _ensureReferralCodeAfterLogin(user);

        final updatedUser = await updateCurrentUser(user);
        unawaited(refreshFcmTokenForUser(user));
        return updatedUser;
      } else if (user == null) {
        final displayName = authResult.user?.displayName ?? '';
        final parts = displayName.split(' ');
        final String firstName = parts.isNotEmpty ? parts.first : '';
        final String lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';

        user = User(
          email: authResult.user?.email ?? '',
          firstName: firstName,
          lastName: lastName,
          profilePictureURL: authResult.user?.photoURL ?? '',
          userID: authResult.user?.uid ?? '',
          lastOnlineTimestamp: Timestamp.now(),
          active: true,
          role: USER_ROLE_CUSTOMER,
          fcmToken: '',
          phoneNumber: authResult.user?.phoneNumber ?? '',
          createdAt: Timestamp.now(),
          settings: UserSettings(),
        );
        String? errorMessage = await firebaseCreateNewUser(user, "");
        if (errorMessage == null) {
          unawaited(refreshFcmTokenForUser(user));
          return user;
        } else {
          return errorMessage;
        }
      } else {
        return 'notSignUp';
      }
    } catch (e, s) {
      print('loginWithGoogle error: $e $s');
      return 'Login failed, Please try again.';
    }
  }

  static Future<dynamic> loginWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = appleCredential.identityToken;
      final accessToken = appleCredential.authorizationCode;
      if (idToken == null || idToken.isEmpty || accessToken == null) {
        return 'Sign in with Apple failed: missing credentials.';
      }
      final auth.AuthCredential credential =
          auth.OAuthProvider('apple.com').credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      return await handleAppleLogin(credential, appleCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          return 'Apple sign-in was cancelled.';
        case AuthorizationErrorCode.notHandled:
          return 'Apple sign-in was not completed.';
        case AuthorizationErrorCode.notInteractive:
          return 'Apple sign-in is not available in this context.';
        case AuthorizationErrorCode.unknown:
          return e.message;
        case AuthorizationErrorCode.failed:
          return e.message;
        case AuthorizationErrorCode.invalidResponse:
          return 'Invalid response from Apple sign-in.';
      }
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_with_apple_not_available') {
        return 'Sign in with Apple is not available on this device.';
      }
      return e.message ?? "Couldn't sign in with Apple.";
    } catch (e, s) {
      print('loginWithApple error: $e $s');
      return "Couldn't sign in with Apple.";
    }
  }

  static Future<dynamic> handleAppleLogin(
    auth.AuthCredential credential,
    AuthorizationCredentialAppleID appleIdCredential,
  ) async {
    auth.UserCredential authResult =
        await auth.FirebaseAuth.instance.signInWithCredential(credential);
    User? user = await getCurrentUser(authResult.user?.uid ?? '');
    if (user != null) {
      user.role = USER_ROLE_CUSTOMER;
      await _ensureReferralCodeAfterLogin(user);
      final updatedUser = await updateCurrentUser(user);
      unawaited(refreshFcmTokenForUser(user));
      return updatedUser;
    } else {
      final email = appleIdCredential.email ??
          authResult.user?.email ??
          '';
      final givenName = appleIdCredential.givenName ?? '';
      final familyName = appleIdCredential.familyName ?? '';
      user = User(
          email: email,
          firstName: givenName,
          profilePictureURL: '',
          userID: authResult.user?.uid ?? '',
          lastOnlineTimestamp: Timestamp.now(),
          lastName: familyName,
          role: USER_ROLE_CUSTOMER,
          active: true,
          fcmToken: '',
          phoneNumber: '',
          createdAt: Timestamp.now(),
          settings: UserSettings());
      // Align with reference: update Firebase Auth displayName when fullName
      // is provided (first-time Apple sign-in only).
      if (givenName.isNotEmpty || familyName.isNotEmpty) {
        final displayName = '$givenName $familyName'.trim();
        try {
          await authResult.user?.updateDisplayName(displayName);
        } catch (_) {
          // Non-fatal; Firestore user still has firstName/lastName.
        }
      }
      String? errorMessage = await firebaseCreateNewUser(user, "");
      if (errorMessage == null) {
        unawaited(refreshFcmTokenForUser(user));
        return user;
      } else {
        return errorMessage;
      }
    }
  }

  /// Generates a unique referral code for a user
  static Future<String> _generateUniqueReferralCode(String userId) async {
    // Generate code from user ID hash (first 8 characters uppercase)
    String baseCode = userId
        .substring(0, userId.length > 8 ? 8 : userId.length)
        .toUpperCase();

    // Add random suffix to ensure uniqueness
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch % 10000;
    String suffix = random.toRadixString(36).toUpperCase().padLeft(4, '0');

    String referralCode = '$baseCode$suffix';

    // Check if code already exists, regenerate if needed
    int attempts = 0;
    while (attempts < 10) {
      final existing = await firestore
          .collection(REFERRAL)
          .where('referralCode', isEqualTo: referralCode)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        // Code is unique
        break;
      }

      // Regenerate with different suffix
      final newRandom =
          (DateTime.now().millisecondsSinceEpoch + attempts) % 10000;
      suffix = newRandom.toRadixString(36).toUpperCase().padLeft(4, '0');
      referralCode = '$baseCode$suffix';
      attempts++;
    }

    return referralCode;
  }

  /// Validates referral code and returns referrer user ID if valid
  static Future<String?> _validateReferralCode(String referralCode) async {
    try {
      // Check if referral code exists in REFERRAL collection
      final referralQuery = await firestore
          .collection(REFERRAL)
          .where('referralCode', isEqualTo: referralCode)
          .limit(1)
          .get();

      if (referralQuery.docs.isNotEmpty) {
        final referralData = referralQuery.docs.first.data();
        return referralData['id'] ?? referralQuery.docs.first.id;
      }

      return null;
    } catch (e) {
      log('Error validating referral code: $e');
      return null;
    }
  }

  /// save a new user document in the USERS table in firebase firestore
  /// returns an error message on failure or null on success
  static Future<String?> firebaseCreateNewUser(
      User user, String referralCode) async {
    try {
      // Generate unique referral code for new user if not exists
      if (user.referralCode == null || user.referralCode!.isEmpty) {
        user.referralCode = await _generateUniqueReferralCode(user.userID);
      }

      // Validate and process referral code if provided
      String? referrerId;
      if (referralCode.isNotEmpty && referralCode.trim().isNotEmpty) {
        referrerId = await _validateReferralCode(referralCode.trim());

        if (referrerId != null) {
          // Prevent self-referral
          if (referrerId == user.userID) {
            log('⚠️ Self-referral prevented');
          } else {
            // Set referredBy only if not already set (write-once)
            if (user.referredBy == null || user.referredBy!.isEmpty) {
              user.referredBy = referralCode.trim();
            }
          }
        } else {
          log('⚠️ Invalid referral code: $referralCode');
          // Allow signup to proceed even with invalid referral code
        }
      }

      // Initialize referral wallet amount
      user.referralWalletAmount = 0.0;
      user.hasCompletedFirstOrder = false;

      // Save user document
      await firestore.collection(USERS).doc(user.userID).set(user.toJson());

      // Create referral document for lookup
      ReferralModel referralModel = ReferralModel(
        id: user.userID,
        referralCode: user.referralCode,
        referralBy: user.referredBy,
      );
      await firestore
          .collection(REFERRAL)
          .doc(user.userID)
          .set(referralModel.toJson());

      // Create pending referral record if user was referred
      if (referrerId != null && referrerId != user.userID) {
        await firestore.collection(PENDING_REFERRALS).add({
          'referrerId': referrerId,
          'refereeId': user.userID,
          'referralCode': referralCode.trim(),
          'isProcessed': false,
          'status': 'pending',
          'createdAt': Timestamp.now(),
        });
      }

      log('✅ Created new user with referral code: ${user.referralCode}');
    } on FirebaseException catch (e, s) {
      log(
        'firebaseCreateNewUser firestore code=${e.code} '
        'message=${e.message} '
        'userId=${user.userID} '
        'email=${user.email} '
        'stack=$s',
      );
      return "notSignUp";
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return "notSignUp";
    }
    return null;
  }

  // Removed client-side referral processing - backend handles all business logic

  static getReferralAmount() async {
    try {
      await firestore
          .collection(Setting)
          .doc("referral_amount")
          .get()
          .then((value) {
        referralAmount = value.data()!['referralAmount'];
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralAmount;
  }

  static Future<bool?> checkReferralCodeValidOrNot(String referralCode) async {
    bool? isExit;
    try {
      await firestore
          .collection(REFERRAL)
          .where("referralCode", isEqualTo: referralCode)
          .get()
          .then((value) {
        if (value.size > 0) {
          isExit = true;
        } else {
          isExit = false;
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isExit;
  }

  static Future<ReferralModel?> getReferralUserByCode(
      String referralCode) async {
    ReferralModel? referralModel;
    try {
      await firestore
          .collection(REFERRAL)
          .where("referralCode", isEqualTo: referralCode)
          .get()
          .then((value) {
        referralModel = ReferralModel.fromJson(value.docs.first.data());
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<ReferralModel?> getReferralUserBy() async {
    ReferralModel? referralModel;
    try {
      print(MyAppState.currentUser!.userID);
      await firestore
          .collection(REFERRAL)
          .doc(MyAppState.currentUser!.userID)
          .get()
          .then((value) {
        referralModel = ReferralModel.fromJson(value.data()!);
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<String?> referralAdd(ReferralModel ratingModel) async {
    try {
      await firestore
          .collection(REFERRAL)
          .doc(ratingModel.id)
          .set(ratingModel.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return 'Couldn\'t review';
    }
    return null;
  }

  /// Gets or generates a unique referral code for the current user
  /// Returns existing code if user already has one, otherwise generates new one
  static Future<String?> getUserReferralCode() async {
    try {
      // Simply return the referral code from current user - backend manages it
      if (MyAppState.currentUser?.referralCode != null &&
          MyAppState.currentUser!.referralCode!.isNotEmpty) {
        return MyAppState.currentUser!.referralCode;
      }
      return null;
    } catch (e, s) {
      print('❌ Error in getUserReferralCode: $e $s');
      return null;
    }
  }

  /// Gets referral code for a specific user by user ID
  static Future<String?> getUserReferralCodeById(String userId) async {
    try {
      var doc = await firestore.collection(USERS).doc(userId).get();
      if (doc.exists) {
        User user = User.fromJson(doc.data()!);
        return user.referralCode;
      }
      return null;
    } catch (e) {
      print('❌ Error getting referral code for user $userId: $e');
      return null;
    }
  }

  /// Validates and processes referral code during signup
  static Future<User?> validateAndProcessReferralCode(
      String referralCode) async {
    try {
      // Check if referral code exists in REFERRAL collection (backward compatibility)
      ReferralModel? referrerModel = await getReferralUserByCode(referralCode);
      if (referrerModel != null) {
        return await getCurrentUser(referrerModel.id!);
      }

      // Check if referral code exists in USERS collection (new system)
      var querySnapshot = await firestore
          .collection(USERS)
          .where('referralCode', isEqualTo: referralCode)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return User.fromJson(querySnapshot.docs.first.data());
      }

      return null; // Referral code not found
    } catch (e) {
      print('❌ Error validating referral code: $e');
      return null;
    }
  }

  /// Processes referral code during signup - non-blocking validation
  static Future<Map<String, dynamic>> processSignupReferralCode(
      String referralCode, String newUserId) async {
    try {
      // Skip if no referral code provided
      if (referralCode.isEmpty) {
        return {'success': true, 'message': 'No referral code provided'};
      }

      print('🔍 Processing referral code: $referralCode for user: $newUserId');

      // Check for self-referral (user trying to refer themselves)
      User? newUser = await getCurrentUser(newUserId);
      if (newUser?.referralCode == referralCode) {
        print('⚠️ Self-referral blocked');
        return {
          'success': false,
          'message': 'Cannot use your own referral code',
          'blocked': true
        };
      }

      // Find the referrer by code
      User? referrer = await validateAndProcessReferralCode(referralCode);

      if (referrer == null) {
        print('⚠️ Invalid referral code: $referralCode');
        return {
          'success': false,
          'message': 'Invalid referral code',
          'blocked': false
        };
      }

      // Check if user already has a referrer (write-once protection)
      if (newUser?.referredBy != null && newUser!.referredBy!.isNotEmpty) {
        print('⚠️ User already has a referrer: ${newUser.referredBy}');
        return {
          'success': false,
          'message': 'User already has a referrer',
          'blocked': false
        };
      }

      // Set the referrer (write-once operation)
      bool referrerSet = newUser!.setReferredBy(referrer.userID);
      if (!referrerSet) {
        print('⚠️ Failed to set referrer - already exists');
        return {
          'success': false,
          'message': 'Referrer already set',
          'blocked': false
        };
      }

      // Create pending referral record
      await _createPendingReferralRecord(
          referrer.userID, newUserId, referralCode);

      print('✅ Referral code processed successfully');
      return {
        'success': true,
        'message': 'Referral code applied successfully',
        'referrerId': referrer.userID,
        'referrerName': referrer.fullName(),
      };
    } catch (e) {
      print('❌ Error processing referral code: $e');
      return {
        'success': false,
        'message': 'Error processing referral code',
        'blocked': false
      };
    }
  }

  /// Creates a pending referral record for later reward evaluation
  static Future<void> _createPendingReferralRecord(
      String referrerId, String refereeId, String referralCode) async {
    try {
      PendingReferralModel pendingReferral = PendingReferralModel(
        id: refereeId, // Use referee ID as document ID for easy lookup
        referrerId: referrerId,
        refereeId: refereeId,
        referralCode: referralCode,
        createdAt: Timestamp.now(),
        isProcessed: false,
        status: 'pending',
      );

      await firestore
          .collection(PENDING_REFERRALS)
          .doc(refereeId)
          .set(pendingReferral.toJson());

      print('✅ Created pending referral record for user: $refereeId');
    } catch (e) {
      print('❌ Error creating pending referral record: $e');
    }
  }

  /// Gets pending referrals for a referrer
  static Future<List<PendingReferralModel>> getPendingReferralsForReferrer(
      String referrerId) async {
    try {
      var querySnapshot = await firestore
          .collection(PENDING_REFERRALS)
          .where('referrerId', isEqualTo: referrerId)
          .where('isProcessed', isEqualTo: false)
          .get();

      return querySnapshot.docs
          .map((doc) => PendingReferralModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('❌ Error getting pending referrals: $e');
      return [];
    }
  }

  /// Processes referral completion when a customer's first order is completed
  /// This method is atomic and idempotent - safe to call multiple times
  /// orderId is used for idempotency protection to prevent duplicate credits
  static Future<void> processReferralCompletion(
      String customerId, String orderId) async {
    return _runSerializedReferral(() async {
      final txName = 'FireStoreUtils.processReferralCompletion';
      final txParams = 'customerId=$customerId orderId=$orderId';
      _setTxBreadcrumb(name: txName, params: txParams);

      try {
        print(
            '🔍 Processing referral completion for customer: $customerId, order: $orderId');

        // Use atomic transaction to ensure all operations succeed or fail together
        await runFirestoreTransaction<void>(
          firestore: firestore,
          txName: txName,
          txParams: txParams,
          handler: (transaction) async {
          // Check if this specific order has already been processed for referral credits
          DocumentReference referralCreditDoc = firestore
              .collection('referral_credits')
              .doc('${customerId}_${orderId}');

          DocumentSnapshot referralCreditSnapshot =
              await transaction.get(referralCreditDoc);

          if (referralCreditSnapshot.exists) {
            print(
                '⚠️ Referral credit already processed for customer: $customerId, order: $orderId');
            return; // Already processed - idempotent exit
          }

          // Get customer data within transaction
          DocumentReference customerDoc =
              firestore.collection(USERS).doc(customerId);
          DocumentSnapshot customerSnapshot = await transaction.get(customerDoc);

          if (!customerSnapshot.exists) {
            print('⚠️ Customer not found: $customerId');
            throw Exception('Customer not found');
          }

          User customer =
              User.fromJson(customerSnapshot.data()! as Map<String, dynamic>);

          // Check if customer has a referrer and hasn't completed first order yet
          if (customer.referredBy == null ||
              customer.referredBy!.isEmpty ||
              customer.hasCompletedFirstOrder) {
            print(
                '⚠️ Customer has no referrer or already completed first order');
            return; // Not eligible for referral credit
          }

          // Check if there's a pending referral record for this customer
          DocumentReference pendingReferralDoc =
              firestore.collection(PENDING_REFERRALS).doc(customerId);
          DocumentSnapshot pendingReferralSnapshot =
              await transaction.get(pendingReferralDoc);

          if (!pendingReferralSnapshot.exists) {
            print(
                '⚠️ No pending referral record found for customer: $customerId');
            return;
          }

          PendingReferralModel pendingReferral = PendingReferralModel.fromJson(
              pendingReferralSnapshot.data()! as Map<String, dynamic>);

          if (pendingReferral.isProcessed == true) {
            print('⚠️ Referral already processed for customer: $customerId');
            return;
          }

          print(
              '✅ Processing referral for customer: $customerId, referrer: ${pendingReferral.referrerId}');

          // Get referral amount from constants
          double referralAmountValue = double.tryParse(referralAmount) ?? 0.0;

          if (referralAmountValue <= 0) {
            print('⚠️ No referral amount configured');
            return;
          }

          // Get referrer data within transaction
          DocumentReference referrerDoc =
              firestore.collection(USERS).doc(pendingReferral.referrerId!);
          DocumentSnapshot referrerSnapshot =
              await transaction.get(referrerDoc);

          if (!referrerSnapshot.exists) {
            print('⚠️ Referrer not found: ${pendingReferral.referrerId}');
            throw Exception('Referrer not found');
          }

          User referrer =
              User.fromJson(referrerSnapshot.data()! as Map<String, dynamic>);

          // Calculate new wallet amount
          double newWalletAmount =
              (referrer.walletAmount ?? 0.0) + referralAmountValue;

          // Perform all updates atomically:

          // 1. Mark pending referral as earned and processed
          transaction.update(pendingReferralDoc, {
            'isProcessed': true,
            'status': 'earned',
            'processedAt': Timestamp.now(),
            'processedOrderId':
                orderId, // Track which order triggered the credit
          });

          // 2. Update customer's first order completion flag
          transaction.update(customerDoc, {
            'hasCompletedFirstOrder': true,
            'firstOrderCompletedAt': Timestamp.now(),
            'firstOrderId': orderId, // Track which order was the first completed
          });

          // 3. Update referrer's wallet amount
          transaction.update(referrerDoc, {
            'wallet_amount': newWalletAmount,
          });

          // 4. Create idempotency record to prevent duplicate processing
          transaction.set(referralCreditDoc, {
            'customerId': customerId,
            'referrerId': pendingReferral.referrerId!,
            'orderId': orderId,
            'amount': referralAmountValue,
            'type': 'referral_bonus',
            'status': 'completed',
            'createdAt': Timestamp.now(),
            'customerName': customer.fullName(),
            'referrerName': referrer.fullName(),
          });

          // 5. Create audit trail transaction record
          DocumentReference transactionDoc =
              firestore.collection('referral_transactions').doc();
          transaction.set(transactionDoc, {
            'id': transactionDoc.id,
            'referrerId': pendingReferral.referrerId!,
            'customerId': customerId,
            'orderId': orderId,
            'amount': referralAmountValue,
            'type': 'referral_bonus',
            'status': 'completed',
            'createdAt': Timestamp.now(),
            'customerName': customer.fullName(),
            'referrerName': referrer.fullName(),
            'previousWalletAmount': referrer.walletAmount ?? 0.0,
            'newWalletAmount': newWalletAmount,
          });

          print('✅ Atomic referral processing completed successfully');
          },
        );

        print(
            '✅ Referral processing completed successfully for customer: $customerId, order: $orderId');
      } catch (e, s) {
        print('❌ Error processing referral completion: $e');
        await FirebaseCrashlytics.instance.recordError(
          e,
          s,
          reason: txName,
        );
        // Transaction will automatically rollback on error
      }
    });
  }

  /// Checks if a referral credit has already been processed for a specific order
  /// This is used for idempotency protection
  static Future<bool> isReferralCreditProcessed(
      String customerId, String orderId) async {
    try {
      DocumentSnapshot doc = await firestore
          .collection('referral_credits')
          .doc('${customerId}_${orderId}')
          .get();

      return doc.exists;
    } catch (e) {
      print('❌ Error checking referral credit status: $e');
      return false;
    }
  }

  /// Gets all referral credits for a specific customer
  static Future<List<Map<String, dynamic>>> getReferralCreditsForCustomer(
      String customerId) async {
    try {
      QuerySnapshot querySnapshot = await firestore
          .collection('referral_credits')
          .where('customerId', isEqualTo: customerId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('❌ Error getting referral credits for customer: $e');
      return [];
    }
  }

  /// Gets all referral credits earned by a specific referrer
  static Future<List<Map<String, dynamic>>> getReferralCreditsForReferrer(
      String referrerId) async {
    try {
      QuerySnapshot querySnapshot = await firestore
          .collection('referral_credits')
          .where('referrerId', isEqualTo: referrerId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('❌ Error getting referral credits for referrer: $e');
      return [];
    }
  }

  /// Gets total referral earnings for a referrer
  static Future<double> getTotalReferralEarnings(String referrerId) async {
    try {
      QuerySnapshot querySnapshot = await firestore
          .collection('referral_credits')
          .where('referrerId', isEqualTo: referrerId)
          .get();

      double total = 0.0;
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        total += (data['amount'] as num?)?.toDouble() ?? 0.0;
      }

      return total;
    } catch (e) {
      print('❌ Error getting total referral earnings: $e');
      return 0.0;
    }
  }

  /// Manually processes referral completion for a specific order
  /// This can be used for debugging or handling edge cases
  static Future<bool> manualProcessReferralCompletion(
      String customerId, String orderId) async {
    try {
      print(
          '🔧 Manual referral processing for customer: $customerId, order: $orderId');

      // Check if already processed
      bool alreadyProcessed =
          await isReferralCreditProcessed(customerId, orderId);
      if (alreadyProcessed) {
        print('⚠️ Referral already processed for this order');
        return true; // Success - already processed
      }

      // Process the referral
      await processReferralCompletion(customerId, orderId);

      // Verify it was processed
      bool nowProcessed = await isReferralCreditProcessed(customerId, orderId);
      print(
          '✅ Manual referral processing ${nowProcessed ? "successful" : "failed"}');

      return nowProcessed;
    } catch (e) {
      print('❌ Error in manual referral processing: $e');
      return false;
    }
  }

  /// Determines if a customer is on the referral path (eligible for referral rewards)
  /// Returns true if customer has a referrer and hasn't completed first order yet
  static Future<bool> isCustomerOnReferralPath(String customerId) async {
    try {
      User? customer = await getCurrentUser(customerId);
      if (customer == null) {
        return false;
      }

      // Customer is on referral path if:
      // 1. Has a referrer (referredBy is not null/empty)
      // 2. Hasn't completed their first order yet
      bool hasReferrer =
          customer.referredBy != null && customer.referredBy!.isNotEmpty;
      bool hasNotCompletedFirstOrder = !customer.hasCompletedFirstOrder;

      return hasReferrer && hasNotCompletedFirstOrder;
    } catch (e) {
      print('❌ Error checking referral path status: $e');
      return false;
    }
  }

  /// Generates audit note for referral vs promo decision
  static String generateReferralAuditNote(
      bool isReferralPath, bool promoApplied) {
    if (isReferralPath && promoApplied) {
      return "Referral active → ₱20 promo disabled (mutually exclusive)";
    } else if (isReferralPath) {
      return "Referral active → ₱20 promo not applied (mutually exclusive)";
    } else if (promoApplied) {
      return "₱20 first-order promo applied";
    } else {
      return "No first-order benefits applied";
    }
  }

  /// Validates referral system consistency for a customer
  /// Returns a report of any inconsistencies found
  static Future<Map<String, dynamic>> validateReferralConsistency(
      String customerId) async {
    try {
      Map<String, dynamic> report = {
        'customerId': customerId,
        'isValid': true,
        'issues': <String>[],
        'details': <String, dynamic>{},
      };

      // Get customer data
      User? customer = await getCurrentUser(customerId);
      if (customer == null) {
        report['isValid'] = false;
        report['issues'].add('Customer not found');
        return report;
      }

      report['details']['hasReferredBy'] =
          customer.referredBy != null && customer.referredBy!.isNotEmpty;
      report['details']['hasCompletedFirstOrder'] =
          customer.hasCompletedFirstOrder;

      // Check pending referral record
      DocumentSnapshot pendingReferralDoc =
          await firestore.collection(PENDING_REFERRALS).doc(customerId).get();

      report['details']['hasPendingReferral'] = pendingReferralDoc.exists;

      if (pendingReferralDoc.exists) {
        PendingReferralModel pendingReferral = PendingReferralModel.fromJson(
            pendingReferralDoc.data()! as Map<String, dynamic>);
        report['details']['pendingReferralProcessed'] =
            pendingReferral.isProcessed ?? false;
        report['details']['pendingReferralStatus'] = pendingReferral.status;
      }

      // Check referral credits
      List<Map<String, dynamic>> credits =
          await getReferralCreditsForCustomer(customerId);
      report['details']['referralCreditsCount'] = credits.length;

      // Validate consistency
      if (customer.referredBy != null && customer.referredBy!.isNotEmpty) {
        if (customer.hasCompletedFirstOrder) {
          // Should have a processed pending referral and credit record
          if (!pendingReferralDoc.exists) {
            report['isValid'] = false;
            report['issues'].add(
                'Missing pending referral record for customer with referrer');
          } else {
            PendingReferralModel pendingReferral =
                PendingReferralModel.fromJson(
                    pendingReferralDoc.data()! as Map<String, dynamic>);
            if (!(pendingReferral.isProcessed ?? false)) {
              report['isValid'] = false;
              report['issues'].add('Pending referral not marked as processed');
            }
          }

          if (credits.isEmpty) {
            report['isValid'] = false;
            report['issues'].add(
                'No referral credit found for customer with completed first order');
          }
        } else {
          // Should have a pending referral but no credit
          if (!pendingReferralDoc.exists) {
            report['isValid'] = false;
            report['issues'].add(
                'Missing pending referral record for customer with referrer');
          }

          if (credits.isNotEmpty) {
            report['isValid'] = false;
            report['issues'].add(
                'Found referral credits for customer without completed first order');
          }
        }
      }

      return report;
    } catch (e) {
      print('❌ Error validating referral consistency: $e');
      return {
        'customerId': customerId,
        'isValid': false,
        'issues': ['Error during validation: $e'],
        'details': {},
      };
    }
  }

  /// Updates pending referral status
  static Future<void> updatePendingReferralStatus(
      String refereeId, String status,
      {bool isProcessed = true}) async {
    try {
      await firestore.collection(PENDING_REFERRALS).doc(refereeId).update({
        'status': status,
        'isProcessed': isProcessed,
      });

      print('✅ Updated pending referral status for user: $refereeId');
    } catch (e) {
      print('❌ Error updating pending referral status: $e');
    }
  }

  static Future<String?> firebaseCreateNewReview(
      RatingModel ratingModel) async {
    try {
      await firestore
          .collection(Order_Rating)
          .doc(ratingModel.id)
          .set(ratingModel.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return 'Couldn\'t review';
    }
    return null;
  }

  /// Helper function to ensure user has referral code after login
  static Future<void> _ensureReferralCodeAfterLogin(User user) async {
    try {
      // Call backend to ensure referral code (timeout so login never blocks)
      String? backendReferralCode = await BackendService
          .ensureReferralCodeOnLogin(user.userID)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      // Update user if backend assigned a new referral code
      if (backendReferralCode != null &&
          user.referralCode != backendReferralCode) {
        user.referralCode = backendReferralCode;
        await updateCurrentUser(user);
        print(
            '✅ Updated user with backend referral code: $backendReferralCode');
      }
    } catch (e) {
      print(
          '⚠️ Backend referral check failed, continuing with existing flow: $e');
    }
  }

  /// login with email and password with firebase
  /// @param email user email
  /// @param password user password
  static Future<dynamic> loginWithEmailAndPassword(
      String email, String password) async {
    try {
      log('FireStoreUtils.loginWithEmailAndPassword email=$email');
      auth.UserCredential result = await auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final String uid = result.user?.uid ?? '';
      log('Login success: uid=${uid.isEmpty ? 'null' : uid}');
      if (uid.isEmpty) {
        return 'Login failed: empty user id.';
      }
      DocumentSnapshot<Map<String, dynamic>> documentSnapshot =
          await firestore.collection(USERS).doc(uid).get();
      log('Login user doc exists=${documentSnapshot.exists}');
      User? user;

      if (!documentSnapshot.exists) {
        await firestore.collection(USERS).doc(uid).set({
          'email': email.trim(),
          'role': USER_ROLE_CUSTOMER,
          'active': true,
        });
        documentSnapshot = await firestore.collection(USERS).doc(uid).get();
      }
      if (documentSnapshot.exists) {
        final Map<String, dynamic> data = documentSnapshot.data() ?? {};
        final String role = (data['role'] ?? '').toString().trim();
        if (role.isEmpty) {
          await firestore.collection(USERS).doc(uid).set(
            {
              'role': USER_ROLE_CUSTOMER,
            },
            SetOptions(merge: true),
          );
          documentSnapshot = await firestore.collection(USERS).doc(uid).get();
        }
        user = User.fromJson(documentSnapshot.data() ?? {});
        await _ensureReferralCodeAfterLogin(user);
      } else {
        return 'User record missing after login.';
      }
      if (user != null) {
        unawaited(refreshFcmTokenForUser(user));
      }
      return user;
    } on auth.FirebaseAuthException catch (exception, s) {
      log('FirebaseAuthException code=${exception.code} message=${exception.message} $s');
      switch ((exception).code) {
        case 'invalid-email':
          return 'Email address is malformed.';
        case 'wrong-password':
          return 'Wrong password.';
        case 'user-not-found':
          return 'No user corresponding to the given email address.';
        case 'user-disabled':
          return 'This user has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts to sign in as this user.';
      }
      return 'Authentication failed: ${exception.code}.';
    } on FirebaseException catch (exception, s) {
      log('Firestore exception code=${exception.code} message=${exception.message} $s');
      return 'Firestore error: ${exception.code}.';
    } catch (e, s) {
      log(e.toString() + '$s');
      return 'Login failed: ${e.toString()}.';
    }
  }

  ///submit a phone number to firebase to receive a code verification, will
  ///be used later to login
  static Future<void> firebaseSubmitPhoneNumber(
    String phoneNumber,
    auth.PhoneCodeAutoRetrievalTimeout? phoneCodeAutoRetrievalTimeout,
    auth.PhoneCodeSent? phoneCodeSent,
    auth.PhoneVerificationFailed? phoneVerificationFailed,
    auth.PhoneVerificationCompleted? phoneVerificationCompleted,
  ) async {
    // #region agent log
    debugPrint(
      '[PHONE_AUTH] entry kDebugMode=$kDebugMode isAndroid=${Platform.isAndroid} '
      'willSetSettings=${kDebugMode && Platform.isAndroid}',
    );
    await _appendCursorDebugLog(
      hypothesisId: 'H8',
      location: 'FirebaseHelper.firebaseSubmitPhoneNumber:entry',
      message: 'phone auth entry',
      data: <String, Object?>{
        'kDebugMode': kDebugMode,
        'isAndroid': Platform.isAndroid,
        'willCallSetSettings': kDebugMode && Platform.isAndroid,
        'phoneLength': phoneNumber.trim().length,
      },
    );
    // #endregion
    if (kDebugMode && Platform.isAndroid) {
      try {
        // #region agent log
        debugPrint('[PHONE_AUTH] calling setSettings(appVerificationDisabledForTesting: true)');
        await _appendCursorDebugLog(
          hypothesisId: 'H8',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:beforeSetSettings',
          message: 'calling setSettings(appVerificationDisabledForTesting: true)',
          data: <String, Object?>{},
        );
        // #endregion
        await auth.FirebaseAuth.instance.setSettings(
          appVerificationDisabledForTesting: true,
        );
        // #region agent log
        debugPrint('[PHONE_AUTH] setSettings succeeded');
        await _appendCursorDebugLog(
          hypothesisId: 'H8',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:setSettingsSuccess',
          message: 'setSettings succeeded',
          data: <String, Object?>{},
        );
        // #endregion
      } catch (e, s) {
        // #region agent log
        debugPrint('[PHONE_AUTH] setSettings failed: $e');
        await _appendCursorDebugLog(
          hypothesisId: 'H8',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:setSettingsError',
          message: 'setSettings failed',
          data: <String, Object?>{
            'error': e.toString(),
            'stack': s.toString().split('\n').take(3).join(' '),
          },
        );
        // #endregion
      }
    }
    // #region agent log
    debugPrint('[PHONE_AUTH] calling verifyPhoneNumber phoneLength=${phoneNumber.trim().length}');
    _appendCursorDebugLog(
      hypothesisId: 'H1',
      location: 'FirebaseHelper.firebaseSubmitPhoneNumber:beforeVerify',
      message: 'calling verifyPhoneNumber',
      data: <String, Object?>{
        'phoneLength': phoneNumber.trim().length,
        'hasPlus': phoneNumber.trim().startsWith('+'),
      },
    );
    // #endregion
    final auth.PhoneCodeSent? onCodeSent = phoneCodeSent;
    final auth.PhoneVerificationFailed? onVerificationFailed =
        phoneVerificationFailed;
    auth.FirebaseAuth.instance.verifyPhoneNumber(
      timeout: Duration(minutes: 2),
      phoneNumber: phoneNumber,
      verificationCompleted: phoneVerificationCompleted!,
      verificationFailed: (auth.FirebaseAuthException error) {
        // #region agent log
        debugPrint(
          '[PHONE_AUTH] verificationFailed code=${error.code} '
          'message=${error.message ?? ""}',
        );
        _appendCursorDebugLog(
          hypothesisId: 'H3',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:verificationFailed',
          message: 'verifyPhoneNumber failed',
          data: <String, Object?>{
            'errorCode': error.code,
            'message': error.message ?? '',
          },
        );
        // #endregion
        if (onVerificationFailed != null) {
          onVerificationFailed(error);
        }
      },
      codeSent: (String verificationId, int? forceResendingToken) {
        // #region agent log
        debugPrint(
          '[PHONE_AUTH] codeSent verificationIdLength=${verificationId.length}',
        );
        _appendCursorDebugLog(
          hypothesisId: 'H2',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:codeSent',
          message: 'verifyPhoneNumber code sent',
          data: <String, Object?>{
            'verificationIdLength': verificationId.length,
            'hasResendToken': forceResendingToken != null,
          },
        );
        // #endregion
        if (onCodeSent != null) {
          onCodeSent(verificationId, forceResendingToken);
        }
      },
      codeAutoRetrievalTimeout: phoneCodeAutoRetrievalTimeout!,
    );
  }

  /// submit the received code to firebase to complete the phone number
  /// verification process
  static Future<dynamic> firebaseSubmitPhoneNumberCode(String verificationID,
      String code, String phoneNumber, BuildContext context,
      {String firstName = 'Anonymous',
      String lastName = 'User',
      File? image,
      String referralCode = ''}) async {
    auth.AuthCredential authCredential = auth.PhoneAuthProvider.credential(
        verificationId: verificationID, smsCode: code);
    auth.UserCredential userCredential =
        await auth.FirebaseAuth.instance.signInWithCredential(authCredential);
    User? user = await getCurrentUser(userCredential.user?.uid ?? '');
    // #region agent log
    await _appendCursorDebugLog(
      hypothesisId: 'H4',
      location: 'FirebaseHelper.firebaseSubmitPhoneNumberCode:userLookup',
      message: 'phone auth user lookup',
      data: <String, Object?>{
        'verificationIdLength': verificationID.length,
        'codeLength': code.length,
        'hasUid': (userCredential.user?.uid ?? '').isNotEmpty,
        'userFound': user != null,
        'roleMatch': user?.role == USER_ROLE_CUSTOMER,
      },
    );
    // #endregion
    if (user != null && user.role == USER_ROLE_CUSTOMER) {
      user.role = USER_ROLE_CUSTOMER;
      //user.active = true;
      await updateCurrentUser(user);
      unawaited(refreshFcmTokenForUser(user));
      // #region agent log
      await _appendCursorDebugLog(
        hypothesisId: 'H4',
        location: 'FirebaseHelper.firebaseSubmitPhoneNumberCode:returnExisting',
        message: 'returning existing customer user',
        data: <String, Object?>{
          'uid': user.userID,
          'role': user.role,
        },
      );
      // #endregion
      return user;
    } else if (user == null) {
      /// create a new user from phone login
      String profileImageUrl = '';
      if (image != null) {
        File? compressedImage = await FireStoreUtils.compressImage(image);
        final bytes = compressedImage?.readAsBytesSync().lengthInBytes;
        final kb = bytes ?? 0 / 1024;
        final mb = kb / 1024;

        // File size limit removed - allowing larger images
        print('🔄 DEBUG: File size limit removed - proceeding with upload');
        profileImageUrl = await uploadUserImageToFireStorage(
            compressedImage ?? image, userCredential.user?.uid ?? '');
      }
      User user = User(
        firstName: firstName,
        lastName: lastName,
        fcmToken: '',
        phoneNumber: phoneNumber,
        profilePictureURL: profileImageUrl,
        userID: userCredential.user?.uid ?? '',
        role: USER_ROLE_CUSTOMER,
        active: true,
        lastOnlineTimestamp: Timestamp.now(),
        settings: UserSettings(),
        createdAt: Timestamp.now(),
        email: '',
      );
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (errorMessage == null) {
        unawaited(refreshFcmTokenForUser(user));
        // #region agent log
        await _appendCursorDebugLog(
          hypothesisId: 'H4',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumberCode:returnNew',
          message: 'returning newly created user',
          data: <String, Object?>{
            'uid': user.userID,
          },
        );
        // #endregion
        return user;
      } else {
        // #region agent log
        await _appendCursorDebugLog(
          hypothesisId: 'H4',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumberCode:createFailed',
          message: 'firebaseCreateNewUser failed',
          data: <String, Object?>{
            'errorMessage': errorMessage,
          },
        );
        // #endregion
        return 'Couldn\'t create new user with phone number.';
      }
    } else {
      // user != null && user.role != USER_ROLE_CUSTOMER
      // #region agent log
      await _appendCursorDebugLog(
        hypothesisId: 'H4',
        location: 'FirebaseHelper.firebaseSubmitPhoneNumberCode:wrongRole',
        message: 'user exists but role is not customer',
        data: <String, Object?>{
          'uid': user!.userID,
          'role': user.role,
          'expectedRole': USER_ROLE_CUSTOMER,
        },
      );
      // #endregion
      return null;
    }
  }

  /// Account recovery: existing user doc by phone; create or sign in with
  /// new email/password, then merge and optionally migrate to new UID.
  static Future<dynamic> _signUpRecoverExistingUser({
    required String emailAddress,
    required String password,
    required File? image,
    required String firstName,
    required String lastName,
    required String mobile,
    required String referralCode,
    required String existingUserDocId,
    required Map<String, dynamic> existingUserData,
  }) async {
    String currentUid;
    auth.UserCredential authResult;

    try {
      authResult = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: emailAddress, password: password);
      currentUid = authResult.user?.uid ?? '';
    } on auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          authResult = await auth.FirebaseAuth.instance
              .signInWithEmailAndPassword(
                  email: emailAddress, password: password);
          currentUid = authResult.user?.uid ?? '';
        } on auth.FirebaseAuthException catch (loginError, _) {
          log('Recovery signIn error: ${loginError.code} ${loginError.message}');
          switch (loginError.code) {
            case 'wrong-password':
              return 'Wrong password.';
            case 'user-not-found':
              return 'No user corresponding to the given email address.';
            case 'user-disabled':
              return 'This user has been disabled.';
            case 'invalid-email':
              return 'Email address is malformed.';
            case 'too-many-requests':
              return 'Too many requests, please try again later.';
            default:
              return loginError.message ?? 'Login failed.';
          }
        }
      } else {
        switch (e.code) {
          case 'invalid-email':
            return 'Enter a valid email address.';
          case 'operation-not-allowed':
            return 'Email/password accounts are not enabled.';
          case 'weak-password':
            return 'Password must be more than 5 characters.';
          case 'too-many-requests':
            return 'Too many requests, please try again later.';
          default:
            return e.message ?? 'Sign up failed.';
        }
      }
    }

    if (currentUid.isEmpty) return 'Sign up failed: no user id.';

    String profilePicUrl = '';
    if (image != null) {
      try {
        File? compressedImage = await FireStoreUtils.compressImage(image);
        File uploadFile = compressedImage ?? image;
        updateProgress('Uploading image, please wait...');
        profilePicUrl = await uploadUserImageToFireStorage(
          uploadFile,
          currentUid,
        );
      } catch (e, stack) {
        log('Recovery image upload error: $e\n$stack');
      }
    }

    final String? existingProfilePic =
        existingUserData['profilePictureURL'] as String?;
    if (profilePicUrl.isEmpty && existingProfilePic != null) {
      profilePicUrl = existingProfilePic;
    }

    final Map<String, dynamic> merged = Map<String, dynamic>.from(
      existingUserData,
    );
    merged['firstName'] = firstName;
    merged['lastName'] = lastName;
    merged['email'] = emailAddress;
    merged['profilePictureURL'] = profilePicUrl;
    merged['id'] = currentUid;
    merged['updatedAt'] = Timestamp.now();
    merged['lastOnlineTimestamp'] = Timestamp.now();
    merged['active'] = true;
    merged['phoneNumber'] = mobile;

    if (currentUid == existingUserDocId) {
      await firestore
          .collection(USERS)
          .doc(currentUid)
          .set(merged, SetOptions(merge: true));
      unawaited(refreshFcmTokenForUser(User.fromJson(merged)));
      return User.fromJson(merged);
    }

    await firestore.collection(USERS).doc(currentUid).set(merged);

    final QuerySnapshot<Map<String, dynamic>> ordersSnap = await firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: existingUserDocId)
        .get();
    for (final doc in ordersSnap.docs) {
      await doc.reference.update({'authorID': currentUid});
    }

    final QuerySnapshot<Map<String, dynamic>> tableSnap = await firestore
        .collection(ORDERS_TABLE)
        .where('author.id', isEqualTo: existingUserDocId)
        .get();
    for (final doc in tableSnap.docs) {
      await doc.reference.update({
        'author.id': currentUid,
        'authorID': currentUid,
      });
    }

    final String? refCode = existingUserData['referralCode'] as String?;
    final String? refBy = existingUserData['referredBy'] as String?;
    final String resolvedRefCode =
        refCode?.isNotEmpty == true
            ? refCode!
            : await _generateUniqueReferralCode(currentUid);
    await firestore.collection(REFERRAL).doc(currentUid).set({
      'id': currentUid,
      'referralCode': resolvedRefCode,
      'referralBy': refBy,
    });
    try {
      await firestore.collection(REFERRAL).doc(existingUserDocId).delete();
    } catch (_) {}

    final QuerySnapshot<Map<String, dynamic>> pendingSnap = await firestore
        .collection(PENDING_REFERRALS)
        .where('refereeId', isEqualTo: existingUserDocId)
        .get();
    for (final doc in pendingSnap.docs) {
      await doc.reference.update({'refereeId': currentUid});
    }

    await firestore.collection(USERS).doc(existingUserDocId).delete();

    final User user = User.fromJson(merged);
    unawaited(refreshFcmTokenForUser(user));
    return user;
  }

  static Future<dynamic> firebaseSignUpWithEmailAndPassword({
    required String emailAddress,
    required String password,
    required File? image,
    required String firstName,
    required String lastName,
    required String mobile,
    required BuildContext context,
    required String referralCode,
    String? existingUserDocId,
    Map<String, dynamic>? existingUserData,
  }) async {
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H11',
      location: 'FirebaseHelper.firebaseSignUp:keychainWarmup',
      message: 'warming keychain before auth',
      data: const <String, Object?>{
        'start': true,
      },
    ));
    // #endregion
    if (Platform.isIOS) {
      unawaited(_warmUpKeychain());
    }
    log(
      'firebaseSignUp start email=$emailAddress '
      'hasImage=${image != null} '
      'platform=${Platform.operatingSystem}',
    );
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H4',
      location: 'FirebaseHelper.firebaseSignUp:entry',
      message: 'signup started',
      data: <String, Object?>{
        'emailLength': emailAddress.trim().length,
        'passwordLength': password.length,
        'hasImage': image != null,
        'phoneLength': mobile.trim().length,
        'platform': Platform.operatingSystem,
      },
    ));
    // #endregion
    // #region agent log
    unawaited(_appendDebugLog(
      hypothesisId: 'H2',
      location: 'FirebaseHelper.firebaseSignUpWithEmailAndPassword:start',
      message: 'starting firebase signup',
      data: <String, Object?>{
        'emailLength': emailAddress.trim().length,
        'passwordLength': password.length,
        'hasImage': image != null,
        'platform': Platform.operatingSystem,
      },
    ));
    // #endregion

    try {
      // Account recovery when phone already exists: reuse existing user doc.
      if (existingUserDocId != null &&
          existingUserData != null &&
          existingUserDocId.isNotEmpty) {
        final recovered = await _signUpRecoverExistingUser(
          emailAddress: emailAddress,
          password: password,
          image: image,
          firstName: firstName,
          lastName: lastName,
          mobile: mobile,
          referralCode: referralCode,
          existingUserDocId: existingUserDocId,
          existingUserData: existingUserData,
        );
        if (recovered != null) return recovered;
      }

      if (Platform.isIOS && _isIosSimulator) {
        log(
          '[SIM_KEYCHAIN_BYPASS] createUserWithEmailAndPassword start',
        );
      }
      final authCreateStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      auth.UserCredential result = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: emailAddress, password: password);
      if (authCreateStopwatch != null) {
        authCreateStopwatch.stop();
        log(
          '[SIGNUP_TIMING] authCreateUserMs=${authCreateStopwatch.elapsedMilliseconds}',
        );
      }
      log('firebaseSignUp user created uid=${result.user?.uid}');
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H4',
        location: 'FirebaseHelper.firebaseSignUp:authResult',
        message: 'firebase auth createUser completed',
        data: <String, Object?>{
          'hasUser': result.user != null,
          'hasUid': (result.user?.uid ?? '').isNotEmpty,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendDebugLog(
        hypothesisId: 'H2',
        location:
            'FirebaseHelper.firebaseSignUpWithEmailAndPassword:authResult',
        message: 'firebase auth createUser result',
        data: <String, Object?>{
          'hasUser': result.user != null,
          'hasUid': (result.user?.uid ?? '').isNotEmpty,
        },
      ));
      // #endregion

      String profilePicUrl = '';

      if (image != null) {
        try {
          File? compressedImage = await FireStoreUtils.compressImage(image);

          File uploadFile = compressedImage ?? image;

          final int bytes = await uploadFile.length();
          final double mb = bytes / (1024 * 1024);

          // File size limit removed - allowing larger images
          print('🔄 DEBUG: File size limit removed - proceeding with upload');

          updateProgress('Uploading image, please wait...');

          profilePicUrl = await uploadUserImageToFireStorage(
            uploadFile,
            result.user?.uid ?? '',
          );
          // #region agent log
          unawaited(_appendDebugLog(
            hypothesisId: 'H4',
            location:
                'FirebaseHelper.firebaseSignUpWithEmailAndPassword:imageUpload',
            message: 'profile image upload completed',
            data: <String, Object?>{
              'hasImage': image != null,
              'uploadBytes': bytes,
              'urlEmpty': profilePicUrl.isEmpty,
            },
          ));
          // #endregion
        } catch (e, stack) {
          log('Image upload error: $e\n$stack');
          // Non-blocking: continue signup without a profile image.
          profilePicUrl = '';
        }
      }

      User user = User(
        email: emailAddress,
        settings: UserSettings(),
        lastOnlineTimestamp: Timestamp.now(),
        active: true,
        phoneNumber: mobile,
        firstName: firstName,
        role: USER_ROLE_CUSTOMER,
        userID: result.user?.uid ?? '',
        lastName: lastName,
        fcmToken: '',
        createdAt: Timestamp.now(),
        profilePictureURL: profilePicUrl,
      );

      final createUserStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (createUserStopwatch != null) {
        createUserStopwatch.stop();
        log(
          '[SIGNUP_TIMING] firestoreCreateUserMs=${createUserStopwatch.elapsedMilliseconds}',
        );
      }

      if (errorMessage == null) {
        unawaited(refreshFcmTokenForUser(user));
        // #region agent log
        unawaited(_appendRuntimeDebugLog(
          hypothesisId: 'H6',
          location: 'FirebaseHelper.firebaseSignUp:createUser',
          message: 'user created in firestore',
          data: <String, Object?>{
            'hasUserId': user.userID.isNotEmpty,
          },
        ));
        // #endregion
        // #region agent log
        unawaited(_appendDebugLog(
          hypothesisId: 'H5',
          location:
              'FirebaseHelper.firebaseSignUpWithEmailAndPassword:createUser',
          message: 'firebase create user success',
          data: <String, Object?>{
            'hasUserId': user.userID.isNotEmpty,
          },
        ));
        // #endregion
        return user;
      } else {
        // #region agent log
        unawaited(_appendDebugLog(
          hypothesisId: 'H5',
          location:
              'FirebaseHelper.firebaseSignUpWithEmailAndPassword:createUser',
          message: 'firebase create user failed',
          data: <String, Object?>{
            'errorMessage': errorMessage,
          },
        ));
        // #endregion
        return 'Couldn\'t sign up for Firebase, please try again.';
      }
    } on auth.FirebaseAuthException catch (error, stack) {
      log(
        'firebaseSignUp auth error code=${error.code} '
        'message=${error.message} '
        'email=$emailAddress '
        'stack=$stack',
      );
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H7',
        location: 'FirebaseHelper.firebaseSignUp:authException',
        message: 'firebase auth exception',
        data: <String, Object?>{
          'code': error.code,
          'message': error.message ?? '',
          'platform': Platform.operatingSystem,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendDebugLog(
        hypothesisId: 'H2',
        location:
            'FirebaseHelper.firebaseSignUpWithEmailAndPassword:authException',
        message: 'firebase auth exception',
        data: <String, Object?>{
          'code': error.code,
          'message': error.message ?? '',
        },
      ));
      // #endregion

      String message = "notSignUp";
      switch (error.code) {
        case 'email-already-in-use':
          message = 'Email already in use, please pick another email!';
          break;
        case 'invalid-email':
          message = 'Enter a valid email address.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled.';
          break;
        case 'weak-password':
          message = 'Password must be more than 5 characters.';
          break;
        case 'too-many-requests':
          message = 'Too many requests, please try again later.';
          break;
      }
      return message;
    } catch (e, stack) {
      log('firebaseSignUp unexpected error $e\n$stack');
      return "notSignUp";
    }
  }

  static Future<auth.UserCredential?> reAuthUser(
    AuthProviders provider, {
    String? email,
    String? password,
    String? smsCode,
    String? verificationId,
    AuthorizationCredentialAppleID? signInWithAppleCredential,
  }) async {
    late auth.AuthCredential credential;

    switch (provider) {
      case AuthProviders.PASSWORD:
        if (email != null && password != null) {
          credential = auth.EmailAuthProvider.credential(
              email: email, password: password);
        } else {
          throw ArgumentError(
              'Email and password must not be null for PASSWORD authentication.');
        }
        break;

      case AuthProviders.PHONE:
        if (smsCode != null && verificationId != null) {
          credential = auth.PhoneAuthProvider.credential(
              smsCode: smsCode, verificationId: verificationId);
        } else {
          throw ArgumentError(
              'smsCode and verificationId must not be null for PHONE authentication.');
        }
        break;

      case AuthProviders.APPLE:
        if (signInWithAppleCredential != null) {
          final idToken = signInWithAppleCredential.identityToken;
          final accessTokenStr = signInWithAppleCredential.authorizationCode;
          if (idToken != null &&
              idToken.isNotEmpty &&
              accessTokenStr != null &&
              accessTokenStr.isNotEmpty) {
            credential = auth.OAuthProvider('apple.com').credential(
              idToken: idToken,
              accessToken: accessTokenStr,
            );
          } else {
            throw ArgumentError(
                'Apple credential missing idToken or authorizationCode.');
          }
        } else {
          throw ArgumentError(
              'signInWithAppleCredential must not be null for APPLE authentication.');
        }
        break;
    }

    return await auth.FirebaseAuth.instance.currentUser
        ?.reauthenticateWithCredential(credential);
  }

  static resetPassword(String emailAddress) async {
    log("email $emailAddress");
    // Build action code settings with safe defaults based on current Firebase app
    // final projectId = Firebase.app().options.projectId;
    // final continueUrl = 'https://$projectId.firebaseapp.com';
    // const androidPackage = 'com.lalago.customer.android';

    // final actionCodeSettings = auth.ActionCodeSettings(
    //   url: continueUrl,
    //   handleCodeInApp: true,
    //   androidPackageName: androidPackage,
    //   androidInstallApp: true,
    //   androidMinimumVersion: '21',
    // );

    return auth.FirebaseAuth.instance
        .sendPasswordResetEmail(email: emailAddress);
  }

  static deleteUser() async {
    try {
      // delete user records from CHANNEL_PARTICIPATION table
      await firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: MyAppState.currentUser!.userID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });

      // delete user records from REPORTS table
      await firestore
          .collection(REPORTS)
          .where('source', isEqualTo: MyAppState.currentUser!.userID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });

      // delete user records from REPORTS table
      await firestore
          .collection(REPORTS)
          .where('dest', isEqualTo: MyAppState.currentUser!.userID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });

      // delete user records from users table
      await firestore
          .collection(USERS)
          .doc(auth.FirebaseAuth.instance.currentUser!.uid)
          .delete();

      // delete user  from firebase auth
      await auth.FirebaseAuth.instance.currentUser!.delete();
    } catch (e, s) {
      print('FireStoreUtils.deleteUser $e $s');
    }
  }

  Future<List> getVendorCusions(String id) async {
    List tagList = [];
    List prodtagList = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: id)
        .get();
    await Future.forEach(productsQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      if (document.data().containsKey("categoryID") &&
          document.data()['categoryID'].toString().isNotEmpty) {
        prodtagList.add(document.data()['categoryID']);
      }
    });
    QuerySnapshot<Map<String, dynamic>> catQuery = await firestore
        .collection(VENDORS_CATEGORIES)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(catQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      Map<String, dynamic> catDoc = document.data();
      if (catDoc.containsKey("id") &&
          catDoc['id'].toString().isNotEmpty &&
          catDoc.containsKey("title") &&
          catDoc['title'].toString().isNotEmpty &&
          prodtagList.contains(catDoc['id'])) {
        tagList.add(catDoc['title']);
      }
    });

    return tagList;
  }

  static const String _defaultContactEmail = 'alshidarabdelnasir19@gmail.com';

  getContactUs() async {
    final defaults = <String, dynamic>{
      'Address': '',
      'Phone': '',
      'Email': _defaultContactEmail,
      'Location': '',
    };
    final snapshot =
        await firestore.collection(Setting).doc(CONTACT_US).get();
    final data = snapshot.data();
    if (data == null || data.isEmpty) return defaults;
    final email = data['Email']?.toString().trim() ?? '';
    return {
      'Address': data['Address']?.toString() ?? '',
      'Phone': data['Phone']?.toString() ?? '',
      'Email': email.isEmpty ? _defaultContactEmail : email,
      'Location': data['Location']?.toString() ?? '',
    };
  }

  Future<List<TaxModel>?> getTaxList() async {
    List<TaxModel> taxList = [];

    await firestore
        .collection(tax)
        .where('country', isEqualTo: country)
        .where('enable', isEqualTo: true)
        .get()
        .then((value) {
      for (var element in value.docs) {
        TaxModel taxModel = TaxModel.fromJson(element.data());
        taxList.add(taxModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return taxList;
  }

  static Future<List<GiftCardsModel>> getGiftCard() async {
    List<GiftCardsModel> giftCardModelList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(GIFT_CARDS)
        .where("isEnable", isEqualTo: true)
        .get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        log(document.data().toString());
        giftCardModelList.add(GiftCardsModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return giftCardModelList;
  }

  static Future<void> updateCurrentUserAddress(AddressModel userAddress) async {
    if (MyAppState.currentUser == null) {
      print('❌ Cannot update address: currentUser is null');
      return;
    }

    try {
      print('🔄 Updating user address in Firestore...');
      print('🔄 User ID: ${MyAppState.currentUser!.userID}');
      print(
          '🔄 Shipping addresses count: ${MyAppState.currentUser!.shippingAddress?.length ?? 0}');

      // Update the entire user document with the current shippingAddress list
      await firestore
          .collection(USERS)
          .doc(MyAppState.currentUser!.userID)
          .update({
        'shippingAddress': MyAppState.currentUser!.shippingAddress
                ?.map((address) => address.toJson())
                .toList() ??
            [],
        'location': MyAppState.currentUser!.location?.toJson(),
      });

      print('✅ Address updated successfully in Firestore');
    } catch (e) {
      print('❌ Error updating address in Firestore: $e');
      rethrow;
    }
  }

  /// Updates the latest version in Firestore settings
  static Future<bool> updateLatestVersion(String latestVersion) async {
    try {
      await firestore.collection(Setting).doc('Version').update({
        'latest_version': latestVersion,
      });
      return true;
    } catch (e) {
      debugPrint('Error updating latest version: $e');
      return false;
    }
  }

  getChannelByIdOrNull(String channelID) {}

  // Pagination methods for lazy loading
  Future<Map<String, dynamic>> getRestaurantsPaginated({
    required String orderType,
    required int limit,
    DocumentSnapshot? lastDocument,
    bool popularOnly = false,
  }) async {
    try {
      Query query = FirebaseFirestore.instance.collection(VENDORS);

      if (popularOnly) {
        // For popular restaurants, use reviewsCount (which should exist for all)
        query = query.orderBy('reviewsCount', descending: true);
      } else {
        // For regular restaurants, try createdAt but handle missing fields
        // First, try to get restaurants with createdAt field
        query = query.orderBy('createdAt', descending: true);
      }

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      // Log for debugging
      debugPrint(
          '✅ [getRestaurantsPaginated] Fetched ${snapshot.docs.length} documents');

      final restaurants = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              return VendorModel.fromJson(data);
            } catch (e) {
              debugPrint(
                  '❌ [getRestaurantsPaginated] Error parsing document ${doc.id}: $e');
              return null;
            }
          })
          .whereType<VendorModel>()
          .toList(); // Filter out nulls

      // Get the last document for pagination cursor
      DocumentSnapshot? lastDoc =
          snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

      debugPrint(
          '✅ [getRestaurantsPaginated] Returning ${restaurants.length} restaurants');

      return {
        'restaurants': restaurants,
        'lastDocument': lastDoc,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ [getRestaurantsPaginated] Error: $e');
      debugPrint('❌ [getRestaurantsPaginated] StackTrace: $stackTrace');
      // If the error is about missing index, provide helpful message
      if (e.toString().contains('index')) {
        debugPrint(
            '⚠️ [getRestaurantsPaginated] Firestore index may be missing. Check console for index creation link.');
      }
      return {
        'restaurants': <VendorModel>[],
        'lastDocument': null,
      };
    }
  }

  /// Paginated fetch of orders by status (e.g. completed).
  /// Requires Firestore composite index: authorID, status, createdAt.
  Future<Map<String, dynamic>> getOrdersByStatusPaginated({
    required String userID,
    required String status,
    int limit = 10,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: userID)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      final orders = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              return OrderModel.fromJson(data);
            } catch (e) {
              debugPrint(
                  'getOrdersByStatusPaginated parse error ${doc.id}: $e');
              return null;
            }
          })
          .whereType<OrderModel>()
          .toList();

      final lastDoc =
          snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

      return {
        'orders': orders,
        'lastDocument': lastDoc,
      };
    } catch (e, stackTrace) {
      debugPrint('getOrdersByStatusPaginated error: $e');
      debugPrint('StackTrace: $stackTrace');
      if (e.toString().contains('index')) {
        debugPrint(
            'Firestore index may be missing. Check console for index link.');
      }
      return {
        'orders': <OrderModel>[],
        'lastDocument': null,
      };
    }
  }

  /// Returns vendorID -> order count for user's completed orders (most recent
  /// first). Used for personalizing restaurant ordering in Sulit list.
  Future<Map<String, int>> getUserVendorOrderCounts(
    String userID, {
    int orderLimit = 50,
  }) async {
    final counts = <String, int>{};
    dynamic lastDoc;
    const pageSize = 25;
    try {
      int totalProcessed = 0;
      while (totalProcessed < orderLimit) {
        final result = await getOrdersByStatusPaginated(
          userID: userID,
          status: ORDER_STATUS_COMPLETED,
          limit: pageSize,
          lastDocument: lastDoc,
        );
        final orders = (result['orders'] as List<OrderModel>?) ?? [];
        if (orders.isEmpty) break;
        for (final o in orders) {
          if (o.vendorID.isNotEmpty) {
            counts[o.vendorID] = (counts[o.vendorID] ?? 0) + 1;
          }
        }
        lastDoc = result['lastDocument'];
        totalProcessed += orders.length;
        if (totalProcessed >= orderLimit ||
            lastDoc == null ||
            orders.length < pageSize) {
          break;
        }
      }
    } catch (e) {
      debugPrint('getUserVendorOrderCounts error: $e');
    }
    return counts;
  }

  Future<List<VendorModel>> getPopularRestaurantsPaginated({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(VENDORS)
          .orderBy('reviewsCount', descending: true)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final restaurants = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return VendorModel.fromJson(data);
      }).toList();

      return restaurants;
    } catch (e) {
      debugPrint('Error loading popular restaurants: $e');
      return [];
    }
  }

  Future<List<ProductModel>> getProductsByVendorPaginated({
    required String vendorId,
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorId)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ProductModel.fromJson(data);
      }).toList();

      return products;
    } catch (e) {
      debugPrint('Error loading vendor products: $e');
      return [];
    }
  }

  Future<List<ProductModel>> getProductsByCategoryPaginated({
    required String categoryId,
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(PRODUCTS)
          .where('categoryID', isEqualTo: categoryId)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ProductModel.fromJson(data);
      }).toList();

      return products;
    } catch (e) {
      debugPrint('Error loading category products: $e');
      return [];
    }
  }

  Future<List<ProductModel>> getAllProductsPaginated({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(PRODUCTS)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ProductModel.fromJson(data);
      }).toList();

      return products;
    } catch (e) {
      debugPrint('Error loading all products: $e');
      return [];
    }
  }

  // Search Analytics Methods
  /// Returns document ID for click-update flow, or null on error.
  Future<String?> trackSearchQuery({
    required String userId,
    required String searchQuery,
    required String searchType,
    required int resultCount,
    String? productId,
    String? vendorId,
    String? location,
  }) async {
    try {
      final searchAnalytics = SearchAnalyticsModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        searchQuery: searchQuery,
        searchType: searchType,
        resultCount: resultCount,
        productId: productId,
        vendorId: vendorId,
        timestamp: Timestamp.now(),
        location: location,
        deviceInfo: Platform.operatingSystem,
      );

      final docRef = await firestore
          .collection(SEARCH_ANALYTICS)
          .add(searchAnalytics.toJson());
      return docRef.id;
    } catch (e) {
      debugPrint('Error tracking search: $e');
      return null;
    }
  }

  Future<void> updateSearchClick(String docId, String restaurantId) async {
    try {
      await firestore.collection(SEARCH_ANALYTICS).doc(docId).update({
        'clickedRestaurantId': restaurantId,
        'clickedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating search click: $e');
    }
  }

  // Get popular searches
  Future<List<Map<String, dynamic>>> getPopularSearches({
    int limit = 10,
    String? searchType,
    int daysBack = 30,
  }) async {
    try {
      // Calculate timestamp for 30 days ago
      final thirtyDaysAgo =
          Timestamp.fromDate(DateTime.now().subtract(Duration(days: daysBack)));

      Query query = firestore
          .collection(SEARCH_ANALYTICS)
          .where('timestamp', isGreaterThanOrEqualTo: thirtyDaysAgo);

      if (searchType != null) {
        query = query.where('searchType', isEqualTo: searchType);
      }

      final snapshot = await query
          .orderBy('timestamp', descending: true)
          .limit(limit * 10) // Get more to account for grouping
          .get();

      // Group by search query and count occurrences
      Map<String, int> searchCounts = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final query = data['searchQuery'] as String;
        searchCounts[query] = (searchCounts[query] ?? 0) + 1;
      }

      // Convert to list and sort by count
      List<Map<String, dynamic>> popularSearches = searchCounts.entries
          .map((entry) => {
                'query': entry.key,
                'count': entry.value,
              })
          .toList();

      popularSearches.sort((a, b) => b['count'].compareTo(a['count']));

      return popularSearches.take(limit).toList();
    } catch (e) {
      debugPrint('Error getting popular searches: $e');
      return [];
    }
  }

  // Get user's search history
  Future<List<SearchAnalyticsModel>> getUserSearchHistory(String userId) async {
    try {
      final snapshot = await firestore
          .collection(SEARCH_ANALYTICS)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      return snapshot.docs
          .map((doc) => SearchAnalyticsModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error getting user search history: $e');
      return [];
    }
  }

  // Get trending food searches
  Future<List<Map<String, dynamic>>> getTrendingFoodSearches(
      {int limit = 10}) async {
    return await getPopularSearches(limit: limit, searchType: 'food');
  }

  // Get trending restaurant searches
  Future<List<Map<String, dynamic>>> getTrendingRestaurantSearches(
      {int limit = 10}) async {
    return await getPopularSearches(limit: limit, searchType: 'restaurant');
  }

  // --- Vendor Visitor Tracking (real-time + per week) ---

  static String _getCurrentWeekKey() {
    final now = DateTime.now();
    final startOfWeek =
        now.subtract(Duration(days: now.weekday - 1));
    return '${startOfWeek.year}-W${startOfWeek.month.toString().padLeft(2, '0')}-${startOfWeek.day.toString().padLeft(2, '0')}';
  }

  /// Add active viewer session when user opens restaurant screen.
  Future<String?> addActiveViewerSession(String vendorId) async {
    try {
      if (vendorId.isEmpty) return null;

      final userId = auth.FirebaseAuth.instance.currentUser?.uid;
      // Avoid writes for unauthenticated users; Firestore rules often deny these.
      if (userId == null || userId.isEmpty) return null;

      final sessionId = const Uuid().v4();
      await firestore
          .collection(VENDOR_VIEWERS)
          .doc(vendorId)
          .collection('active')
          .doc(sessionId)
          .set({
        'userId': userId,
        'sessionId': sessionId,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      return sessionId;
    } catch (e) {
      // Do not spam logs for expected permission issues in guest mode.
      if (e.toString().contains('permission-denied')) return null;
      debugPrint('Error adding active viewer session: $e');
      return null;
    }
  }

  /// Remove active viewer session when user leaves restaurant screen.
  Future<void> removeActiveViewerSession(
      String vendorId, String sessionId) async {
    try {
      if (vendorId.isEmpty || sessionId.isEmpty) return;

      final userId = auth.FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) return;

      await firestore
          .collection(VENDOR_VIEWERS)
          .doc(vendorId)
          .collection('active')
          .doc(sessionId)
          .delete();
    } catch (e) {
      if (e.toString().contains('permission-denied')) return;
      debugPrint('Error removing active viewer session: $e');
    }
  }

  /// Increment weekly visit count when user opens restaurant screen.
  Future<void> incrementWeeklyVisitCount(String vendorId) async {
    try {
      if (vendorId.isEmpty) return;

      final userId = auth.FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) return;

      final weekKey = _getCurrentWeekKey();
      final docId = '${vendorId}_week_$weekKey';
      await firestore.collection(VENDOR_VISITS).doc(docId).set({
        'vendorId': vendorId,
        'weekKey': weekKey,
        'visitCount': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (e.toString().contains('permission-denied')) return;
      debugPrint('Error incrementing weekly visit count: $e');
    }
  }

  /// Stream of active viewer count (real-time "viewing now").
  Stream<int> getActiveViewerCountStream(String vendorId) {
    return firestore
        .collection(VENDOR_VIEWERS)
        .doc(vendorId)
        .collection('active')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Stream of weekly visit count.
  Stream<int> getWeeklyVisitCountStream(String vendorId) {
    final weekKey = _getCurrentWeekKey();
    final docId = '${vendorId}_week_$weekKey';
    return firestore
        .collection(VENDOR_VISITS)
        .doc(docId)
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (data == null || !snap.exists) return 0;
      final count = data['visitCount'];
      if (count == null) return 0;
      return count is int ? count : (count as num).toInt();
    });
  }

  // Cache for order counts
  static Map<String, int> _orderCountCache = {};
  static DateTime? _lastCacheUpdate;
  static const int _cacheExpiryMinutes = 5; // Cache expires after 5 minutes

  /// Get order count for a specific vendor with caching
  Future<int> getVendorOrderCount(String vendorID) async {
    if (vendorID.isEmpty) {
      return 0;
    }

    // Check cache first
    if (_orderCountCache.containsKey(vendorID) &&
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!).inMinutes <
            _cacheExpiryMinutes) {
      int cachedCount = _orderCountCache[vendorID]!;
      return cachedCount;
    }

    try {
      QuerySnapshot<Map<String, dynamic>> ordersQuery = await firestore
          .collection(ORDERS)
          .where('vendorID', isEqualTo: vendorID)
          .get();

      int orderCount = ordersQuery.docs.length;

      // Cache the result
      _orderCountCache[vendorID] = orderCount;
      _lastCacheUpdate = DateTime.now();

      return orderCount;
    } catch (e) {
      // Cache 0 as fallback
      _orderCountCache[vendorID] = 0;
      _lastCacheUpdate = DateTime.now();
      return 0;
    }
  }

  /// Get order count for multiple vendors efficiently
  static Future<Map<String, int>> getVendorOrderCounts(
      List<String> vendorIDs) async {
    Map<String, int> orderCounts = {};

    try {
      // Query all orders for the given vendor IDs
      QuerySnapshot<Map<String, dynamic>> ordersQuery = await firestore
          .collection(ORDERS)
          .where('vendorID', whereIn: vendorIDs)
          .get();

      // Count orders for each vendor
      for (var doc in ordersQuery.docs) {
        String vendorID = doc.data()['vendorID'] ?? '';
        if (vendorID.isNotEmpty) {
          orderCounts[vendorID] = (orderCounts[vendorID] ?? 0) + 1;
        }
      }

      // Ensure all vendor IDs are in the map (even with 0 orders)
      for (String vendorID in vendorIDs) {
        if (!orderCounts.containsKey(vendorID)) {
          orderCounts[vendorID] = 0;
        }
      }
    } catch (e) {
      print('Error getting vendor order counts: $e');
      // Initialize all vendors with 0 orders
      for (String vendorID in vendorIDs) {
        orderCounts[vendorID] = 0;
      }
    }

    return orderCounts;
  }

  /// Clear the order count cache
  static void clearOrderCountCache() {
    print('🔍 DEBUG: Clearing order count cache');
    _orderCountCache.clear();
    _lastCacheUpdate = null;
  }

  /// Get cache status for debugging
  static Map<String, dynamic> getCacheStatus() {
    return {
      'cacheSize': _orderCountCache.length,
      'lastUpdate': _lastCacheUpdate?.toString(),
      'isExpired': _lastCacheUpdate == null ||
          DateTime.now().difference(_lastCacheUpdate!).inMinutes >=
              _cacheExpiryMinutes,
      'cachedVendors': _orderCountCache.keys.toList(),
    };
  }

  /// Track banner events for analytics
  Future<void> trackBannerEvent({
    required String userId,
    required String eventType,
    required String orderId,
    String? orderStatus,
  }) async {
    try {
      await firestore.collection('banner_analytics').add({
        'userId': userId,
        'eventType': eventType,
        'orderId': orderId,
        'orderStatus': orderStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error tracking banner event: $e');
      // Don't throw - analytics failures shouldn't break the UI
    }
  }
}
