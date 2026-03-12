// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/mail_setting.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'model/TaxModel.dart';

const FINISHED_ON_BOARDING = 'finishedOnBoarding';
const COLOR_ACCENT = 0xFF8fd468;
const COLOR_PRIMARY_DARK = 0xFF683A;
var COLOR_PRIMARY = 0xFFFF683A;
const DARK_COLOR = 0xff191A1C;
const DARK_VIEWBG_COLOR = 0xff191A1C;
const DARK_CARD_BG_COLOR = 0xff242528;
const DARK_BG_COLOR = 0xff121212;
const COUPON_BG_COLOR = 0xFFFCF8F3;
const COUPON_DASH_COLOR = 0xFFCACFDA;
const GREY_TEXT_COLOR = 0xff5E5C5C;
const DARK_GREY_TEXT_COLOR = 0xff9F9F9F;
const DarkContainerColor = 0xff26272C;
const DarkContainerBorderColor = 0xff515151;

double radiusValue = 0.0;

// Default location for guests without location set (Jolo, Sulu, Philippines)
const double DEFAULT_LATITUDE = 6.0522;
const double DEFAULT_LONGITUDE = 121.0022;
const String DEFAULT_ADDRESS = "Jolo, Sulu";

/// Returns true if the given coordinates match the default Jolo, Sulu location.
bool isDefaultLocation(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  const epsilon = 0.0001;
  return (lat - DEFAULT_LATITUDE).abs() < epsilon &&
      (lng - DEFAULT_LONGITUDE).abs() < epsilon;
}

const STORY = 'story';
const MENU_ITEM = 'menu_items';
const USERS = 'users';
const dynamicNotification = 'dynamic_notification';
const emailTemplates = 'email_templates';
const REFERRAL = 'referral';
const PENDING_REFERRALS = 'pending_referrals';
const REPORTS = 'reports';
const Deliverycharge = 6;
const VENDOR_ATTRIBUTES = "vendor_attributes";
const REVIEW_ATTRIBUTES = "review_attributes";
const FavouriteItem = "favorite_item";
const VENDORS = 'vendors';
const PRODUCTS = 'vendor_products';
const ORDERS = 'restaurant_orders';
const PAUTOS_ORDERS = 'pautos_orders';
const ORDER_FEEDBACK = 'order_feedback';
const ADVERTISEMENTS = 'advertisements';
const ORDERS_TABLE = 'booked_table';
const GIFT_CARDS = 'gift_cards';
const GIFT_PURCHASES = 'gift_purchases';
const SECOND_MILLIS = 1000;
const MINUTE_MILLIS = 60 * SECOND_MILLIS;
const HOUR_MILLIS = 60 * MINUTE_MILLIS;
const SERVER_KEY = 'Replace with your Server key';
String GOOGLE_API_KEY = 'AIzaSyBXNXXV60p-VYnIMD0mevMk8HeW9kSJnPs';
bool isGoogleApiKeyFromFirestore = false;
// Google Sign-In Web Client ID (client_type 3 from google-services.json)
// Required for Android release builds to avoid DEVELOPER_ERROR
const String GOOGLE_SIGN_IN_WEB_CLIENT_ID = '916084329397-l5hn2jd8agb8228p3p42pf83jn4lf20b.apps.googleusercontent.com';

const ORDER_STATUS_PLACED = 'Order Placed';
const ORDER_STATUS_ACCEPTED = 'Order Accepted';
const ORDER_STATUS_REJECTED = 'Order Rejected';
const ORDER_STATUS_CANCELLED = "Order Cancelled";
const ORDER_STATUS_DRIVER_ACCEPTED = 'Driver Accepted';
const ORDER_STATUS_DRIVER_REJECTED = 'Driver Rejected';
const ORDER_STATUS_SHIPPED = 'Order Shipped';
const ORDER_STATUS_IN_TRANSIT = 'In Transit';
const ORDER_STATUS_COMPLETED = 'Order Completed';
const ORDER_STATUS_PAYMENT_FAILED = 'Payment Failed';

const USER_ROLE_DRIVER = 'driver';
const USER_ROLE_CUSTOMER = 'customer';
const USER_ROLE_VENDOR = 'vendor';
const VENDORS_CATEGORIES = 'vendor_categories';
const Order_Rating = 'foods_review';
const CONTACT_US = 'ContactUs';
const COUPON = 'coupons';
const Wallet = "wallet";
const Currency = 'currencies';
const HomePageVersion = 'home_page_version';
const Setting = 'settings';
const tax = 'tax';
const FavouriteRestaurant = "favorite_restaurant";
const SEARCH_ANALYTICS = 'search_analytics';
const USER_CLICKS = 'user_clicks';
const CUSTOMER_FEEDBACK = 'customer_feedback';
const RECOMMENDATION_FEEDBACK = 'recommendation_feedback';
const VENDOR_VIEWERS = 'vendor_viewers';
const VENDOR_VISITS = 'vendor_visits';

const walletTopup = "wallet_topup";
const newVendorSignup = "new_vendor_signup";
const payoutRequestStatus = "payout_request_status";
const payoutRequest = "payout_request";
const newOrderPlaced = "new_order_placed";

const COD = 'CODSettings';

const GlobalURL = "Replace with your web";

