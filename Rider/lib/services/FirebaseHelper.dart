// ignore_for_file: close_sinks, cancel_subscriptions

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:foodie_driver/model/FlutterWaveSettingDataModel.dart';
import 'package:foodie_driver/model/MercadoPagoSettingsModel.dart';
import 'package:foodie_driver/model/PayFastSettingData.dart';
import 'package:foodie_driver/model/PayStackSettingsModel.dart';
import 'package:foodie_driver/model/conversation_model.dart';
import 'package:foodie_driver/services/fcm_v1_service.dart';
import 'package:foodie_driver/model/email_template_model.dart';
import 'package:foodie_driver/model/inbox_model.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/model/paypalSettingData.dart';
import 'package:foodie_driver/model/paytmSettingData.dart';
import 'package:foodie_driver/model/referral_model.dart';
import 'package:foodie_driver/model/stripeSettingData.dart';
import 'package:foodie_driver/model/topupTranHistory.dart';
import 'package:foodie_driver/userPrefrence.dart';
import 'package:http/http.dart' as http;
import 'package:map_launcher/map_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/BlockUserModel.dart';
import 'package:foodie_driver/model/ChatVideoContainer.dart';
import 'package:foodie_driver/model/CurrencyModel.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/model/VendorModel.dart';
import 'package:foodie_driver/model/withdrawHistoryModel.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/ui/reauthScreen/reauth_user_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
// Removed duplicate imports

import 'package:foodie_driver/resources/debug_log.dart';
import 'package:intl/intl.dart';

const String _cursorDebugLogPath =
    '/Users/sudimard/Downloads/Lalago/.cursor/debug.log';

Future<void> _appendCursorDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
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
    );
  } catch (_) {}
}

// Upload result class for progress streams
class UploadProgress {
  final double progress; // 0.0 to 1.0
  final Url? result;
  final ChatVideoContainer? videoResult;
  final String? error;

  UploadProgress({
    required this.progress,
    this.result,
    this.videoResult,
    this.error,
  });
}

class FireStoreUtils {
  static const String accessToken =
      "5d501215c9d0fae5e5c10289ec1cd2241319c833"; // Your Access Token (deprecated - now using OAuth)
  static const String projectId = "lalago-v2"; // Your Firebase Project ID
  static const String fcmUrl =
      "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";

  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();
  List<BlockUserModel> blockedList = [];

