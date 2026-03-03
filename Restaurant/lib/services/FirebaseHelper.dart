// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/AttributesModel.dart';
import 'package:foodie_restaurant/model/BlockUserModel.dart';
import 'package:foodie_restaurant/model/ChatVideoContainer.dart';
import 'package:foodie_restaurant/model/CurrencyModel.dart';
import 'package:foodie_restaurant/model/DeliveryChargeModel.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/ProductModel.dart';
import 'package:foodie_restaurant/model/Ratingmodel.dart';
import 'package:foodie_restaurant/model/ReviewAttributeModel.dart';
import 'package:foodie_restaurant/model/TableModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';
import 'package:foodie_restaurant/model/categoryModel.dart';
import 'package:foodie_restaurant/model/conversation_model.dart';
import 'package:foodie_restaurant/model/email_template_model.dart';
import 'package:foodie_restaurant/model/inbox_model.dart';
import 'package:foodie_restaurant/model/notification_model.dart';
import 'package:foodie_restaurant/model/story_model.dart';
import 'package:foodie_restaurant/model/topupTranHistory.dart';
import 'package:foodie_restaurant/model/withdrawHistoryModel.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/DineIn/BookTableModel.dart';
import 'package:foodie_restaurant/ui/offer/offer_model/offer_model.dart';
import 'package:foodie_restaurant/ui/reauthScreen/reauth_user_screen.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:the_apple_sign_in/the_apple_sign_in.dart' as apple;
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class FireStoreUtils {
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();
  late StreamSubscription ordersStreamSub;
  late StreamController<List<OrderModel>> ordersStreamController;
  late StreamSubscription productsStreamSub;
  late StreamController<List<ProductModel>> productsStreamController;
  bool isShowLoader = true;

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

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrderStatus(
      String orderID) async* {
    yield* firestore.collection(ORDERS).doc(orderID).snapshots();
  }

  static Future<OrderModel?> getOrderById(String orderId) async {
    final doc =
        await firestore.collection(ORDERS).doc(orderId).get();
    if (!doc.exists || doc.data() == null) return null;
    try {
      final data = Map<String, dynamic>.from(doc.data()!);
      data['id'] = doc.id;
      return OrderModel.fromJson(data);
    } catch (e) {
      print('FireStoreUtils.getOrderById Parse error: $e');
      return null;
    }
  }

  static Future addInbox(InboxModel inboxModel) async {
    return await firestore
        .collection("chat_restaurant")
        .doc(inboxModel.orderId)
        .set(inboxModel.toJson())
        .then((document) {
      return inboxModel;
    });
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

  static sendNewVendorMail(User user) async {
    EmailTemplateModel? emailTemplateModel =
        await FireStoreUtils.getEmailTemplates(newVendorSignup);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{userid}", user.userID);
    newString = newString.replaceAll(
        "{username}", user.firstName + " " + user.lastName);
    newString = newString.replaceAll("{useremail}", user.email);
    newString = newString.replaceAll("{userphone}", user.phoneNumber);
    newString = newString.replaceAll(
        "{date}", DateFormat('yyyy-MM-dd').format(Timestamp.now().toDate()));
    await sendMail(
        subject: emailTemplateModel.subject,
        isAdmin: emailTemplateModel.isSendToAdmin,
        body: newString,
        recipients: []);
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

  static Future addChat(ConversationModel conversationModel) async {
    return await firestore
        .collection("chat_restaurant")
        .doc(conversationModel.orderId)
        .collection("thread")
        .doc(conversationModel.id)
        .set(conversationModel.toJson())
        .then((document) {
      return conversationModel;
    });
  }

  static const _uuid = Uuid();

  /// Add system message to chat_driver for order status updates (e.g. Order Shipped).
  static Future<void> addDriverChatSystemMessage({
    required String orderId,
    required String status,
    required String customerId,
    String? customerFcmToken,
    String? restaurantId,
  }) async {
    try {
      final messageId = _uuid.v4();
      const statusMessages = {
        'Order Shipped': 'Your order is ready for pickup',
        'In Transit': 'Driver is on the way with your order',
        'Order Completed': 'Your order has been delivered. Thank you!',
      };
      final messageText =
          statusMessages[status] ?? 'Order status updated: $status';

      await firestore
          .collection("chat_driver")
          .doc(orderId)
          .collection("thread")
          .doc(messageId)
          .set({
        'id': messageId,
        'senderId': 'system',
        'receiverId': customerId,
        'orderId': orderId,
        'message': messageText,
        'messageType': 'system',
        'senderType': 'system',
        'orderStatus': status,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'readBy': <String, dynamic>{},
      });
    } catch (e) {
      debugPrint('Error adding driver chat system message: $e');
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
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
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

  Future<ProductModel> getProductByProductID(String productId) async {
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
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  static Future<TableModel?> addTable(
      TableModel bookTableModel, VendorModel vendorModel) async {
    try {
      await firestore
          .collection(VENDORS)
          .doc(vendorModel.id)
          .collection(CREATETABLE)
          .doc(bookTableModel.tableId)
          .set(bookTableModel.toJson());
    } on Exception catch (e) {
      print(e);
    }
    return null;
  }

  static Future<TableModel?> removeTable(
      TableModel bookTableModel, VendorModel vendorModel) async {
    try {
      await firestore
          .collection(VENDORS)
          .doc(vendorModel.id)
          .collection(CREATETABLE)
          .doc(bookTableModel.tableId)
          .delete();
    } on Exception catch (e) {
      print(e);
    }
    return null;
  }

  static Future<List<TableModel>> getTable(String vid) async {
    List<TableModel> bookTablemodel = [];
    QuerySnapshot<Map<String, dynamic>> tableDocument = await firestore
        .collection(VENDORS)
        .doc(vid)
        .collection(CREATETABLE)
        .get();
    await Future.forEach(tableDocument.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bookTablemodel.add(TableModel.fromJson(document.data()));
      } catch (e) {
        print(e);
      }
    });
    // print("Book Model"+bookTablemodel.toString());
    return bookTablemodel;
  }

  late StreamSubscription offerStreamSub;
  late StreamController<List<OfferModel>> offerStreamController;

  static Future<User?> getCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return User.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  static Stream<User?> getCurrentUserStream(String uid) async* {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      yield User.fromJson(userDocument.data()!);
    } else {
      yield null;
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

  static Future<bool> sendFcmMessage(String type, String token) async {
    try {
      NotificationModel? notificationModel = await getNotificationContent(type);
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
        },
        "priority": "high",
        'data': {},
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
      String title, String message, String token) async {
    try {
      var url = 'https://fcm.googleapis.com/fcm/send';
      var header = {
        "Content-Type": "application/json",
        "Authorization": "key=$SERVER_KEY",
      };
      var request = {
        "notification": {
          "title": title,
          "body": message,
          "sound": "default",
          // "color": COLOR_PRIMARY,
        },
        "priority": "high",
        'data': {},
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

  static Future<User?> updateCurrentUser(User user) async {
    return await firestore
        .collection(USERS)
        .doc(user.userID)
        .set(user.toJson())
        .then((document) {
      return user;
    });
  }

  /// Adds token to user's fcmTokens array. Call on login. Also updates vendor.
  static Future<void> addFcmTokenToArray(
      String userId, String token, {String? vendorId}) async {
    try {
      if (userId.isEmpty || token.isEmpty) return;
      await firestore.collection(USERS).doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      if (vendorId != null && vendorId.isNotEmpty) {
        await firestore.collection(VENDORS).doc(vendorId).update({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('[FCM] addFcmTokenToArray failed: $e');
    }
  }

  /// Removes token from user's fcmTokens array. Call on logout.
  static Future<void> removeFcmToken(
      String userId, String token, {String? vendorId}) async {
    try {
      if (userId.isEmpty || token.isEmpty) return;
      await firestore.collection(USERS).doc(userId).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      if (vendorId != null && vendorId.isNotEmpty) {
        await firestore.collection(VENDORS).doc(vendorId).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
    } catch (e) {
      print('[FCM] removeFcmToken failed: $e');
    }
  }

  Future<Map<String, dynamic>?> getAdminCommission() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery =
        await firestore.collection(Setting).doc('AdminCommission').get();
    if (codQuery.data() != null) {
      Map<String, dynamic> getValue = {
        "adminCommission": codQuery["fix_commission"].toString(),
        "isAdminCommission": codQuery["isEnabled"],
      };
      print(getValue.toString() + "===____");
      return getValue;
    } else {
      return null;
    }
  }

  getplaceholderimage() async {
    var collection = FirebaseFirestore.instance.collection(Setting);
    var docSnapshot = await collection.doc('placeHolderImage').get();
// if (docSnapshot.exists) {
    Map<String, dynamic>? data = docSnapshot.data();
    var value = data?['image'];
    placeholderImage = value;
    return Center();
  }

  Future<CurrencyModel?> getCurrency() async {
    try {
      final value = await firestore
          .collection(Currency)
          .where("isActive", isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 15));
      if (value.docs.isNotEmpty) {
        return CurrencyModel.fromJson(value.docs.first.data());
      }
      return null;
    } catch (e) {
      log('getCurrency error: $e');
      return null;
    }
  }

  // static Future<VendorCategoryModel> getVendorCategoryById() async {
  //   late VendorCategoryModel vendorCategoryModel;
  //   QuerySnapshot<Map<String, dynamic>> vendorsQuery =
  //       await firestore.collection(VENDORS_CATEGORIES).get();
  //   try {
  //     vendorCategoryModel =
  //         VendorCategoryModel.fromJson(vendorsQuery.docs.first.data());
  //   } catch (e) {
  //     print('FireStoreUtils.getVendorByVendorID Parse error $e');
  //   }
  //   return vendorCategoryModel;
  // }

  static Future<List<AttributesModel>> getAttributes() async {
    List<AttributesModel> attributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await firestore.collection(VENDOR_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        print(document.data());
        attributesList.add(AttributesModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return attributesList;
  }

  static Future<List<VendorCategoryModel>> getVendorCategoryById() async {
    List<VendorCategoryModel> category = [];

    QuerySnapshot<Map<String, dynamic>> categoryQuery = await firestore
        .collection(VENDORS_CATEGORIES)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(categoryQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        category.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e, stacksTrace) {
        print('FireStoreUtils.getVendorOrders Parse error ${document.id} $e '
            '$stacksTrace');
      }
    });
    return category;
  }

  static Future<DeliveryChargeModel> getDelivery() async {
    DeliveryChargeModel deliveryChargeModel = DeliveryChargeModel();
    await firestore
        .collection(Setting)
        .doc('DeliveryCharge')
        .get()
        .then((value) {
      deliveryChargeModel = DeliveryChargeModel.fromJson(value.data()!);
    });
    return deliveryChargeModel;
  }

  static Future createPaymentId({collectionName = "wallet"}) async {
    DocumentReference documentReference =
        firestore.collection(collectionName).doc();
    final paymentId = documentReference.id;
    //UserPreference.setPaymentId(paymentId: paymentId);
    return paymentId;
  }

  static Future orderTransaction(
      {required OrderModel orderModel, required double amount}) async {
    DocumentReference documentReference =
        firestore.collection(OrderTransaction).doc();
    Map<String, dynamic> data = {
      "order_id": orderModel.id,
      "id": documentReference.id,
      "date": DateTime.now(),
    };
    if (orderModel.takeAway!) {
      data.addAll({"vendorId": orderModel.vendorID, "vendorAmount": amount});
    }
    await firestore
        .collection(OrderTransaction)
        .doc(documentReference.id)
        .set(data)
        .then((value) {});
    return "updated transaction";
  }

  static Future topUpWalletAmount(
      {required String userId,
      String paymentMethod = "test",
      bool isTopup = true,
      required amount,
      required id,
      orderId = ""}) async {
    print("this is te payment id");
    print(id);
    print(MyAppState.currentUser!.userID);

    await firestore.collection("wallet").doc(id).set({
      "user_id": userId,
      "payment_method": paymentMethod,
      "amount": amount,
      "id": id,
      "order_id": orderId,
      "isTopUp": isTopup,
      "payment_status": "Refund success",
      "date": DateTime.now(),
    }).then((value) {
      firestore.collection("wallet").doc(id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print("nato");
        print(documentData.data());
      });
    });
    return "updated Amount";
  }

  static Future withdrawWalletAmount(
      {required WithdrawHistoryModel withdrawHistory}) async {
    print("this is te payment id");
    print(withdrawHistory.id);
    print(MyAppState.currentUser!.userID);
    await firestore
        .collection(Payouts)
        .doc(withdrawHistory.id)
        .set(withdrawHistory.toJson())
        .then((value) {
      firestore.collection(Payouts).doc(withdrawHistory.id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print(documentData.data());
      });
    });
    return "updated Amount";
  }

  static Future updateWalletAmount(
      {required String userId, required amount}) async {
    dynamic walletAmount = 0;

    await firestore.collection(USERS).doc(userId).get().then((value) async {
      DocumentSnapshot<Map<String, dynamic>> userDocument = value;
      if (userDocument.data() != null && userDocument.exists) {
        try {
          print(userDocument.data());
          await firestore.collection(USERS).doc(userId).update({
            "wallet_amount":
                (num.parse(userDocument.data()!['wallet_amount'].toString()) +
                    amount)
          }).then((value) => print("north"));
        } catch (error) {
          print(error);
          if (error.toString() ==
              "Bad state: field does not exist within the DocumentSnapshotPlatform") {
            print("does not exist");
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

  static Future<VendorModel?> getVendor(String vid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(VENDORS).doc(vid).get();
    if (userDocument.data() != null && userDocument.exists) {
      print("dataaaaaa aaa ");
      return VendorModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
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

  static Future<VendorModel?> updatePhoto(VendorModel vendor, photo) async {
    return await firestore
        .collection(VENDORS)
        .doc(vendor.id)
        .update({'hidephotos': photo}).then((document) {
      return vendor;
    });
  }

  static Future<VendorModel?> updatestatus(
      VendorModel vendor, reststatus) async {
    return await firestore
        .collection(VENDORS)
        .doc(vendor.id)
        .update({'reststatus': reststatus}).then((document) {
      return vendor;
    });
  }

  static Future<String> uploadUserImageToFireStorage(
      File image, String userID) async {
    Reference upload = storage.child('images/$userID.png');
    File compressedImage = await compressImage(image);
    final metadata = SettableMetadata(contentType: 'image/png');
    UploadTask uploadTask = upload.putFile(compressedImage, metadata);
    var downloadUrl =
        await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  Future<List<OrderModel>> getVendorOrders(String userID) async {
    List<OrderModel> orders = [];

    QuerySnapshot<Map<String, dynamic>> ordersQuery = await firestore
        .collection(ORDERS)
        .where('vendorID', isEqualTo: userID)
        .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(ordersQuery.docs,
        (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        orders.add(OrderModel.fromJson(document.data()));
      } catch (e, stacksTrace) {
        print('FireStoreUtils.getVendorOrders Parse error ${document.id} $e '
            '$stacksTrace');
      }
    });
    return orders;
  }

  Stream<List<OrderModel>> watchOrdersPlaced(String vendorID) async* {
    final controller = StreamController<List<OrderModel>>.broadcast();
    StreamSubscription? sub;

    sub = firestore
        .collection(ORDERS)
        .where('vendorID', isEqualTo: vendorID)
        .where('status', whereIn: [
          'Order Placed',
          'Order Accepted',
          'Driver Assigned',
          'Driver Accepted',
          'Driver Rejected',
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final orders = <OrderModel>[];
            for (final doc in snapshot.docs) {
              try {
                orders.add(OrderModel.fromJson(doc.data()));
              } catch (e, s) {
                print('parse error on ${doc.id}: $e\n$s');
              }
            }
            if (!controller.isClosed) controller.add(orders);
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

    controller.onCancel = () => sub?.cancel();

    yield* controller.stream;
  }

  Stream<List<OrderModel>> watchCompletedOrders(String vendorID) async* {
    final controller = StreamController<List<OrderModel>>.broadcast();
    StreamSubscription? sub;

    sub = firestore
        .collection(ORDERS)
        .where('vendorID', isEqualTo: vendorID)
        .where('status', whereNotIn: [
          'Order Placed',
          'Driver Assigned',
          'Order Accepted',
          'Driver Accepted',
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            print(
                '=== DEBUG: watchCompletedOrders - Firestore query returned ${snapshot.docs.length} documents ===');
            final orders = <OrderModel>[];
            for (final doc in snapshot.docs) {
              try {
                final orderData = doc.data();
                final status = orderData['status'] as String?;
                print(
                    '=== DEBUG: watchCompletedOrders - Order ${doc.id} with status: "$status" ===');
                orders.add(OrderModel.fromJson(orderData));
              } catch (e, s) {
                print('parse error on ${doc.id}: $e\n$s');
              }
            }
            print(
                '=== DEBUG: watchCompletedOrders - Adding ${orders.length} orders to stream ===');
            if (!controller.isClosed) controller.add(orders);
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

    controller.onCancel = () => sub?.cancel();

    yield* controller.stream;
  }

  Stream<List<OrderModel>> watchCompletedOrdersForDate(
      String vendorID, DateTime selectedDate) async* {
    // broadcast so multiple listeners can share it
    final controller = StreamController<List<OrderModel>>.broadcast();

    // Create start and end of the selected date
    final startOfDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final endOfDay = startOfDay.add(Duration(days: 1));

    print(
        '=== DEBUG: Looking for ALL completed orders for vendorID: $vendorID ===');
    print(
        '=== DEBUG: Excluding statuses: Order Placed, Driver Assigned, Order Accepted, Driver Accepted ===');

    StreamSubscription? sub;

    sub = firestore
        .collection(ORDERS)
        .where('vendorID', isEqualTo: vendorID)
        .where('status', whereNotIn: [
          'Order Placed',
          'Driver Assigned',
          'Order Accepted',
          'Driver Accepted',
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            print(
                '=== DEBUG: Firestore query returned ${snapshot.docs.length} documents ===');
            final orders = <OrderModel>[];
            for (final doc in snapshot.docs) {
              try {
                final orderData = doc.data();
                final status = orderData['status'] as String?;
                final createdAt = orderData['createdAt'] as Timestamp?;
                final orderVendorID = orderData['vendorID'] as String?;

                print('=== DEBUG: Order ${doc.id} ===');
                print('  Status: "$status"');
                print('  CreatedAt: $createdAt');
                print('  VendorID: $orderVendorID');
                print('  Expected VendorID: $vendorID');

                final excludedStatuses = [
                  'Order Placed',
                  'Driver Assigned',
                  'Order Accepted',
                  'Driver Accepted',
                ];
                if (status != null && excludedStatuses.contains(status)) {
                  print(
                      '  ❌ EXCLUDED: Status "$status" is in exclusion list');
                  continue;
                }

                if (status != null && createdAt != null) {
                  final orderDate = createdAt.toDate();
                  print('  ✅ INCLUDED - Status: $status, Date: $orderDate');
                  orders.add(OrderModel.fromJson(orderData));
                } else {
                  print('  ❌ FILTERED OUT - Missing status or createdAt');
                  print('    Status: $status');
                  print('    CreatedAt: $createdAt');
                }
              } catch (e, s) {
                print('parse error on ${doc.id}: $e\n$s');
              }
            }
            if (!controller.isClosed) controller.add(orders);
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

    controller.onCancel = () => sub?.cancel();

    yield* controller.stream;
  }

  Stream<List<BookTableModel>> watchDineOrdersStatus(
      String vendorID, bool isUpComing) async* {
    print(vendorID.toString() + "====123");
    List<BookTableModel> orders = [];
    if (isUpComing) {
      StreamController<List<BookTableModel>> dineInStreamController =
          StreamController.broadcast();
      firestore
          .collection(ORDERS_TABLE)
          .where('vendorID', isEqualTo: vendorID)
          .where('date', isGreaterThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((event) async {
        orders.clear();
        await Future.forEach(event.docs,
            (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
            print(orders.length.toString() + "{}O{}");
          } catch (e, s) {
            print('watchDineOrdersStatus parse error ${element.id}$e $s');
          }
        });
        dineInStreamController.sink.add(orders);
      });
      yield* dineInStreamController.stream;
    } else {
      StreamController<List<BookTableModel>> dineInStreamController =
          StreamController.broadcast();
      firestore
          .collection(ORDERS_TABLE)
          .where('vendorID', isEqualTo: vendorID)
          .where('date', isLessThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((event) async {
        orders.clear();
        await Future.forEach(event.docs,
            (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
            print(orders.length.toString() + "{}O{}");
          } catch (e, s) {
            print('watchDineOrdersStatus parse error ${element.id}$e $s');
          }
        });
        dineInStreamController.add(orders);
      });
      yield* dineInStreamController.stream;
    }
  }

  static Future updateOrder(OrderModel orderModel) async {
    await firestore
        .collection(ORDERS)
        .doc(orderModel.id)
        .set(orderModel.toJson(), SetOptions(merge: true));
  }

  static Future updateDineInOrder(BookTableModel orderModel) async {
    await firestore
        .collection(ORDERS_TABLE)
        .doc(orderModel.id)
        .set(orderModel.toJson(), SetOptions(merge: true));
  }

  closeOrdersStream() {
    ordersStreamSub.cancel();
    ordersStreamController.close();
  }

  Stream<List<ProductModel>> getProductsStream(String vendorID) async* {
    List<ProductModel> products = [];
    productsStreamController = StreamController();
    if (vendorID == "") {
      isShowLoader = false;
    } else {
      productsStreamSub = firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorID)
          .snapshots()
          .listen((event) async {
        products.clear();
        await Future.forEach(event.docs,
            (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            products.add(ProductModel.fromJson(element.data()));
          } catch (e, s) {
            print('getProductsStream parse error ${element.id}$e $s');
          }
        });
        productsStreamController.add(products);
      });
    }
    yield* productsStreamController.stream;
  }

  closeProductsStream() {
    productsStreamSub.cancel();
    productsStreamController.close();
  }

  Stream<List<OfferModel>> getOfferStream(String vendorID) async* {
    print(vendorID.toString() + "{}");
    List<OfferModel> offers = [];
    offerStreamController = StreamController<List<OfferModel>>();
    offerStreamSub = firestore
        .collection(COUPONS)
        .where("resturant_id", isEqualTo: vendorID)
        .snapshots()
        .listen((event) async {
      offers.clear();
      await Future.forEach(event.docs,
          (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          print(element.data().toString() + "[][");
          offers.add(OfferModel.fromJson(element.data()));
        } catch (e, s) {
          print('getProductsStream parse error ${element.id}$e $s');
        }
      });
      offerStreamController.add(offers);
    });
    yield* offerStreamController.stream;
  }

  closeOfferStream() {
    offerStreamSub.cancel();
    offerStreamController.close();
  }

  Future<String> uploadProductImage(File image, String progress) async {
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('flutter/uberEats/productImages/$uniqueID'
        '.png');
    File compressedImage = await compressImage(image);
    final metadata = SettableMetadata(contentType: 'image/png');
    UploadTask uploadTask = upload.putFile(compressedImage, metadata);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress('{} \n{} / {}KB'.tr(args: [
        progress,
        '${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)}',
        '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
      ]));
    });
    uploadTask.whenComplete(() {});
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    return downloadUrl.toString();
  }

  addOrUpdateProduct(ProductModel productModel) async {
    //print(productModel.toJson().toString()+"===ABC");
    if ((productModel.id).isNotEmpty) {
      await firestore
          .collection(PRODUCTS)
          .doc(productModel.id)
          .set(productModel.toJson());
    } else {
      DocumentReference docRef = firestore.collection(PRODUCTS).doc();
      productModel.id = docRef.id;
      final json = productModel.toJson();
      json['createdAt'] = FieldValue.serverTimestamp();
      docRef.set(json);
    }
  }

  Future addOrUpdateStory(StoryModel storyModel) async {
    await firestore
        .collection(STORY)
        .doc(storyModel.vendorID)
        .set(storyModel.toJson());
  }

  Future removeStory(String vendorId) async {
    await firestore.collection(STORY).doc(vendorId).delete();
  }

  Future<StoryModel?> getStory(String vendorId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument =
        await firestore.collection(STORY).doc(vendorId).get();
    if (userDocument.data() != null && userDocument.exists) {
      return StoryModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  addOffer(OfferModel offerModel, BuildContext context) async {
    DocumentReference docRef = firestore.collection(COUPONS).doc();
    offerModel.id = docRef.id;
    docRef.set(offerModel.toJson()).then((value) {
      Navigator.of(context).pop();
    });
  }

  updateOffer(OfferModel offerModel, BuildContext context) async {
    await firestore
        .collection(COUPONS)
        .doc(offerModel.id!)
        .set(offerModel.toJson())
        .then((value) {
      Navigator.of(context).pop();
    });
  }

  deleteProduct(String productID) async {
    await firestore.collection(PRODUCTS).doc(productID).delete();
  }

  /// compress image file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the image after
  /// being compressed(100 = max quality - 0 = low quality)
  /// @param file the image file that will be compressed
  /// @return File a new compressed file with smaller size
  static Future<File> compressImage(File file) async {
    File compressedImage = await FlutterNativeImage.compressImage(
      file.path,
      quality: 25,
    );
    return compressedImage;
  }

  static Future<auth.UserCredential> signInWithFacebook() async {
    // Trigger the sign-in flow
    final LoginResult loginResult = await FacebookAuth.instance.login();

    // Create a credential from the access token
    final auth.OAuthCredential facebookAuthCredential =
        auth.FacebookAuthProvider.credential(loginResult.accessToken!.token);

    // Once signed in, return the UserCredential
    print("====DFB" +
        facebookAuthCredential.accessToken.toString() +
        " " +
        facebookAuthCredential.token.toString());
    return auth.FirebaseAuth.instance
        .signInWithCredential(facebookAuthCredential);
  }

  static loginWithFacebook() async {
    /// creates a user for this facebook login when this user first time login
    /// and save the new user object to firebase and firebase auth
    ///

    FacebookAuth facebookAuth = FacebookAuth.instance;
    bool isLogged = await facebookAuth.accessToken != null;
    if (!isLogged) {
      LoginResult result = await facebookAuth.login(
        permissions: [
          'public_profile',
          'email',
          'pages_show_list',
          'pages_messaging',
          'pages_manage_metadata'
        ],
      );
      // by default we request the email and the public profile
// or FacebookAuth.i.permissions

      if (result.status == LoginStatus.success) {
        // you are logged
        AccessToken? token = result.accessToken;
        print("====DFB" + "FBLOGIN SUCESS");
        return await handleFacebookLogin(
            await facebookAuth.getUserData(), token!);
      }
    } else {
      AccessToken? token = await facebookAuth.accessToken;

      return await handleFacebookLogin(
          await facebookAuth.getUserData(), token!);
    }
  }

  static handleFacebookLogin(
      Map<String, dynamic> userData, AccessToken token) async {
    // print(token);
    auth.UserCredential authResult = await auth.FirebaseAuth.instance
        .signInWithCredential(
            auth.FacebookAuthProvider.credential(token.token));
    User? user = await getCurrentUser(authResult.user?.uid ?? '');
    List<String> fullName = (userData['name'] as String).split(' ');
    String firstName = '';
    String lastName = '';
    if (fullName.isNotEmpty) {
      firstName = fullName.first;
      lastName = fullName.skip(1).join(' ');
    }
    if (user != null && user.role == USER_ROLE_VENDOR) {
      print("email ${userData['email']}");
      if (userData['email'] == null) {
        return 'Email not added in Facebook';
      }
      user.profilePictureURL = userData['picture']['data']['url'];
      user.firstName = firstName;
      user.lastName = lastName;
      user.email = userData['email'];
      user.role = USER_ROLE_VENDOR;
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      dynamic result = await updateCurrentUser(user);
      return result;
    } else if (user == null) {
      user = User(
          email: userData['email'] ?? '',
          firstName: firstName,
          profilePictureURL: userData['picture']['data']['url'] ?? '',
          userID: authResult.user?.uid ?? '',
          lastOnlineTimestamp: Timestamp.now(),
          lastName: lastName,
          active: true,
          role: USER_ROLE_VENDOR,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          phoneNumber: '',
          createdAt: Timestamp.now(),
          settings: UserSettings());
      String? errorMessage = await firebaseCreateNewUser(user);
      await FireStoreUtils.sendNewVendorMail(user);
      print("====DFB" + user.firstName.toString());
      if (errorMessage == null) {
        print("====DFB" + user.lastName.toString());
        return user;
      } else {
        print("====DFB" + "ERROR");
        return errorMessage;
      }
    }
  }

  static loginWithApple() async {
    final appleCredential = await apple.TheAppleSignIn.performRequests([
      apple.AppleIdRequest(
          requestedScopes: [apple.Scope.email, apple.Scope.fullName])
    ]);
    if (appleCredential.error != null) {
      return "notLoginApple.".tr();
    }

    if (appleCredential.status == apple.AuthorizationStatus.authorized) {
      final auth.AuthCredential credential =
          auth.OAuthProvider('apple.com').credential(
        accessToken: String.fromCharCodes(
            appleCredential.credential?.authorizationCode ?? []),
        idToken: String.fromCharCodes(
            appleCredential.credential?.identityToken ?? []),
      );
      return await handleAppleLogin(credential, appleCredential.credential!);
    } else {
      return "notLoginApple.".tr();
    }
  }

  static handleAppleLogin(
    auth.AuthCredential credential,
    apple.AppleIdCredential appleIdCredential,
  ) async {
    auth.UserCredential authResult =
        await auth.FirebaseAuth.instance.signInWithCredential(credential);
    User? user = await getCurrentUser(authResult.user?.uid ?? '');
    if (user != null) {
      user.role = USER_ROLE_VENDOR;
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      dynamic result = await updateCurrentUser(user);
      return result;
    } else {
      user = User(
          email: appleIdCredential.email ?? '',
          firstName: appleIdCredential.fullName?.givenName ?? '',
          profilePictureURL: '',
          userID: authResult.user?.uid ?? '',
          lastOnlineTimestamp: Timestamp.now(),
          lastName: appleIdCredential.fullName?.familyName ?? '',
          role: USER_ROLE_VENDOR,
          active: true,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          phoneNumber: '',
          createdAt: Timestamp.now(),
          settings: UserSettings());
      String? errorMessage = await firebaseCreateNewUser(user);
      await FireStoreUtils.sendNewVendorMail(user);
      if (errorMessage == null) {
        return user;
      } else {
        return errorMessage;
      }
    }
  }

  Future<Url> uploadChatImageToFireStorage(
      File image, BuildContext context) async {
    showProgress(context, 'Uploading image...', false);
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('images/$uniqueID.png');
    File compressedImage = await compressImage(image);
    final metadata = SettableMetadata(contentType: 'image/png');
    UploadTask uploadTask = upload.putFile(compressedImage, metadata);
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          'Uploading image ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
          '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
          'KB');
    });
    uploadTask.whenComplete(() {});
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
    final uint8list = await VideoThumbnail.thumbnailFile(
        video: downloadUrl,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.PNG);
    final file = File(uint8list ?? '');
    String thumbnailDownloadUrl = await uploadVideoThumbnailToFireStorage(file);
    hideProgress();
    return ChatVideoContainer(
        videoUrl: Url(
            url: downloadUrl.toString(), mime: metaData.contentType ?? 'video'),
        thumbnailUrl: thumbnailDownloadUrl);
  }

  Future<String?> uploadVideoStory(File video, BuildContext context) async {
    updateProgress('Uploading Video...');
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('Story/$uniqueID.mp4');
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
    hideProgress();
    return downloadUrl.toString();
  }

  Future<String> uploadImageOfStory(
      File image, BuildContext context, String extansion) async {
    updateProgress('Uploading thumbnail...');

    final data = await image.readAsBytes();
    final mime = lookupMimeType('', headerBytes: data);
    print("---------->");
    print(mime);

    Reference upload = storage.child(
      'Story/images/${image.path.split('/').last}',
    );
    UploadTask uploadTask =
        upload.putFile(image, SettableMetadata(contentType: mime));
    uploadTask.snapshotEvents.listen((event) {
      updateProgress(
          'Uploading image ${(event.bytesTransferred.toDouble() / 1000).toStringAsFixed(2)} /'
          '${(event.totalBytes.toDouble() / 1000).toStringAsFixed(2)} '
          'KB');
    });
    uploadTask.whenComplete(() {});
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    hideProgress();
    return downloadUrl.toString();
  }

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

  Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = Uuid().v4();
    Reference upload = storage.child('thumbnails/$uniqueID.png');
    File compressedImage = await compressImage(file);
    final metadata = SettableMetadata(contentType: 'image/png');
    UploadTask uploadTask = upload.putFile(compressedImage, metadata);
    var downloadUrl =
        await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<VendorModel> firebaseCreateNewVendor(VendorModel vendor) async {
    User? currentUser;
    DocumentReference documentReference =
        FirebaseFirestore.instance.collection(VENDORS).doc();
    vendor.id = documentReference.id;
    await documentReference.set(vendor.toJson());
    MyAppState.currentUser!.vendorID = documentReference.id;
    currentUser = MyAppState.currentUser;
    await FireStoreUtils.updateCurrentUser(currentUser!);
    vendor.fcmToken = MyAppState.currentUser!.fcmToken;
    await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
    return vendor;
  }

  /// save a new user document in the USERS table in firebase firestore
  /// returns an error message on failure or null on success
  /// Retries up to 2 times for transient 'unavailable' errors
  static Future<String?> firebaseCreateNewUser(User user) async {
    const maxRetries = 3;
    var lastError = '';
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await firestore.collection(USERS).doc(user.userID).set(user.toJson());
        return null;
      } on FirebaseException catch (e) {
        lastError = _firestoreErrorToMessage(e);
        if (e.code == 'unavailable' && attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return lastError;
      } catch (e) {
        return 'Unexpected error: $e';
      }
    }
    return lastError;
  }

  static String _firestoreErrorToMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission error. Please contact support.';
      case 'unavailable':
        return 'Firebase service temporarily unavailable. Try again.';
      case 'resource-exhausted':
        return 'Too many requests. Please try again later.';
      case 'deadline-exceeded':
        return 'Request timed out. Check your connection and try again.';
      default:
        return 'Firestore error: ${e.message ?? e.code}';
    }
  }

  /// login with email and password with firebase
  /// @param email user email
  /// @param password user password
  // In your FireStoreUtils file

  static Future<dynamic> loginWithEmailAndPassword(
      String email, String password) async {
    try {
      // Attempt Firebase Auth login.
      auth.UserCredential result = await auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      // Fetch the corresponding user document from Firestore.
      DocumentSnapshot<Map<String, dynamic>> documentSnapshot =
          await firestore.collection(USERS).doc(result.user?.uid ?? '').get();

      print("Document data: ${documentSnapshot.data()}");

      if (documentSnapshot.exists) {
        // Print each field for debugging.
        Map<String, dynamic> docData = documentSnapshot.data()!;
        docData.forEach((key, value) {
          print("Key: $key => Value: $value");
        });

        // Convert the document data into your User model.
        User user = User.fromJson(docData);
        print(
            "Parsed User => userID: ${user.userID}, role: ${user.role}, active: ${user.active}");

        // Only allow users with vendor role.
        if (user.role == 'vendor') {
          // Update the user's FCM token.
          user.fcmToken = await firebaseMessaging.getToken() ?? '';
          return user;
        } else {
          return 'This account is not authorized as a vendor.';
        }
      } else {
        return 'User record not found.';
      }
    } on auth.FirebaseAuthException catch (exception, s) {
      print("FirebaseAuthException: $exception\nStackTrace: $s");
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
        default:
          return 'Unexpected firebase error, Please try again.';
      }
    } catch (e, s) {
      print("Error while signing in: $e");
      print("Stack trace: $s");
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
    auth.FirebaseAuth.instance.verifyPhoneNumber(
      timeout: Duration(minutes: 2),
      phoneNumber: phoneNumber,
      verificationCompleted: phoneVerificationCompleted!,
      verificationFailed: phoneVerificationFailed!,
      codeSent: phoneCodeSent!,
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
      bool? auto_approve_restaurant}) async {
    auth.AuthCredential authCredential = auth.PhoneAuthProvider.credential(
        verificationId: verificationID, smsCode: code);
    auth.UserCredential userCredential =
        await auth.FirebaseAuth.instance.signInWithCredential(authCredential);
    User? user = await getCurrentUser(userCredential.user?.uid ?? '');
    if (user != null && user.role == USER_ROLE_VENDOR) {
      return user;
    } else if (user == null) {
      /// create a new user from phone login
      String profileImageUrl = '';
      if (image != null) {
        profileImageUrl = await uploadUserImageToFireStorage(
            image, userCredential.user?.uid ?? '');
      }
      User user = User(
        firstName: firstName,
        lastName: lastName,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        phoneNumber: phoneNumber,
        profilePictureURL: profileImageUrl,
        userID: userCredential.user?.uid ?? '',
        active: auto_approve_restaurant == true ? true : false,
        lastOnlineTimestamp: Timestamp.now(),
        photos: [],
        settings: UserSettings(),
        role: USER_ROLE_VENDOR,
        createdAt: Timestamp.now(),
        email: '',
      );
      String? errorMessage = await firebaseCreateNewUser(user);
      await FireStoreUtils.sendNewVendorMail(user);
      if (errorMessage == null) {
        return user;
      } else {
        return "notCreateUserThisPhone".tr();
      }
    }
  }

  static firebaseSignUpWithEmailAndPassword(
      String emailAddress,
      String password,
      File? image,
      String firstName,
      String lastName,
      String mobile,
      bool? auto_approve_restaurant) async {
    try {
      auth.UserCredential result = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: emailAddress, password: password);
      print('Auth user created: ${result.user?.uid}');
      updateProgress('Creating account...'.tr());

      try {
        String profilePicUrl = '';
        if (image != null) {
          updateProgress('Uploading image...'.tr());
          profilePicUrl = await uploadUserImageToFireStorage(
              image, result.user?.uid ?? '');
          print('Image upload completed');
        }
        updateProgress('Saving your information...'.tr());
        User user = User(
            email: emailAddress,
            settings: UserSettings(),
            photos: [],
            lastOnlineTimestamp: Timestamp.now(),
            active: auto_approve_restaurant == true ? true : false,
            phoneNumber: mobile,
            firstName: firstName,
            userID: result.user?.uid ?? '',
            lastName: lastName,
            role: USER_ROLE_VENDOR,
            fcmToken: await firebaseMessaging.getToken() ?? '',
            createdAt: Timestamp.now(),
            profilePictureURL: profilePicUrl);
        String? errorMessage = await firebaseCreateNewUser(user);
        if (errorMessage != null) {
          print('Firestore write failed, deleting Auth user ${result.user?.uid}');
          try {
            await result.user?.delete();
          } catch (delErr) {
            print('Failed to delete Auth user: $delErr');
          }
          return errorMessage;
        }
        print('Firestore write completed for ${user.userID}');
        updateProgress('Almost done...'.tr());
        await FireStoreUtils.sendNewVendorMail(user);
        return user;
      } catch (e) {
        print('Firestore/post-Auth step failed, deleting Auth user '
            '${result.user?.uid}');
        try {
          await result.user?.delete();
        } catch (delErr) {
          print('Failed to delete Auth user: $delErr');
        }
        return e.toString();
      }
    } on auth.FirebaseAuthException catch (error) {
      print(error.toString() + '${error.stackTrace}');
      if (error.code == 'email-already-in-use') {
        return await _tryOrphanRecovery(
          emailAddress,
          password,
          image,
          firstName,
          lastName,
          mobile,
          auto_approve_restaurant,
        );
      }
      String message = "notSignUp".tr();
      switch (error.code) {
        case 'invalid-email':
          message = 'Enter valid e-mail';
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled';
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
      return "notSignUp".tr();
    }
  }

  static Future<dynamic> _tryOrphanRecovery(
    String emailAddress,
    String password,
    File? image,
    String firstName,
    String lastName,
    String mobile,
    bool? auto_approve_restaurant,
  ) async {
    try {
      await auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailAddress, password: password);
      final uid = auth.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 'Email already in use. Try logging in instead.';
      User? existingUser = await getCurrentUser(uid);
      if (existingUser != null) {
        await auth.FirebaseAuth.instance.signOut();
        return 'Email already in use, Please pick another email!';
      }
      print('Orphan detected for uid $uid, completing registration');
      String profilePicUrl = '';
      if (image != null) {
        profilePicUrl =
            await uploadUserImageToFireStorage(image, uid);
      }
      User user = User(
          email: emailAddress,
          settings: UserSettings(),
          photos: [],
          lastOnlineTimestamp: Timestamp.now(),
          active: auto_approve_restaurant == true ? true : false,
          phoneNumber: mobile,
          firstName: firstName,
          userID: uid,
          lastName: lastName,
          role: USER_ROLE_VENDOR,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          createdAt: Timestamp.now(),
          profilePictureURL: profilePicUrl);
      String? errorMessage = await firebaseCreateNewUser(user);
      if (errorMessage != null) return errorMessage;
      await FireStoreUtils.sendNewVendorMail(user);
      print('Orphan recovery completed, Firestore doc created');
      return user;
    } on auth.FirebaseAuthException catch (_) {
      return 'Email already in use. Try logging in instead.';
    } catch (e) {
      return 'Email already in use, Please pick another email!';
    }
  }

  static Future<auth.UserCredential?> reAuthUser(AuthProviders provider,
      {String? email,
      String? password,
      String? smsCode,
      String? verificationId,
      AccessToken? accessToken,
      apple.AuthorizationResult? appleCredential}) async {
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
        credential = auth.FacebookAuthProvider.credential(accessToken!.token);
        break;
      case AuthProviders.APPLE:
        credential = auth.OAuthProvider('apple.com').credential(
          accessToken: String.fromCharCodes(
              appleCredential!.credential?.authorizationCode ?? []),
          idToken: String.fromCharCodes(
              appleCredential.credential?.identityToken ?? []),
        );
        break;
    }
    return await auth.FirebaseAuth.instance.currentUser!
        .reauthenticateWithCredential(credential);
  }

  static deleteUser() async {
    try {
      // delete user records from CHANNEL_PARTICIPATION table
      await firestore
          .collection(ORDERS)
          .where('vendorID', isEqualTo: MyAppState.currentUser!.vendorID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });
      await firestore
          .collection(ORDERS_TABLE)
          .where('vendorID', isEqualTo: MyAppState.currentUser!.vendorID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });

      await firestore
          .collection(COUPONS)
          .where('resturant_id', isEqualTo: MyAppState.currentUser!.vendorID)
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

      await firestore
          .collection(FOOD_REVIEW)
          .where('VendorId', isEqualTo: MyAppState.currentUser!.vendorID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });
      await firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: MyAppState.currentUser!.vendorID)
          .get()
          .then((value) async {
        for (var doc in value.docs) {
          await firestore.doc(doc.reference.path).delete();
        }
      });

      await firestore
          .collection(VENDORS)
          .doc(MyAppState.currentUser!.vendorID)
          .delete();

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

  Future restaurantVendorWalletSet(OrderModel orderModel) async {
    double total = 0.0;
    double discount = 0.0;
    double specialDiscount = 0.0;
    double taxAmount = 0.0;
    orderModel.products.forEach((element) {
      if (element.extrasPrice != null &&
          element.extrasPrice!.isNotEmpty &&
          double.parse(element.extrasPrice!) != 0.0) {
        total += element.quantity * double.parse(element.extrasPrice!);
      }
      total += element.quantity * double.parse(element.price);
    });
    if (orderModel.specialDiscount != null ||
        orderModel.specialDiscount!['special_discount'] != null) {
      specialDiscount = double.parse(
          orderModel.specialDiscount!['special_discount'].toString());
    }

    if (orderModel.discount != null) {
      discount = double.parse(orderModel.discount.toString());
    }
    var totalamount = total - discount - specialDiscount;

    double adminComm = (orderModel.adminCommissionType == 'Percent')
        ? (totalamount * double.parse(orderModel.adminCommission!)) / 100
        : double.parse(orderModel.adminCommission!);

    if (orderModel.taxModel != null) {
      for (var element in orderModel.taxModel!) {
        taxAmount = taxAmount +
            calculateTax(amount: totalamount.toString(), taxModel: element);
      }
    }

    double finalAmount = totalamount + taxAmount;

    TopupTranHistoryModel historyModel = TopupTranHistoryModel(
        amount: finalAmount,
        id: Uuid().v4(),
        orderId: orderModel.id,
        userId: orderModel.vendor.author,
        date: Timestamp.now(),
        isTopup: true,
        paymentMethod: "Wallet",
        paymentStatus: "success",
        transactionUser: "vendor");

    await firestore
        .collection(Wallet)
        .doc(historyModel.id)
        .set(historyModel.toJson());

    TopupTranHistoryModel adminCommission = TopupTranHistoryModel(
        amount: adminComm,
        id: Uuid().v4(),
        orderId: orderModel.id,
        userId: orderModel.vendor.author,
        date: Timestamp.now(),
        isTopup: false,
        paymentMethod: "Wallet",
        paymentStatus: "success",
        transactionUser: "vendor");

    await firestore
        .collection(Wallet)
        .doc(historyModel.id)
        .set(historyModel.toJson());
    await firestore
        .collection(Wallet)
        .doc(adminCommission.id)
        .set(adminCommission.toJson());
    await updateVendorWalletAmount(
        amount: finalAmount - adminComm, userId: orderModel.vendor.author);
  }

  static Future updateVendorWalletAmount(
      {required amount, required userId}) async {
    await firestore.collection(USERS).doc(userId).get().then((value) async {
      DocumentSnapshot<Map<String, dynamic>> userDocument = value;
      if (userDocument.data() != null && userDocument.exists) {
        try {
          print(userDocument.data());
          User user = User.fromJson(userDocument.data()!);
          user.walletAmount = user.walletAmount + amount;
          await firestore
              .collection(USERS)
              .doc(userId)
              .set(user.toJson())
              .then((value) => print("north"));
        } catch (error) {
          print(error);
          if (error.toString() ==
              "Bad state: field does not exist within the DocumentSnapshotPlatform") {
            print("does not exist");
          } else {
            print("went wrong!!");
          }
        }
      } else {
        return 0.111;
      }
    });
  }

  static resetPassword(String emailAddress) async =>
      await auth.FirebaseAuth.instance
          .sendPasswordResetEmail(email: emailAddress);
}