const scheduleOrder = "schedule_order";
const dineInPlaced = "dinein_placed";
const dineInCanceled = "dinein_canceled";
const dineinAccepted = "dinein_accepted";
const driverAccepted = "driver_accepted";
const restaurantRejected = "restaurant_rejected";
const driverCompleted = "driver_completed";
const restaurantAccepted = "restaurant_accepted";
const takeawayCompleted = "takeaway_completed";
const orderPlaced = "order_placed";

String? country = "";
List<TaxModel>? taxList = [];

bool isDineInEnable = false;
List<VendorModel> allstoreList = [];
String appVersion = '';

CurrencyModel? currencyModel;
String? homePageThem = "them_1";

String referralAmount = "0.0";

String placeholderImage =
    'https://firebasestorage.googleapis.com/v0/b/lalago-v2.firebasestorage.app/o/images%2Fplace_holder_offer.png?alt=media&token=e8e7233b-8df2-4cd6-be48-6bf067550324';

String getReferralCode() {
  var rng = new Random();
  return (rng.nextInt(900000) + 100000).toString();
}

double getDoubleVal(dynamic input) {
  if (input == null) {
    return 0.1;
  }

  if (input is int) {
    return double.parse(input.toString());
  }

  if (input is double) {
    return input;
  }
  return 0.1;
}

double calculateTax({String? amount, TaxModel? taxModel}) {
  double taxAmount = 0.0;
  if (taxModel != null && taxModel.enable == true) {
    if (taxModel.type == "fix") {
      taxAmount = double.parse(taxModel.tax.toString());
    } else {
      taxAmount = (double.parse(amount.toString()) *
              double.parse(taxModel.tax!.toString())) /
          100;
    }
  }
  return taxAmount;
}

double calculateDiscount({String? amount, OfferModel? offerModel}) {
  double taxAmount = 0.0;
  if (offerModel != null) {
    if (offerModel.discountType == "Percentage" ||
        offerModel.discountType == "percentage") {
      taxAmount = (double.parse(amount.toString()) *
              double.parse(offerModel.discount.toString())) /
          100;
    } else {
      taxAmount = double.parse(offerModel.discount.toString());
    }
  }
  return taxAmount;
}

Uri createCoordinatesUrl(double latitude, double longitude, [String? label]) {
  var uri;
  if (kIsWeb) {
    uri = Uri.https('www.google.com', '/maps/search/',
        {'api': '1', 'query': '$latitude,$longitude'});
  } else if (Platform.isAndroid) {
    var query = '$latitude,$longitude';
    if (label != null) query += '($label)';
    uri = Uri(scheme: 'geo', host: '0,0', queryParameters: {'q': query});
  } else if (Platform.isIOS) {
    var params = {'ll': '$latitude,$longitude'};
    if (label != null) params['q'] = label;
    uri = Uri.https('maps.apple.com', '/', params);
  } else {
    uri = Uri.https('www.google.com', '/maps/search/',
        {'api': '1', 'query': '$latitude,$longitude'});
  }

  return uri;
}

String getKm(UserLocation pos1, UserLocation pos2) {
  double distanceInMeters = Geolocator.distanceBetween(
      pos1.latitude, pos1.longitude, pos2.latitude, pos2.longitude);
  double kilometer = distanceInMeters / 1000;
  debugPrint("KiloMeter$kilometer");
  return kilometer.toStringAsFixed(2).toString();
}

String amountShow({required String? amount}) {
  if (currencyModel!.symbolatright == true) {
    return "${double.parse(amount.toString()).toStringAsFixed(currencyModel!.decimal)} ${currencyModel!.symbol.toString()}";
  } else {
    return "${currencyModel!.symbol.toString()} ${double.parse(amount.toString()).toStringAsFixed(currencyModel!.decimal)}";
  }
}

String getImageVAlidUrl(String url) {
  String imageUrl = placeholderImage;
  if (url.isNotEmpty && url.trim().isNotEmpty) {
    // Validate URL format
    try {
      Uri.parse(url);
      imageUrl = url;
    } catch (e) {
      // If URL is invalid, use placeholder
      imageUrl = placeholderImage;
    }
  }
  return imageUrl;
}

MailSettings? mailSettings;
// logs.log(newString);
// String username = 'foodie@siswebapp.com';
// String password = "8#bb\$1)E@#f3";

final smtpServer = SmtpServer(mailSettings!.host.toString(),
    username: mailSettings!.userName.toString(),
    password: mailSettings!.password.toString(),
    port: 465,
    ignoreBadCertificate: false,
    ssl: true,
    allowInsecure: true);

sendMail(
    {String? subject,
    String? body,
    bool? isAdmin = false,
    List<dynamic>? recipients}) async {
  // Create our message.
  if (isAdmin == true) {
    recipients!.add(mailSettings!.userName.toString());
  }
  final message = Message()
    ..from = Address(
        mailSettings!.userName.toString(), mailSettings!.fromName.toString())
    ..recipients = recipients!
    ..subject = subject
    ..text = body
    ..html = body;

  try {
    final sendReport = await send(message, smtpServer);
    print('Message sent: ' + sendReport.toString());
  } on MailerException catch (e) {
    print(e);
    print('Message not sent.');
    for (var p in e.problems) {
      print('Problem: ${p.code}: ${p.msg}');
    }
  }

  // var connection = PersistentConnection(smtpServer);
  //
  // // Send the first message
  // await connection.send(message);
}