  // FCM v1 API message sender using OAuth 2.0
  static Future<void> sendFcmMessage({
    required String title,
    required String body,
    required String fcmToken,
  }) async {
    // Use FcmV1Service with proper OAuth 2.0 authentication
    await FcmV1Service.sendFcmMessage(
      title: title,
      body: body,
      fcmToken: fcmToken,
    );
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

  void cancelDriverStreamSubscription() {
    if (driverStreamSub != null) {
      driverStreamSub?.cancel();
      driverStreamSub = null; // Clean up reference
    }
  }

  late StreamController<User>? driverStreamController;
  late StreamSubscription? driverStreamSub;

  Stream<User> getDriver(String userId) {
    driverStreamController = StreamController<User>();

    driverStreamSub =
        firestore.collection(USERS).doc(userId).snapshots().listen((snapshot) {
      if (snapshot.data() != null) {
        User user = User.fromJson(snapshot.data()!);
        driverStreamController?.sink.add(user);
      }
    }, onError: (error) {
      driverStreamController?.sink.addError(error); // Handle errors
    });

    return driverStreamController!.stream;
  }

  /// Clean up resources
  void disposeDriverStream() {
    driverStreamSub?.cancel();
    driverStreamController?.close();
  }

  static Future<User?> getCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      final user = User.fromJson(userDocument.data()!);

      // Initialize performance score if not set for drivers
      if (user.role == USER_ROLE_DRIVER &&
          (user.driverPerformance == null || user.driverPerformance == 0)) {
        await _initializeDriverPerformance(uid);
        user.driverPerformance = 100.0;
      }

      return user;
    } else {
      return null;
    }
  }

  /// Initialize driver performance score if not exists
  static Future<void> _initializeDriverPerformance(String driverId) async {
    try {
      final doc = await firestore.collection(USERS).doc(driverId).get();
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      // Only initialize if driver_performance doesn't exist or is null
      if (!data.containsKey('driver_performance') ||
          data['driver_performance'] == null) {
        await firestore.collection(USERS).doc(driverId).update({
          'driver_performance': 100.0,
        });
      }
    } catch (e) {
      print('❌ Error initializing driver performance: $e');
    }
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

  /// Refreshes FCM token (with iOS retries if null), saves to
  /// users/{riderId}.fcmToken and updates local user. Call on app start
  /// when rider is already logged in and from onTokenRefresh.
  static Future<bool> refreshAndSaveFcmTokenIfLoggedIn() async {
    final user = MyAppState.currentUser;
    if (user == null || user.userID.isEmpty) {
      dlog('[FCM_TOKEN] Refresh skipped: no logged-in rider');
      return false;
    }
    if (user.role != USER_ROLE_DRIVER) {
      dlog('[FCM_TOKEN] Refresh skipped: user is not driver');
      return false;
    }

    String? token = await _getFcmTokenWithRetry();
    if (token == null || token.isEmpty) {
      dlog('[FCM_TOKEN] No token obtained after retries; riderId=${user.userID}');
      return false;
    }

    final preview = token.length > 24
        ? '${token.substring(0, 12)}...${token.substring(token.length - 4)}'
        : '***';
    dlog('[FCM_TOKEN] Token generated, saving to users/${user.userID}.fcmToken');
    dlog('[FCM_TOKEN] Token preview: $preview');
    return await saveFcmTokenForCurrentUser(token);
  }

  /// Gets FCM token; on iOS retries at 2s, 5s, 10s, 15s if null.
  static Future<String?> _getFcmTokenWithRetry() async {
    const delays = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 15)];
    for (var i = 0; i < delays.length; i++) {
      if (delays[i] > Duration.zero) {
        await Future<void>.delayed(delays[i]);
      }
      try {
        final token = await firebaseMessaging.getToken();
        if (token != null && token.isNotEmpty) {
          if (i > 0) {
            dlog('[FCM_TOKEN] Token obtained after ${i} retry(ies)');
          }
          return token;
        }
      } catch (e) {
        dlog('[FCM_TOKEN] getToken attempt ${i + 1} failed: $e');
      }
      if (Platform.isIOS) {
        dlog('[FCM_TOKEN] iOS: token null, next retry in ${i < delays.length - 1 ? delays[i + 1].inSeconds : 0}s');
      }
    }
    return null;
  }

  /// Saves the given FCM token to users/{riderId}.fcmToken and updates
  /// local user. Use when onTokenRefresh fires with a new token.
  static Future<bool> saveFcmTokenForCurrentUser(String newToken) async {
    final user = MyAppState.currentUser;
    if (user == null || user.userID.isEmpty) {
      dlog('[FCM_TOKEN] Save skipped: no logged-in rider');
      return false;
    }
    if (newToken.isEmpty) return false;

    user.fcmToken = newToken;
    try {
      await updateCurrentUser(user);
      MyAppState.currentUser = user;
      dlog('[FCM_TOKEN] Token saved to users/${user.userID}.fcmToken (refreshed)');
      return true;
    } catch (e) {
      dlog('[FCM_TOKEN] Failed to save token: $e');
      return false;
    }
  }

  static Future<User?> updateCurrentUser(User user) async {
    // Strip wallet-related and server-owned fields so generic merges do not
    // overwrite server/admin data (e.g. driver_performance from Admin edits).
    final sanitized = Map<String, dynamic>.from(user.toJson());
    const serverOwnedKeys = <String>{
      'wallet_amount',
      'wallet_credit',
      'payoutRequests',
      'transmitRequests',
      'todayVoucherEarned',
      'totalVouchers',
      'driver_performance',
    };
    serverOwnedKeys.forEach(sanitized.remove);

    return await firestore
        .collection(USERS)
        .doc(user.userID)
        .set(sanitized, SetOptions(merge: true))
        .then((document) {
      return user;
    });
  }

  /// Update lastActivityTimestamp for rider inactivity tracking.
  static Future<void> touchLastActivity(String userId) async {
    await firestore.collection(USERS).doc(userId).update({
      'lastActivityTimestamp': FieldValue.serverTimestamp(),
    });
  }

  static const String _defaultContactEmail = 'alshidarabdelnasir19@gmail.com';

  static Map<String, dynamic>? _contactUsCache;
  static DateTime? _contactUsCachedAt;
  static const Duration _contactUsCacheValidity = Duration(hours: 1);

  getContactUs() async {
    final now = DateTime.now();
    if (_contactUsCache != null &&
        _contactUsCachedAt != null &&
        now.difference(_contactUsCachedAt!) < _contactUsCacheValidity) {
      return _contactUsCache!;
    }
    final defaults = <String, dynamic>{
      'Address': '',
      'Phone': '',
      'Email': _defaultContactEmail,
      'Location': '',
    };
    final snapshot =
        await firestore.collection(Setting).doc(CONTACT_US).get();
    final data = snapshot.data();
    if (data == null || data.isEmpty) {
      _contactUsCache = defaults;
      _contactUsCachedAt = now;
      return defaults;
    }
    final email = data['Email']?.toString().trim() ?? '';
    final result = {
      'Address': data['Address']?.toString() ?? '',
      'Phone': data['Phone']?.toString() ?? '',
      'Location': data['Location']?.toString() ?? '',
      'Email': email.isEmpty ? _defaultContactEmail : email,
    };
    _contactUsCache = result;
    _contactUsCachedAt = now;
    return result;
  }

  static Future createPaymentId({collectionName = "wallet"}) async {
    DocumentReference documentReference =
        firestore.collection(collectionName).doc();
    final paymentId = documentReference.id;
    UserPreference.setPaymentId(paymentId: paymentId);
    return paymentId;
  }

  static Future withdrawWalletAmount(
      {required WithdrawHistoryModel withdrawHistory}) async {
    print("this is te payment id");
    print(withdrawHistory.id);
    print(MyAppState.currentUser!.userID);
    await firestore
        .collection(driverPayouts)
        .doc(withdrawHistory.id)
        .set(withdrawHistory.toJson())
        .then((value) {
      firestore
          .collection(driverPayouts)
          .doc(withdrawHistory.id)
          .get()
          .then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print(documentData.data());
      });
    });
    return "updated Amount";
  }

  static Future updateWalletAmount(
      {required String userId, required amount}) async {
    dynamic walletAmount = 0;
    try {
      final userRef = firestore.collection(USERS).doc(userId);

      await firestore.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);

        if (!userSnap.exists || userSnap.data() == null) {
          throw Exception('User document does not exist');
        }

        final currentWallet =
            (userSnap.data()?['wallet_amount'] ?? 0.0).toDouble();
        final newWallet = currentWallet + amount;

        tx.update(userRef, {
          'wallet_amount': newWallet,
        });
      });

      // Refresh current user after successful transaction
      final newUserDocument =
          await firestore.collection(USERS).doc(userId).get();
      if (newUserDocument.exists && newUserDocument.data() != null) {
        MyAppState.currentUser = User.fromJson(newUserDocument.data()!);
        print(MyAppState.currentUser);
      }

      print("data val");
      print(walletAmount);
      return walletAmount;
    } catch (error) {
      print('Error updating wallet: $error');
      if (error.toString().contains(
          "Bad state: field does not exist within the DocumentSnapshotPlatform")) {
        print("does not exist");
      } else {
        print("went wrong!!");
        walletAmount = "ERROR";
      }
      return walletAmount;
    }
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

  static sendPayoutMail(
      {required String amount, required String payoutrequestid}) async {
    EmailTemplateModel? emailTemplateModel =
        await FireStoreUtils.getEmailTemplates(payoutRequest);

    String body = emailTemplateModel!.subject.toString();
    body = body.replaceAll("{userid}", MyAppState.currentUser!.userID);

    String newString = emailTemplateModel.message.toString();
    newString = newString.replaceAll("{username}",
        MyAppState.currentUser!.firstName + MyAppState.currentUser!.lastName);
    newString =
        newString.replaceAll("{userid}", MyAppState.currentUser!.userID);
    newString = newString.replaceAll("{amount}", amountShow(amount: amount));
    newString =
        newString.replaceAll("{payoutrequestid}", payoutrequestid.toString());
    newString = newString.replaceAll("{usercontactinfo}",
        "${MyAppState.currentUser!.email}\n${MyAppState.currentUser!.phoneNumber}");
    await sendMail(
        subject: body,
        isAdmin: emailTemplateModel.isSendToAdmin,
        body: newString,
        recipients: [MyAppState.currentUser!.email]);
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

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore
        .collection(VENDORS)
        .doc(vendor.id)
        .set(vendor.toJson())
        .then((document) {
      return vendor;
    });
  }

  static Future<VendorModel?> getVendor(String vid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(VENDORS).doc(vid).get();
    if (userDocument.data() != null && userDocument.exists) {
      print("dataaaaaa");
      return VendorModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  static Future<String> uploadUserImageToFireStorage(
      File image, String userID) async {
    try {
      Reference upload = storage.child('images/$userID.png');
      File compressedImage = await FireStoreUtils.compressImage(image);

      UploadTask uploadTask = upload.putFile(compressedImage);

      // Add progress tracking
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        print(
            'User image upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      var downloadUrl =
          await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
      return downloadUrl.toString();
    } catch (e) {
      print('Error uploading user image: $e');
      throw Exception('Failed to upload user image: $e');
    }
  }

  static Future<String> uploadCarImageToFireStorage(
      File image, String userID) async {
    try {
      Reference upload =
          storage.child('uberEats/drivers/carImages/$userID.png');
      File compressedCarImage = await compressImage(image);

      UploadTask uploadTask = upload.putFile(compressedCarImage);

      // Add progress tracking
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        print(
            'Car image upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      var downloadUrl =
          await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
      return downloadUrl.toString();
    } catch (e) {
      print('Error uploading car image: $e');
      throw Exception('Failed to upload car image: $e');
    }
  }

  Future<Url> uploadChatImageToFireStorage(
      File image, BuildContext context) async {
    try {
      // Check if user is authenticated
      final currentUser = auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be authenticated to upload images');
      }

      showProgress(context, 'Uploading image...', false);
      var uniqueID = Uuid().v4();
      Reference upload = storage.child('images/$uniqueID.png');
      File compressedImage = await compressImage(image);
      UploadTask uploadTask = upload.putFile(compressedImage);
      uploadTask.snapshotEvents.listen((event) {
        updateProgress(
            'Uploading image ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
            '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
            'KB');
      });
      await uploadTask.whenComplete(() {});
      var storageRef = (await uploadTask).ref;
      var downloadUrl = await storageRef.getDownloadURL();
      var metaData = await storageRef.getMetadata();
      hideProgress();
      return Url(
          mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
    } on FirebaseException catch (e) {
      hideProgress();
      print('Error uploading chat image: ${e.code} - ${e.message}');
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception(
            'Permission denied. Please check Firebase Storage rules.');
      }
      throw Exception('Failed to upload image: ${e.message}');
    } catch (e) {
      hideProgress();
      print('Error uploading chat image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<ChatVideoContainer> uploadChatVideoToFireStorage(
      File video, BuildContext context) async {
    try {
      // Check if user is authenticated
      final currentUser = auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be authenticated to upload videos');
      }

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
      await uploadTask.whenComplete(() {});
      var storageRef = (await uploadTask).ref;
      var downloadUrl = await storageRef.getDownloadURL();
      var metaData = await storageRef.getMetadata();
      final uint8list = await VideoThumbnail.thumbnailFile(
          video: downloadUrl,
          thumbnailPath: (await getTemporaryDirectory()).path,
          imageFormat: ImageFormat.PNG);
      final file = File(uint8list ?? '');
      String thumbnailDownloadUrl =
          await uploadVideoThumbnailToFireStorage(file);
      hideProgress();
      return ChatVideoContainer(
          videoUrl: Url(
              url: downloadUrl.toString(),
              mime: metaData.contentType ?? 'video'),
          thumbnailUrl: thumbnailDownloadUrl);
    } on FirebaseException catch (e) {
      hideProgress();
      print('Error uploading chat video: ${e.code} - ${e.message}');
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception(
            'Permission denied. Please check Firebase Storage rules.');
      }
      throw Exception('Failed to upload video: ${e.message}');
    } catch (e) {
      hideProgress();
      print('Error uploading chat video: $e');
      throw Exception('Failed to upload video: $e');
    }
  }

  Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    try {
      // Check if user is authenticated
      final currentUser = auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be authenticated to upload thumbnails');
      }

      var uniqueID = Uuid().v4();
      Reference upload = storage.child('thumbnails/$uniqueID.png');
      File compressedImage = await compressImage(file);
      UploadTask uploadTask = upload.putFile(compressedImage);
      await uploadTask.whenComplete(() {});
      var downloadUrl = (await uploadTask).ref.getDownloadURL();
      return (await downloadUrl).toString();
    } on FirebaseException catch (e) {
      print('Error uploading video thumbnail: ${e.code} - ${e.message}');
      throw Exception('Failed to upload thumbnail: ${e.message}');
    } catch (e) {
      print('Error uploading video thumbnail: $e');
      throw Exception('Failed to upload thumbnail: $e');
    }
  }

  // Upload image with progress stream (non-blocking, no UI progress)
  Stream<UploadProgress> uploadChatImageWithProgress(File image) async* {
    try {
      // Check if user is authenticated
      final currentUser = auth.FirebaseAuth.instance.currentUser;

      // Debug logging
      print('🔐 Auth Check - User ID: ${currentUser?.uid}');
      print('🔐 Auth Check - Email: ${currentUser?.email}');
      print('🔐 Auth Check - Is Anonymous: ${currentUser?.isAnonymous}');

      if (currentUser == null) {
        yield UploadProgress(
            progress: 0.0,
            error: 'User must be authenticated to upload images');
        return;
      }

      // Force refresh auth token to ensure it's current
      try {
        await currentUser.getIdToken(true);
        print('🔐 Auth token refreshed successfully');
      } catch (e) {
        print('⚠️ Warning: Could not refresh auth token: $e');
      }

      // Create a fresh Storage reference to ensure it uses current auth token
      final freshStorageRef = FirebaseStorage.instance.ref();

      var uniqueID = Uuid().v4();
      Reference upload = freshStorageRef.child('images/$uniqueID.png');

      // Image is already compressed in _handleImageSelection() before upload
      // No need to compress again here

      // Add metadata with content type
      SettableMetadata metadata = SettableMetadata(
        contentType: 'image/png',
      );

      UploadTask uploadTask = upload.putFile(image, metadata);

      // Stream progress updates
      await for (final snapshot in uploadTask.snapshotEvents) {
        if (snapshot.totalBytes > 0) {
          final progress =
              snapshot.bytesTransferred / snapshot.totalBytes.toDouble();
          yield UploadProgress(progress: progress);
        }
      }

      // Upload complete, get download URL
      var uploadedFileRef = (await uploadTask).ref;
      var downloadUrl = await uploadedFileRef.getDownloadURL();
      var metaData = await uploadedFileRef.getMetadata();
      final url = Url(
          mime: metaData.contentType ?? 'image', url: downloadUrl.toString());

      yield UploadProgress(progress: 1.0, result: url);
    } on FirebaseException catch (e) {
      print('Error uploading chat image: ${e.code} - ${e.message}');
      yield UploadProgress(
          progress: 0.0,
          error: e.code == 'unauthorized' || e.code == 'permission-denied'
              ? 'Permission denied. Please check Firebase Storage rules.'
              : 'Failed to upload image: ${e.message}');
    } catch (e) {
      print('Error uploading chat image: $e');
      yield UploadProgress(progress: 0.0, error: 'Failed to upload image: $e');
    }
  }

  // Upload video with progress stream (non-blocking, no UI progress)
  Stream<UploadProgress> uploadChatVideoWithProgress(File video) async* {
    try {
      // Check if user is authenticated
      final currentUser = auth.FirebaseAuth.instance.currentUser;

      // Debug logging
      print('🔐 Auth Check - User ID: ${currentUser?.uid}');
      print('🔐 Auth Check - Email: ${currentUser?.email}');
      print('🔐 Auth Check - Is Anonymous: ${currentUser?.isAnonymous}');

      if (currentUser == null) {
        yield UploadProgress(
            progress: 0.0,
            error: 'User must be authenticated to upload videos');
        return;
      }

      // Force refresh auth token to ensure it's current
      try {
        await currentUser.getIdToken(true);
        print('🔐 Auth token refreshed successfully');
      } catch (e) {
        print('⚠️ Warning: Could not refresh auth token: $e');
      }

      // Create a fresh Storage reference to ensure it uses current auth token
      final freshStorageRef = FirebaseStorage.instance.ref();

      var uniqueID = Uuid().v4();
      Reference upload = freshStorageRef.child('videos/$uniqueID.mp4');
      File compressedVideo = await _compressVideo(video);
      SettableMetadata metadata = SettableMetadata(contentType: 'video/mp4');
      UploadTask uploadTask = upload.putFile(compressedVideo, metadata);

      // Stream progress updates
      await for (final snapshot in uploadTask.snapshotEvents) {
        if (snapshot.totalBytes > 0) {
          final progress =
              snapshot.bytesTransferred / snapshot.totalBytes.toDouble();
          yield UploadProgress(progress: progress);
        }
      }

      // Upload complete, get download URL
      var uploadedFileRef = (await uploadTask).ref;
      var downloadUrl = await uploadedFileRef.getDownloadURL();
      var metaData = await uploadedFileRef.getMetadata();

      // Generate thumbnail
      final uint8list = await VideoThumbnail.thumbnailFile(
          video: downloadUrl,
          thumbnailPath: (await getTemporaryDirectory()).path,
          imageFormat: ImageFormat.PNG);
      final file = File(uint8list ?? '');
      String thumbnailDownloadUrl =
          await uploadVideoThumbnailToFireStorage(file);

      final videoContainer = ChatVideoContainer(
          videoUrl: Url(
              url: downloadUrl.toString(),
              mime: metaData.contentType ?? 'video'),
          thumbnailUrl: thumbnailDownloadUrl);

      yield UploadProgress(progress: 1.0, videoResult: videoContainer);
    } on FirebaseException catch (e) {
      print('Error uploading chat video: ${e.code} - ${e.message}');
      yield UploadProgress(
          progress: 0.0,
          error: e.code == 'unauthorized' || e.code == 'permission-denied'
              ? 'Permission denied. Please check Firebase Storage rules.'
              : 'Failed to upload video: ${e.message}');
    } catch (e) {
      print('Error uploading chat video: $e');
      yield UploadProgress(progress: 0.0, error: 'Failed to upload video: $e');
    }
  }

  Stream<User> getUserByID(String id) async* {
    StreamController<User> userStreamController = StreamController();
    firestore.collection(USERS).doc(id).snapshots().listen((user) {
      try {
        User userModel = User.fromJson(user.data() ?? {});
        userStreamController.sink.add(userModel);
      } catch (e) {
        print(
            'FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* userStreamController.stream;
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

  Stream<bool> getBlocks() async* {
    StreamController<bool> refreshStreamController = StreamController();
    firestore
        .collection(REPORTS)
        .where('source', isEqualTo: MyAppState.currentUser!.userID)
        .snapshots()
        .listen((onData) {
      List<BlockUserModel> list = [];
      for (DocumentSnapshot<Map<String, dynamic>> block in onData.docs) {
        list.add(BlockUserModel.fromJson(block.data() ?? {}));
      }
      blockedList = list;
      refreshStreamController.sink.add(true);
    });
    yield* refreshStreamController.stream;
  }

  bool validateIfUserBlocked(String userID) {
    for (BlockUserModel blockedUser in blockedList) {
      if (userID == blockedUser.dest) {
        return true;
      }
    }
    return false;
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
    uploadTask.whenComplete(() {});
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(
        mime: metaData.contentType ?? 'audio', url: downloadUrl.toString());
  }

  Future<List<OrderModel>> getDriverOrders(String userID) async {
    try {
      final snapshot = await firestore
          .collection(ORDERS)
          .where('driverID', isEqualTo: userID)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      // 🐞 DEBUG: log count and statuses of all fetched orders
      final statuses =
          snapshot.docs.map((d) => d.data()['status'] ?? 'no-status').toList();
      print(
          'getDriverOrders: fetched ${snapshot.docs.length} orders with statuses: $statuses');

      return snapshot.docs
          .map((doc) {
            try {
              final order = OrderModel.fromJson(doc.data());
              order.id = doc.id;
              return order;
            } catch (e, st) {
              print('getDriverOrders parse error (${doc.id}): $e\n$st');
              return null;
            }
          })
          .whereType<OrderModel>()
          .toList();
    } catch (e, st) {
      print('getDriverOrders query failed: $e\n$st');
      return [];
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserObject(
      String userID) async* {
    yield* firestore.collection(USERS).doc(userID).snapshots();
  }

  static Future updateOrder(OrderModel orderModel) async {
    await firestore
        .collection(ORDERS)
        .doc(orderModel.id)
        .set(orderModel.toJson(), SetOptions(merge: true));
  }

  static Future<bool> getFirestOrderOrNOt(OrderModel orderModel) async {
    bool isFirst = true;
    await firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: orderModel.authorID)
        .get()
        .then((value) {
      if (value.size == 1) {
        isFirst = true;
      } else {
        isFirst = false;
      }
    });
    return isFirst;
  }

  static Future updateReferralAmount(OrderModel orderModel) async {
    ReferralModel? referralModel;
    print(orderModel.authorID);
    await firestore
        .collection(REFERRAL)
        .doc(orderModel.authorID)
        .get()
        .then((value) {
      if (value.data() != null) {
        referralModel = ReferralModel.fromJson(value.data()!);
      } else {
        return;
      }
    });
    if (referralModel != null) {
      if (referralModel!.referralBy != null &&
          referralModel!.referralBy!.isNotEmpty) {
        await firestore
            .collection(USERS)
            .doc(referralModel!.referralBy)
            .get()
            .then((value) async {
          DocumentSnapshot<Map<String, dynamic>> userDocument = value;
          if (userDocument.data() != null && userDocument.exists) {
            try {
              print(userDocument.data());
              User user = User.fromJson(userDocument.data()!);
              await firestore.collection(USERS).doc(user.userID).update({
                "wallet_amount":
                    user.walletAmount + double.parse(referralAmount.toString())
              }).then((value) => print("north"));

              await FireStoreUtils.createPaymentId().then((value) async {
                final paymentID = value;
                await FireStoreUtils.topUpWalletAmountRefral(
                    paymentMethod: "Referral Amount",
                    amount: double.parse(referralAmount.toString()),
                    id: paymentID,
                    userId: referralModel!.referralBy,
                    note:
                        "You referral user has complete his this order #${orderModel.id}");
              });
            } catch (error) {
              print(error);
              if (error.toString() ==
                  "Bad state: field does not exist within the DocumentSnapshotPlatform") {
                print("does not exist");
                //await firestore.collection(USERS).doc(userId).update({"wallet_amount": 0});
                //walletAmount = 0;
              } else {
                print("went wrong!!");
              }
            }
            print("data val");
          }
        });
      } else {
        return;
      }
    }
  }

  late StreamController<OrderModel> ordersStreamController;
  late StreamSubscription ordersStreamSub;

  Stream<OrderModel?> getOrderByID(String inProgressOrderID) async* {
    ordersStreamController = StreamController();
    ordersStreamSub = firestore
        .collection(ORDERS)
        .doc(inProgressOrderID)
        .snapshots()
        .listen((onData) async {
      if (onData.data() != null) {
        OrderModel? orderModel = OrderModel.fromJson(onData.data()!);
        ordersStreamController.sink.add(orderModel);
      }
    });
    yield* ordersStreamController.stream;
  }

  /// compress image file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the image after
  /// being compressed(100 = max quality - 0 = low quality)
  /// @param file the image file that will be compressed
  /// @return File a new compressed file with smaller size
  static Future<File> compressImage(File file) async {
    try {
      final targetPath = '${file.path}_compressed.jpg';
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 800,
        minHeight: 600,
        quality: 70,
      );
      if (result != null) {
        final targetFile = File(targetPath);
        await targetFile.writeAsBytes(result);
        return targetFile;
      } else {
        return file;
      }
    } catch (e) {
      print('Error compressing image: $e');
      // Return original file if compression fails
      return file;
    }
  }

  /// compress video file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the video after
  /// being compressed
  /// @param file the video file that will be compressed
  /// @return File a new compressed file with smaller size
  Future<File> _compressVideo(File file) async {
    MediaInfo? info = await VideoCompress.compressVideo(file.path,
        quality: VideoQuality.DefaultQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 24);
    if (info != null) {
      File compressedVideo = File(info.path!);
      return compressedVideo;
    } else {
      return file;
    }
  }

  //static loginWithFacebook() async {
  //  /// creates a user for this facebook login when this user first time login
  //  /// and save the new user object to firebase and firebase auth
  //  FacebookAuth facebookAuth = FacebookAuth.instance;
  //  bool isLogged = await facebookAuth.accessToken != null;
  //  if (!isLogged) {
  //    LoginResult result = await facebookAuth
  //        .login(); // by default we request the email and the public profile
  //    if (result.status == LoginStatus.success) {
  //      // you are logged
  //      AccessToken? token = await facebookAuth.accessToken;
  //      return await handleFacebookLogin(
  //          await facebookAuth.getUserData(), token!);
  //    }
  //  } else {
  //    AccessToken? token = await facebookAuth.accessToken;
  //    return await handleFacebookLogin(
  //        await facebookAuth.getUserData(), token!);
  //  }
  //}

  //static handleFacebookLogin(
  //    //Map<String, dynamic> userData, AccessToken token) async {
  //  auth.UserCredential authResult = await auth.FirebaseAuth.instance
  //      .signInWithCredential(
  //          auth.FacebookAuthProvider.credential(token.token));
  //  print(authResult.user!.uid);
  //  User? user = await getCurrentUser(authResult.user?.uid ?? '');
  //  List<String> fullName = (userData['name'] as String).split(' ');
  //  String firstName = '';
  //  String lastName = '';
  //  if (fullName.isNotEmpty) {
  //    firstName = fullName.first;
  //    lastName = fullName.skip(1).join(' ');
  //  }
  //  if (user != null && user.role == USER_ROLE_DRIVER) {
  //    print('if');
  //    user.profilePictureURL = userData['picture']['data']['url'];
  //    user.firstName = firstName;
  //    user.lastName = lastName;
  //    user.email = userData['email'];
  //    user.isActive = false;
  //    user.role = USER_ROLE_DRIVER;
  //    user.fcmToken = await firebaseMessaging.getToken() ?? '';
  //    dynamic result = await updateCurrentUser(user);
  //    return result;
  //  } else if (user == null) {
  //    print('else');
  //    user = User(
  //        email: userData['email'] ?? '',
  //        firstName: firstName,
  //        profilePictureURL: userData['picture']['data']['url'] ?? '',
  //        userID: authResult.user?.uid ?? '',
  //        lastOnlineTimestamp: Timestamp.now(),
  //        lastName: lastName,
  //        isActive: false,
  //        active: true,
  //        role: USER_ROLE_DRIVER,
  //        fcmToken: await firebaseMessaging.getToken() ?? '',
  //        phoneNumber: '',
  //        carName: 'Uber Car',
  //        carNumber: 'No Plates',
  //        carPictureURL: DEFAULT_CAR_IMAGE,
  //        createdAt: Timestamp.now(),
  //        settings: UserSettings());
  //    String? errorMessage = await firebaseCreateNewUser(user);
  //    if (errorMessage == null) {
  //      return user;
  //    } else {
  //      return errorMessage;
  //    }
  //  }
  //}

  static loginWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final auth.AuthCredential credential =
          auth.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      return await handleAppleLogin(credential, appleCredential);
    } catch (e) {
      return 'Couldn\'t login with apple.';
    }
  }

  static handleAppleLogin(
    auth.AuthCredential credential,
    AuthorizationCredentialAppleID appleIdCredential,
  ) async {
    auth.UserCredential authResult =
        await auth.FirebaseAuth.instance.signInWithCredential(credential);
    User? user = await getCurrentUser(authResult.user?.uid ?? '');
    if (user != null) {
      //user.isActive = false;
      user.role = USER_ROLE_DRIVER;
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      dynamic result = await updateCurrentUser(user);
      return result;
    } else {
      user = User(
          email: appleIdCredential.email ?? '',
          firstName: appleIdCredential.givenName ?? '',
          profilePictureURL: '',
          userID: authResult.user?.uid ?? '',
          lastOnlineTimestamp: Timestamp.now(),
          lastName: appleIdCredential.familyName ?? '',
          role: USER_ROLE_DRIVER,
          isActive: false,
          active: true,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          phoneNumber: '',
          carName: 'Uber Car',
          carNumber: 'No Plates',
          carPictureURL: DEFAULT_CAR_IMAGE,
          createdAt: Timestamp.now(),
          settings: UserSettings());
      String? errorMessage = await firebaseCreateNewUser(user);
      if (errorMessage == null) {
        return user;
      } else {
        return errorMessage;
      }
    }
  }

  static loginWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        return 'Couldn\'t login with google.';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final auth.AuthCredential credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await handleGoogleLogin(credential, googleUser);
    } catch (e, s) {
      print('FireStoreUtils.loginWithGoogle $e $s');
      return 'Couldn\'t login with google.';
    }
  }

  static handleGoogleLogin(
    auth.AuthCredential credential,
    GoogleSignInAccount googleUser,
  ) async {
    auth.UserCredential authResult =
        await auth.FirebaseAuth.instance.signInWithCredential(credential);
    User? user = await getCurrentUser(authResult.user?.uid ?? '');

    if (user != null) {
      user.role = USER_ROLE_DRIVER;
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      dynamic result = await updateCurrentUser(user);
      return result;
    } else {
      final displayName = googleUser.displayName ?? '';
      final nameParts = displayName.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      user = User(
        email: googleUser.email,
        firstName: firstName,
        profilePictureURL: googleUser.photoUrl ?? '',
        userID: authResult.user?.uid ?? '',
        lastOnlineTimestamp: Timestamp.now(),
        lastName: lastName,
        role: USER_ROLE_DRIVER,
        isActive: false,
        active: true,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        phoneNumber: '',
        carName: 'Uber Car',
        carNumber: 'No Plates',
        carPictureURL: DEFAULT_CAR_IMAGE,
        createdAt: Timestamp.now(),
        settings: UserSettings(),
      );
      String? errorMessage = await firebaseCreateNewUser(user);
      if (errorMessage == null) {
        return user;
      } else {
        return errorMessage;
      }
    }
  }

  /// save a new user document in the USERS table in firebase firestore
  /// returns an error message on failure or null on success
  static Future<String?> firebaseCreateNewUser(User user) async {
    try {
      final json = user.toJson();
      if (user.role == USER_ROLE_DRIVER) {
        json['riderAvailability'] = user.riderAvailability ?? 'offline';
        json['riderDisplayStatus'] =
            user.riderDisplayStatus ?? '\u{26AA} Offline';
        json['checkedInToday'] = user.checkedInToday ?? false;
        json['isOnline'] = user.isOnline ?? false;
      }
      await firestore.collection(USERS).doc(user.userID).set(json);
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return "notSignIn";
    }
    return null;
  }

  /// login with email and password with firebase
  /// @param email user email
  /// @param password user password
  /// Logs in with email & password.
  /// Returns a User on success, or a String error message on failure.
  /// Logs in with email & password.
  /// Returns a User on success, or a String error message on failure.
  /// Attempt sign-in; on success returns a User, on failure returns an error message.
  static Future<dynamic> loginWithEmailAndPassword(
      String email, String password) async {
    try {
      dlog(
          'FireStoreUtils.loginWithEmailAndPassword - start. email: <$email>, password length: ${password.length}');

      if (email.isEmpty || password.isEmpty) {
        return 'Email or password cannot be empty.';
      }

      final auth.UserCredential result = await auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final String uid = result.user?.uid ?? '';
      if (uid.isEmpty) {
        dlog('LOGIN DEBUG: authResult.user.uid is null or empty');
        return 'Authentication failed. No user returned.';
      }
      dlog('LOGIN DEBUG: FirebaseAuth sign-in succeeded. UID: $uid');

      final DocumentSnapshot<Map<String, dynamic>> documentSnapshot =
          await firestore.collection(USERS).doc(uid).get();
      if (!documentSnapshot.exists || documentSnapshot.data() == null) {
        return 'User record not found. Please contact support.';
      }

      User? user;
      try {
        user = User.fromJson(documentSnapshot.data()!);
      } catch (parseErr) {
        dlog('LOGIN DEBUG: failed to parse user: $parseErr');
        return 'Failed to parse user data.';
      }

      // Initialize performance score if not set
      if (user.role == USER_ROLE_DRIVER &&
          (user.driverPerformance == null || user.driverPerformance == 0)) {
        await _initializeDriverPerformance(uid);
        user.driverPerformance = 100.0;
      }

      // Try to get FCM token, but don't fail login if it fails
      // Wrap in a separate try-catch to ensure it doesn't block login
      String? fcmToken;
      try {
        fcmToken = await firebaseMessaging.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          user.fcmToken = fcmToken;
          dlog(
              'LOGIN DEBUG: FCM token retrieved successfully: ${fcmToken.substring(0, 20)}...');
        } else {
          dlog(
              'LOGIN DEBUG: FCM token is null or empty, keeping existing token');
        }
      } catch (fcmError) {
        dlog('LOGIN DEBUG: Failed to get FCM token (non-fatal): $fcmError');
        // Keep existing FCM token from user object, don't fail login
        // FCM token can be updated later if needed
      }

      dlog(
          'LOGIN DEBUG: returning User object with active=${user.active}, isActive=${user.isActive}, combined=${user.isReallyActive}, role=${user.role}');

      try {
        await AttendanceService.evaluateAndUpdateAttendance(user);
        await AttendanceService.touchLastActiveDate(user);
      } catch (e) {
        dlog('LOGIN DEBUG: attendance update failed: $e');
      }

      return user;
    } on auth.FirebaseAuthException catch (exception, s) {
      elog(exception, s, 'AUTH');
      switch (exception.code) {
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
        case 'operation-not-allowed':
          return 'Email/password sign-in is not enabled.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection and try again.';
        default:
          // Check for network-related errors in the message
          final errorMessage = exception.message ?? '';
          if (errorMessage.contains('Failed to connect') ||
              errorMessage.contains('network') ||
              errorMessage.contains('connection') ||
              errorMessage.contains('timeout')) {
            return 'Network error. Please check your internet connection and try again.';
          }
          return errorMessage.isNotEmpty
              ? errorMessage
              : 'Unexpected firebase error, Please try again.';
      }
    } catch (e, s) {
      elog(e, s, 'LOGIN');

      // Check if this is an FCM token error - don't fail login for this
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('firebase_messaging') ||
          errorString.contains('fcm') ||
          errorString.contains('authentication_failed') ||
          errorString.contains('messaging')) {
        dlog(
            'LOGIN DEBUG: FCM-related error detected in outer catch. Continuing login anyway.');
        // Try to get user anyway and return it without FCM token update
        try {
          final uid = (await auth.FirebaseAuth.instance.currentUser)?.uid;
          if (uid != null && uid.isNotEmpty) {
            final DocumentSnapshot<Map<String, dynamic>> docSnapshot =
                await firestore.collection(USERS).doc(uid).get();
            if (docSnapshot.exists && docSnapshot.data() != null) {
              final User user = User.fromJson(docSnapshot.data()!);
              dlog('LOGIN DEBUG: Returning user despite FCM error');
              return user;
            }
          }
        } catch (_) {
          // If we can't get user, fall through to error message
        }
      }

      // Check for network-related errors in generic catch
      if (errorString.contains('failed to connect') ||
          errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout') ||
          errorString.contains('socket')) {
        return 'Network error. Please check your internet connection and try again.';
      }
      return 'Login failed, Please try again.';
    }
  }

  ///submit a phone number to firebase to receive a code verification, will
  ///be used later to login
  static firebaseSubmitPhoneNumber(
    String phoneNumber,
    auth.PhoneCodeAutoRetrievalTimeout? phoneCodeAutoRetrievalTimeout,
    auth.PhoneCodeSent? phoneCodeSent,
    auth.PhoneVerificationFailed? phoneVerificationFailed,
    auth.PhoneVerificationCompleted? phoneVerificationCompleted,
  ) {
    // #region agent log
    _appendCursorDebugLog(
      hypothesisId: 'H1',
      location: 'FirebaseHelper.firebaseSubmitPhoneNumber:entry',
      message: 'verifyPhoneNumber start',
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
        _appendCursorDebugLog(
          hypothesisId: 'H3',
          location: 'FirebaseHelper.firebaseSubmitPhoneNumber:verificationFailed',
          message: 'verifyPhoneNumber failed',
          data: <String, Object?>{
            'errorCode': error.code,
          },
        );
        // #endregion
        if (onVerificationFailed != null) {
          onVerificationFailed(error);
        }
      },
      codeSent: (String verificationId, int? forceResendingToken) {
        // #region agent log
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
  static Future<dynamic> firebaseSubmitPhoneNumberCode(
      String verificationID, String code, String phoneNumber,
      {String firstName = 'Anonymous',
      String lastName = 'User',
      File? image,
      File? carImage,
      String carName = '',
      String carPlates = ''}) async {
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
        'roleMatch': user?.role == USER_ROLE_DRIVER,
      },
    );
    // #endregion
    if (user != null && user.role == USER_ROLE_DRIVER) {
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      user.role = USER_ROLE_DRIVER;
      user.isActive = true;
      await updateCurrentUser(user);
      return user;
    } else if (user == null) {
      /// create a new user from phone login
      String profileImageUrl = '';
      String carPicUrl = DEFAULT_CAR_IMAGE;
      if (image != null) {
        profileImageUrl = await uploadUserImageToFireStorage(
            image, userCredential.user?.uid ?? '');
      }
      if (carImage != null) {
        updateProgress('Uploading car image, Please wait...');
        carPicUrl = await uploadCarImageToFireStorage(
            carImage, userCredential.user?.uid ?? '');
      }
      User user = User(
        firstName: firstName,
        lastName: lastName,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        phoneNumber: phoneNumber,
        profilePictureURL: profileImageUrl,
        userID: userCredential.user?.uid ?? '',
        isActive: true,
        active: true,
        lastOnlineTimestamp: Timestamp.now(),
        settings: UserSettings(),
        email: '',
        role: USER_ROLE_DRIVER,
        carName: carName,
        carNumber: carPlates,
        carPictureURL: carPicUrl,
        createdAt: Timestamp.now(),
      );
      String? errorMessage = await firebaseCreateNewUser(user);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t create new user with phone number.';
      }
    }
  }

  static firebaseSignUpWithEmailAndPassword(
      String emailAddress,
      String password,
      File? image,
      File? carImage,
      String carName,
      String carPlate,
      String firstName,
      String lastName,
      String mobile) async {
    try {
      auth.UserCredential result = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: emailAddress, password: password);
      String profilePicUrl = '';
      String carPicUrl = DEFAULT_CAR_IMAGE;
      if (image != null) {
        updateProgress('Uploading image, Please wait...');
        profilePicUrl =
            await uploadUserImageToFireStorage(image, result.user?.uid ?? '');
      }
      if (carImage != null) {
        updateProgress('Uploading car image, Please wait...');
        carPicUrl =
            await uploadCarImageToFireStorage(carImage, result.user?.uid ?? '');
      }

      User user = User(
        email: emailAddress,
        settings: UserSettings(),
        lastOnlineTimestamp: Timestamp.now(),
        isActive: true,
        phoneNumber: mobile,
        firstName: firstName,
        userID: result.user?.uid ?? '',
        lastName: lastName,
        active: true,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        profilePictureURL: profilePicUrl,
        carPictureURL: carPicUrl,
        carNumber: carPlate,
        carName: carName,
        role: USER_ROLE_DRIVER,
        createdAt: Timestamp.now(),
      );
      String? errorMessage = await firebaseCreateNewUser(user);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t sign up for firebase, Please try again.';
      }
    } on auth.FirebaseAuthException catch (error) {
      print(error.toString() + '${error.stackTrace}');
      String message = 'Could not sign in. Please try again.';
      switch (error.code) {
        case 'email-already-in-use':
          message = "EmailAlreadyUseAnother";
          break;
        case 'invalid-email':
          message = 'Enter valid e-mail';
          break;
        case 'operation-not-allowed':
          message = "EmailPasswordAccountsNotEnabled";
          break;
        case 'weak-password':
          message = 'Password must be more than 5 characters';
          break;
        case 'too-many-requests':
          message = 'Too many requests, Please try again later.';
          break;
      }
      return message;
    } catch (e) {
      return "notSignIn";
    }
  }

  static Future<auth.UserCredential?> reAuthUser(AuthProviders provider,
      {String? email,
      String? password,
      String? smsCode,
      String? verificationId,
      //AccessToken? accessToken,
      AuthorizationCredentialAppleID? appleCredential}) async {
    late auth.AuthCredential credential;
    switch (provider) {
      case AuthProviders.PASSWORD:
        credential = auth.EmailAuthProvider.credential(
            email: email!, password: password!);
        break;
      case AuthProviders.PHONE:
        credential = auth.PhoneAuthProvider.credential(
            smsCode: smsCode!, verificationId: verificationId!);
        break;
      case AuthProviders.FACEBOOK:
        //credential = auth.FacebookAuthProvider.credential(accessToken!.token);
        break;
      case AuthProviders.APPLE:
        credential = auth.OAuthProvider('apple.com').credential(
          idToken: appleCredential!.identityToken,
          accessToken: appleCredential.authorizationCode,
        );
        break;
    }
    return await auth.FirebaseAuth.instance.currentUser!
        .reauthenticateWithCredential(credential);
  }

  static resetPassword(String emailAddress) async =>
      await auth.FirebaseAuth.instance
          .sendPasswordResetEmail(email: emailAddress);

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

  static Future<String> _getCloudFunctionRegion() async {
    try {
      // Try to fetch region from Firestore settings
      final regionDoc = await firestore
          .collection('settings')
          .doc('cloudFunctionsRegion')
          .get()
          .timeout(const Duration(seconds: 5));

      if (regionDoc.exists && regionDoc.data() != null) {
        final region = regionDoc.data()!['region'] as String?;
        if (region != null && region.isNotEmpty) {
          debugPrint(
              '[IndividualNotification] Using region from Firestore settings: $region');
          return region;
        }
      }
    } catch (e) {
      debugPrint(
          '[IndividualNotification] Error fetching region from Firestore: $e');
      // Continue to fallback
    }

    // Fallback: Default region
    debugPrint('[IndividualNotification] Using default region: us-central1');
    return 'us-central1';
  }

  static Future<void> _clearInvalidChatToken({
    required String token,
    String? customerId,
    String? orderId,
    String? tokenSource,
  }) async {
    if (token.isEmpty) {
      return;
    }

    if (tokenSource == 'order.author' &&
        orderId != null &&
        orderId.isNotEmpty) {
      try {
        await firestore
            .collection('restaurant_orders')
            .doc(orderId)
            .update({'author.fcmToken': FieldValue.delete()});
        debugPrint(
          '[IndividualNotification] Cleared invalid order.author fcmToken '
          'for orderId=$orderId',
        );
      } catch (e) {
        debugPrint(
          '[IndividualNotification] Failed clearing order.author token: $e',
        );
      }
    }

    if (customerId != null && customerId.isNotEmpty) {
      try {
        await firestore
            .collection('users')
            .doc(customerId)
            .update({'fcmToken': FieldValue.delete()});
        debugPrint(
          '[IndividualNotification] Cleared invalid user fcmToken '
          'for customerId=$customerId',
        );
      } catch (e) {
        debugPrint(
          '[IndividualNotification] Failed clearing user token: $e',
        );
      }
    }
  }

  static Future<bool> sendChatFcmMessage(
      String title, String message, String token,
      {String? orderId,
      String? orderStatus,
      String? senderRole,
      String? messageType,
      String? customerId,
      String? restaurantId,
      String? tokenSource}) async {
    try {
      // Get Firebase project ID
      final projectId = Firebase.app().options.projectId;

      // Get region dynamically from Firestore or use default
      final region = await _getCloudFunctionRegion();

      // Construct Cloud Function URL
      final functionUrl =
          'https://$region-$projectId.cloudfunctions.net/sendIndividualNotification';

      // Build data payload with order context
      final dataPayload = <String, dynamic>{
        'type': 'chat_message',
      };
      if (orderId != null) {
        dataPayload['orderId'] = orderId;
      }
      if (orderStatus != null) {
        dataPayload['orderStatus'] = orderStatus;
      }
      if (senderRole != null) {
        dataPayload['senderRole'] = senderRole;
      }
      if (messageType != null) {
        dataPayload['messageType'] = messageType;
      }
      if (customerId != null && customerId.isNotEmpty) {
        dataPayload['customerId'] = customerId;
      }
      if (restaurantId != null && restaurantId.isNotEmpty) {
        dataPayload['restaurantId'] = restaurantId;
      }

      // Build request payload
      final payload = <String, dynamic>{
        'title': title,
        'body': message,
        'token': token,
        'data': dataPayload,
      };
      if (customerId != null && customerId.isNotEmpty) {
        payload['customerId'] = customerId;
      }

      // Debug logs: customer ID, token source, and payload keys
      final payloadKeys = dataPayload.keys.toList()..sort();
      debugPrint(
          '[sendChatFcmMessage] Pre-send debug - resolvedCustomerId=${customerId ?? "null"}, tokenSource=${tokenSource ?? "unknown"}, payloadKeys=[${payloadKeys.join(", ")}]');
      debugPrint(
          '[FCM_DEBUG] Cloud Function send request: $functionUrl '
          'title=$title tokenPreview=${token.length > 20 ? "${token.substring(0, 12)}...${token.substring(token.length - 4)}" : "***"}');
      debugPrint('[IndividualNotification] Calling function URL: $functionUrl');
      debugPrint(
          '[IndividualNotification] Payload: title=$title, body=$message');

      // Call Cloud Function
      final response = await http
          .post(
            Uri.parse(functionUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint(
          '[IndividualNotification] Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final responseData =
              jsonDecode(response.body) as Map<String, dynamic>;
          final success = responseData['success'] ?? false;

          if (success) {
            final messageId = responseData['messageId'];
            debugPrint(
                '[IndividualNotification] Successfully sent: $messageId');
            return true;
          } else {
            final error = responseData['error'] ?? 'Unknown error';
            debugPrint(
                '[IndividualNotification] Function returned error: $error');
            if (error is String &&
                (error.contains('Requested entity was not found') ||
                    error.contains('not found'))) {
              await _clearInvalidChatToken(
                token: token,
                customerId: customerId,
                orderId: orderId,
                tokenSource: tokenSource,
              );
            }
            return false;
          }
        } catch (parseError) {
          debugPrint(
              '[IndividualNotification] Error parsing response JSON: $parseError');
          debugPrint(
              '[IndividualNotification] Response body: ${response.body}');
          return false;
        }
      } else {
        debugPrint(
            '[IndividualNotification] HTTP error status: ${response.statusCode}');
        debugPrint('[IndividualNotification] Response body: ${response.body}');

        // Check for specific error: "Requested entity was not found" = invalid FCM token
        try {
          final responseData =
              jsonDecode(response.body) as Map<String, dynamic>?;
          final errorMessage = responseData?['error'] as String? ?? '';
          if (errorMessage.contains('Requested entity was not found') ||
              errorMessage.contains('not found')) {
            debugPrint(
                '[IndividualNotification] FCM token is invalid or unregistered: ${token.substring(0, 20)}...');
            debugPrint(
                '[IndividualNotification] Token source: ${tokenSource ?? "unknown"}');
            debugPrint(
                '[IndividualNotification] Customer ID: ${customerId ?? "unknown"}');
            await _clearInvalidChatToken(
              token: token,
              customerId: customerId,
              orderId: orderId,
              tokenSource: tokenSource,
            );
          }
        } catch (e) {
          // Ignore JSON parse errors
        }

        return false;
      }
    } catch (e) {
      debugPrint('[IndividualNotification] Error: $e');
      return false;
    }
  }

  static Future topUpWalletAmountRefral(
      {String paymentMethod = "test",
      bool isTopup = true,
      required amount,
      required id,
      orderId = "",
      userId,
      note}) async {
    print("this is te payment id");
    print(id);
    print(userId);

    await firestore.collection(Wallet).doc(id).set({
      "user_id": userId,
      "payment_method": paymentMethod,
      "amount": amount,
      "id": id,
      "order_id": orderId,
      "isTopUp": isTopup,
      "payment_status": "success",
      "date": DateTime.now(),
      "transactionUser": "driver",
      "note": note,
    }).then((value) {
      firestore.collection(Wallet).doc(id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print("nato");
        print(documentData.data());
      });
    });

    return "updated Amount";
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
        transactionUser: "driver");

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

  static getPayFastSettingData() async {
    firestore
        .collection(Setting)
        .doc("payFastSettings")
        .get()
        .then((payFastData) {
      debugPrint(payFastData.data().toString());
      try {
        PayFastSettingData payFastSettingData =
            PayFastSettingData.fromJson(payFastData.data() ?? {});
        debugPrint(payFastData.toString());
        UserPreference.setPayFastData(payFastSettingData);
      } catch (error) {
        debugPrint("error>>>122");
        debugPrint(error.toString());
      }
    });
  }

  static getMercadoPagoSettingData() async {
    firestore.collection(Setting).doc("MercadoPago").get().then((mercadoPago) {
      try {
        MercadoPagoSettingData mercadoPagoDataModel =
            MercadoPagoSettingData.fromJson(mercadoPago.data() ?? {});
        UserPreference.setMercadoPago(mercadoPagoDataModel);
      } catch (error) {
        debugPrint(error.toString());
      }
    });
  }

  static getReferralAmount() async {
    try {
      print(MyAppState.currentUser!.userID);
      await firestore
          .collection(Setting)
          .doc("referral_amount")
          .get()
          .then((value) {
        referralAmount = value.data()!['referralAmount'];
      });
      await firestore
          .collection(Setting)
          .doc("DriverNearBy")
          .get()
          .then((value) {
        minimumDepositToRideAccept =
            value.data()!['minimumDepositToRideAccept'];
        minimumAmountToWithdrawal = value.data()!['minimumAmountToWithdrawal'];
      });
      print(referralAmount);
      print(minimumDepositToRideAccept);
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralAmount;
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

  static getStripeSettingData() async {
    firestore
        .collection(Setting)
        .doc("stripeSettings")
        .get()
        .then((stripeData) {
      try {
        StripeSettingData stripeSettingData =
            StripeSettingData.fromJson(stripeData.data() ?? {});
        UserPreference.setStripeData(stripeSettingData);
      } catch (error) {
        debugPrint(error.toString());
      }
    });
  }

  static getFlutterWaveSettingData() async {
    firestore
        .collection(Setting)
        .doc("flutterWave")
        .get()
        .then((flutterWaveData) {
      try {
        FlutterWaveSettingData flutterWaveSettingData =
            FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});
        UserPreference.setFlutterWaveData(flutterWaveSettingData);
      } catch (error) {
        debugPrint("error>>>122");
        debugPrint(error.toString());
      }
    });
  }

  static getPayStackSettingData() async {
    firestore.collection(Setting).doc("payStack").get().then((payStackData) {
      try {
        PayStackSettingData payStackSettingData =
            PayStackSettingData.fromJson(payStackData.data() ?? {});
        UserPreference.setPayStackData(payStackSettingData);
      } catch (error) {
        debugPrint("error>>>122");
        debugPrint(error.toString());
      }
    });
  }

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
        final data = walletSetting.data();
        final walletEnable = data != null && data['isEnabled'] == true;

        UserPreference.setWalletData(walletEnable);
      } catch (e) {
        debugPrint(e.toString());
      }
    });
  }

  static Future<OrderModel?> getOrderBuOrderId(String orderId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(ORDERS).doc(orderId).get();
    if (userDocument.data() != null && userDocument.exists) {
      print("dataaaaaa");
      return OrderModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  static redirectMap(
      {required BuildContext context,
      required String name,
      required double latitude,
      required double longLatitude}) async {
    if (mapType == "google") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.google);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.google,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'Google map is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    } else if (mapType == "googleGo") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.googleGo);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.googleGo,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'Google Go map is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    } else if (mapType == "waze") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.waze);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.waze,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'Waze is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    } else if (mapType == "mapswithme") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.mapswithme);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.mapswithme,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'Mapswithme is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    } else if (mapType == "yandexNavi") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.yandexNavi);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.yandexNavi,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'YandexNavi is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    } else if (mapType == "yandexMaps") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.yandexMaps);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.yandexMaps,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'yandexMaps map is not installed',
          style: TextStyle(fontSize: 17),
        )));
      }
    }
  }
}
