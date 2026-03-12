import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:bottom_picker/bottom_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/DeliveryChargeModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/variant_info.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/ui/profile/ProfileScreen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../model/TaxModel.dart';
import '../payment/PaymentScreen.dart';
import 'package:foodie_customer/model/HappyHourConfig.dart';
import 'package:foodie_customer/services/happy_hour_helper.dart';
import 'package:foodie_customer/services/happy_hour_service.dart';
import 'package:foodie_customer/services/first_order_coupon_service.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/new_user_promo_service.dart';
import 'package:foodie_customer/services/loyalty_service.dart';
import 'package:foodie_customer/services/gift_card_service.dart';
import 'package:foodie_customer/services/distance_service.dart';
import 'package:foodie_customer/ui/cartScreen/voucher_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foodie_customer/ui/home/view_all_restaurant.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/widgets/banner_ad_widget.dart';
import 'package:foodie_customer/ui/cartScreen/estimated_delivery_time_card.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/model/addon_promo_model.dart';
import 'package:foodie_customer/services/addon_promo_service.dart';
import 'package:foodie_customer/ui/addon/addon_promo_card.dart';
import 'package:foodie_customer/utils/extensions/cart_product_extension.dart';
import 'package:foodie_customer/services/ad_service.dart';
import 'package:foodie_customer/services/analytics_service.dart';
import 'package:foodie_customer/services/performance_logger.dart';
import 'package:foodie_customer/services/restaurant_status_service.dart';

/// Temporarily set to false to silence cart debug logs while tracing FCM.
const bool _kShowCartLogs = false;

/// One entry in the cart list: either a bundle header or a product row.
class _CartEntry {
  final bool isBundleHeader;
  final String? bundleName;
  final CartProduct? product;

  _CartEntry.bundleHeader(this.bundleName)
      : isBundleHeader = true,
        product = null;

  _CartEntry.item(this.product)
      : isBundleHeader = false,
        bundleName = null;
}

/// Holds a pending quantity update for debouncing rapid +/- taps.
class _PendingQuantityUpdate {
  final CartProduct product;
  final int targetQty;

  const _PendingQuantityUpdate(this.product, this.targetQty);
}

class CartScreen extends StatefulWidget {
  final bool fromContainer;

  const CartScreen({Key? key, this.fromContainer = false}) : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Future<List<CartProduct>> cartFuture;

  late List<CartProduct> cartProducts = [];

  double subTotal = 0.0;

  double specialDiscount = 0.0;

  double specialDiscountAmount = 0.0;

  String specialType = "";

  TextEditingController noteController = TextEditingController(text: '');

  late CartDatabase cartDatabase;

  final ValueNotifier<double> grandtotalNotifier = ValueNotifier<double>(0.0);

  double discountAmount = 0.0;

  var per = 0.0;

  late Future<List<OfferModel>> coupon;

  TextEditingController txt = TextEditingController(text: '');

  FireStoreUtils _fireStoreUtils = FireStoreUtils();

  String vendorID = "";

  late List<AddAddonsDemo> lstExtras = [];

  late List<String> commaSepratedAddOns = [];

  late List<String> commaSepratedAddSize = [];

  String? commaSepratedAddOnsString = "";

  String? commaSepratedAddSizeString = "";

  String? adminCommissionValue = "", addminCommissionType = "";

  bool? isEnableAdminCommission = false;

  var deliveryCharges = "0.0";

  VendorModel? vendorModel;

  String? selctedOrderTypeValue = "Delivery";

  bool isDeliverFound = false;

  var tipValue = 0.0;

  bool isTipSelected = false,
      isTipSelected1 = false,
      isTipSelected2 = false,
      isTipSelected3 = false;

  TextEditingController _textFieldController = TextEditingController();

  late Map<String, dynamic>? adminCommission;

  final ValueNotifier<Timestamp?> scheduleTimeNotifier =
      ValueNotifier<Timestamp?>(null);
  Timestamp? get scheduleTime => scheduleTimeNotifier.value;
  set scheduleTime(Timestamp? value) => scheduleTimeNotifier.value = value;

  AddressModel addressModel = AddressModel();

  bool isFirstOrderEligible = false;
  final ValueNotifier<bool> isReferralPathNotifier = ValueNotifier<bool>(false);
  bool get isReferralPath => isReferralPathNotifier.value;

  // Happy Hour variables
  double happyHourDiscount = 0.0;
  HappyHourConfig? activeHappyHourConfig;
  String? happyHourError;
  int? happyHourItemsNeeded;

  // First-order coupon variables
  bool isFirstOrderCouponEligible = false;
  double firstOrderCouponDiscount = 0.0;
  String? firstOrderCouponId;
  String? firstOrderCouponCode;

  // Selected discount for single-discount policy
  Map<String, dynamic>? selectedDiscount;

  // Manual coupon variables
  OfferModel? manualCoupon;
  TextEditingController manualCouponCodeController = TextEditingController();
  bool isManualCouponValidating = false;
  String? manualCouponError;
  double manualCouponDiscountAmount = 0.0;
  int? couponItemsNeeded;

  // New User Promo variables
  bool isNewUserPromoEligible = false;
  double newUserPromoDiscount = 0.0;
  NewUserPromoConfig? newUserPromoConfig;
  bool _isNewUserPromoLoading = false;

  // Referral wallet variables
  double referralWalletAmountAvailable = 0.0;
  double referralWalletAmountToUse = 0.0;
  bool isReferralWalletApplied = false;

  // Gift card variables
  List<Map<String, dynamic>> activeGiftCards = [];
  double giftCardAmountToUse = 0.0;
  List<Map<String, dynamic>> giftCardBreakdown = [];
  bool isGiftCardApplied = false;
  GiftCardConfig? giftCardConfig;

  // Loyalty free delivery
  double loyaltyFreeDeliveryAmount = 0.0;
  String? loyaltyFreeDeliveryRewardId;
  String? loyaltyFreeDeliveryCycle;

  // State management variables to prevent UI flashing
  bool _isInitialized = false;
  bool _isDeliveryDataLoading = false;
  bool _isDeliveryReady = false;
  bool _deliveryCalcFailed = false;
  bool _isDependenciesInitialized = false;
  String? _lastVendorID;
  List<CartProduct>? _lastCartProducts;
  double? _lastSubTotal;
  String? _lastTotalsSignature;
  Map<String, ProductModel>? _productCache;
  Map<String, VendorModel>? _vendorCache;

  // Distance calculation caching and change tracking
  String? _lastCalculatedVendorID;
  String? _lastCalculatedAddressID;
  double? _lastCalculatedLat;
  double? _lastCalculatedLng;
  double? _cachedDistanceKm;
  String? _cachedDeliveryCharge;
  DateTime? _cacheTimestamp;
  Timer? _distanceCalculationDebounceTimer;
  String? _estimatedDeliveryTimeText;

  Timer? _statusCheckTimer;
  List<Map<String, dynamic>>? _closedVendorsInCart;

  static const int _defaultPrepMinutes = 20;
  static const int _etaBufferMinutes = 10;
  static const double _avgSpeedKmh = 25.0;
  static const int _cacheExpiryMinutes = 10;

  /// When true, next delivery calculation uses live location (no cache).
  bool _useLiveLocationOnNextDeliveryCalc = true;

  /// Invalidates all delivery-related cache variables
  void _invalidateDeliveryCache() {
    _cachedDistanceKm = null;
    _cachedDeliveryCharge = null;
    _lastCalculatedVendorID = null;
    _lastCalculatedAddressID = null;
    _lastCalculatedLat = null;
    _lastCalculatedLng = null;
    _cacheTimestamp = null;
    _estimatedDeliveryTimeText = null;
  }

  List<Map<String, dynamic>> _prorateGiftCardBreakdown(
    List<Map<String, dynamic>> breakdown,
    double maxTotal,
  ) {
    final total = breakdown.fold<double>(
      0,
      (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0),
    );
    if (total <= 0 || maxTotal >= total) return breakdown;
    final ratio = maxTotal / total;
    return breakdown.map((e) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0;
      return {
        ...e,
        'amount': (amt * ratio).roundToDouble(),
      };
    }).where((e) => (e['amount'] as num) > 0).toList();
  }

  String? _validatePhoneNumber(String value) {
    if (value.trim().isEmpty) {
      return "Please enter your phone number.";
    }
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return "Phone number must be numeric.";
    }
    if (value.length < 10 || value.length > 11) {
      return "Phone number must be 10 to 11 digits.";
    }
    return null;
  }

  Future<bool> _ensureUserLoggedIn(BuildContext context) async {
    if (MyAppState.currentUser == null) {
      final shouldLogin = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Login Required'),
          content: Text('Please login to place your order. Your cart will be saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Login'),
            ),
          ],
        ),
      );
      
      if (shouldLogin == true) {
        // Navigate to LoginScreen with return flag
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoginScreen(returnToCart: true),
          ),
        );
        
        // Check if user logged in successfully
        return MyAppState.currentUser != null;
      }
      
      return false;
    }
    
    return true;
  }

  Future<bool> _ensurePhoneNumber(BuildContext context) async {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) {
      return false;
    }

    final latestUser = await FireStoreUtils.getCurrentUser(
      currentUser.userID,
    );
    if (latestUser != null) {
      MyAppState.currentUser = latestUser;
    }

    final phoneNumber = (MyAppState.currentUser?.phoneNumber ?? '').trim();
    if (phoneNumber.isNotEmpty) {
      return true;
    }

    return _showPhoneNumberDialog(context);
  }

  Future<bool> _showPhoneNumberDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                "Phone Number Required",
                style: TextStyle(
                  fontFamily: "Poppinsm",
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Please enter your phone number to continue checkout.",
                    style: TextStyle(
                      fontFamily: "Poppinsr",
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    maxLength: 11,
                    decoration: const InputDecoration(
                      hintText: "e.g. 09XXXXXXXXX",
                      counterText: '',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    SelectableText.rich(
                      TextSpan(
                        text: errorText,
                        style: const TextStyle(
                          color: Colors.red,
                          fontFamily: "Poppinsr",
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.of(context).pop(false);
                        },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final value = controller.text.trim();
                          final validationError =
                              _validatePhoneNumber(value);
                          if (validationError != null) {
                            setState(() {
                              errorText = validationError;
                            });
                            return;
                          }

                          setState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          final user = MyAppState.currentUser;
                          if (user == null) {
                            setState(() {
                              isSaving = false;
                              errorText =
                                  "Unable to load your account details.";
                            });
                            return;
                          }

                          user.phoneNumber = value;
                          final updatedUser =
                              await FireStoreUtils.updateCurrentUser(user);
                          if (updatedUser == null) {
                            setState(() {
                              isSaving = false;
                              errorText =
                                  "Unable to update phone number. "
                                  "Please try again.";
                            });
                            return;
                          }

                          Navigator.of(context).pop(true);
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          "Save",
                          style: TextStyle(
                            fontFamily: "Poppinsm",
                            fontSize: 16,
                            color: Color(COLOR_PRIMARY),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  String _buildEstimatedDeliveryTimeText(double distanceKm) {
    final int travelMinutes =
        ((distanceKm / _avgSpeedKmh) * 60).round();
    final int safeTravelMinutes = travelMinutes < 1 ? 1 : travelMinutes;
    final int totalMinutes = _defaultPrepMinutes + safeTravelMinutes;
    final int safeTotalMinutes =
        totalMinutes > 24 * 60 ? 24 * 60 : totalMinutes;
    final int maxMinutes = safeTotalMinutes + _etaBufferMinutes;
    final int safeMaxMinutes =
        maxMinutes > 24 * 60 ? 24 * 60 : maxMinutes;

    if (safeMaxMinutes <= safeTotalMinutes) {
      return '$safeTotalMinutes minutes';
    }
    return '$safeTotalMinutes - $safeMaxMinutes minutes';
  }

  // Loading state variables for async operations
  bool _isHappyHourLoading = false;
  bool _isFirstOrderCouponLoading = false;
  bool _isAdminCommissionLoading = false;
  bool _isInitialDataLoading = false;

  // Check if any data is currently loading
  bool get _isDataLoading =>
      _isDeliveryDataLoading ||
      _isHappyHourLoading ||
      _isFirstOrderCouponLoading ||
      _isAdminCommissionLoading ||
      _isInitialDataLoading;

  // ValueNotifiers for cart item quantities (for display only)
  final Map<String, ValueNotifier<int>> _itemQuantityNotifiers = {};

  // Debounce quantity +/- taps to reduce DB writes during rapid taps
  static const Duration _quantityDebounceDelay =
      Duration(milliseconds: 300);
  Timer? _quantityDebounceTimer;
  final Map<String, _PendingQuantityUpdate> _pendingQuantityUpdates = {};

  // Initialize/update quantity notifiers for cart items
  void _updateQuantityNotifiers(List<CartProduct> products) {
    // Remove notifiers for items that no longer exist
    final currentIds = products.map((p) => p.id).toSet();
    _itemQuantityNotifiers.removeWhere((id, _) => !currentIds.contains(id));

    // Create or update notifiers for current items
    for (var product in products) {
      if (_itemQuantityNotifiers.containsKey(product.id)) {
        // Update existing notifier if value changed
        if (_itemQuantityNotifiers[product.id]!.value != product.quantity) {
          _itemQuantityNotifiers[product.id]!.value = product.quantity;
        }
      } else {
        // Create new notifier
        _itemQuantityNotifiers[product.id] =
            ValueNotifier<int>(product.quantity);
      }
    }
  }

  // Get or create quantity notifier for a cart item
  ValueNotifier<int> _getQuantityNotifier(String itemId, int initialQuantity) {
    if (!_itemQuantityNotifiers.containsKey(itemId)) {
      _itemQuantityNotifiers[itemId] = ValueNotifier<int>(initialQuantity);
    }
    return _itemQuantityNotifiers[itemId]!;
  }

  /// Schedules a quantity update with 300ms debounce. Optimistic UI update
  /// should be done by caller before calling this.
  void _scheduleQuantityUpdate(CartProduct cartProduct, int targetQty) {
    final key = cartProduct.id;
    _pendingQuantityUpdates[key] =
        _PendingQuantityUpdate(cartProduct, targetQty);
    _quantityDebounceTimer?.cancel();
    _quantityDebounceTimer = Timer(_quantityDebounceDelay, () {
      _quantityDebounceTimer = null;
      _flushPendingQuantityUpdates();
    });
  }

  void _flushPendingQuantityUpdates() {
    final pending =
        Map<String, _PendingQuantityUpdate>.from(_pendingQuantityUpdates);
    _pendingQuantityUpdates.clear();
    for (final e in pending.values) {
      if (e.targetQty <= 0) {
        cartDatabase.removeProduct(e.product.id);
      } else {
        removetocard(e.product, e.targetQty);
      }
    }
  }

  // Diagnostic method to test database access and stream functionality
  Future<void> _testDatabaseAccess() async {
    try {
      print('🔍 [DB_TEST] Starting database access diagnostic...');

      // Test 1: Check database instance
      print('🔍 [DB_TEST] Database instance: ${cartDatabase.runtimeType}');

      // Test 2: Direct query test
      try {
        final products = await cartDatabase.allCartProducts;
        print('✅ [DB_TEST] Direct query successful: ${products.length} items');
        if (products.isNotEmpty) {
          print('✅ [DB_TEST] Sample product: ${products.first.name}');
        }
      } catch (e, stackTrace) {
        print('❌ [DB_TEST] Direct query failed: $e');
        print('❌ [DB_TEST] StackTrace: $stackTrace');
      }

      // Test 3: Stream subscription test
      try {
        StreamSubscription<List<CartProduct>>? testSubscription;
        bool streamEmitted = false;
        bool streamErrored = false;

        testSubscription = cartDatabase.watchProducts.listen(
          (data) {
            streamEmitted = true;
            print(
                '✅ [DB_TEST] Stream emitted successfully: ${data.length} items');
            if (data.isNotEmpty) {
              print('✅ [DB_TEST] Stream data sample: ${data.first.name}');
            }
          },
          onError: (error, stackTrace) {
            streamErrored = true;
            print('❌ [DB_TEST] Stream error occurred: $error');
            print('❌ [DB_TEST] Stream error stackTrace: $stackTrace');
          },
          onDone: () {
            print(
                '⚠️ [DB_TEST] Stream completed (this should not happen normally)');
          },
          cancelOnError: false,
        );

        // Wait for stream to emit or timeout after 3 seconds
        await Future.delayed(Duration(seconds: 3), () {
          if (testSubscription != null) {
            testSubscription!.cancel();
            if (!streamEmitted && !streamErrored) {
              print(
                  '⚠️ [DB_TEST] Stream test timed out - no data or error after 3s');
              print(
                  '⚠️ [DB_TEST] This may indicate the stream is not working properly');
            } else if (streamEmitted) {
              print('✅ [DB_TEST] Stream test completed successfully');
            }
          }
        });
      } catch (e, stackTrace) {
        print('❌ [DB_TEST] Stream subscription failed: $e');
        print('❌ [DB_TEST] StackTrace: $stackTrace');
      }

      print('🔍 [DB_TEST] Database diagnostic completed');
    } catch (e, stackTrace) {
      print('❌ [DB_TEST] Critical error in diagnostic: $e');
      print('❌ [DB_TEST] StackTrace: $stackTrace');
    }
  }

  /// Builds a signature for memoization to skip recalculation when inputs unchanged.
  String _totalsSignature(
      List<CartProduct> data, String delivery, double tip) {
    final cartPart = data
        .map((e) => '${e.id}:${e.quantity}:${e.price}')
        .join(';');
    return '$cartPart|$delivery|$tip';
  }

  /// Pure calculation method that computes all totals without mutating state
  /// Returns calculated values that should be applied to state via setState
  void _calculateAndUpdateTotals(
      List<CartProduct> data, List<AddAddonsDemo> lstExtras, String vendorID) {
    final sig = _totalsSignature(data, deliveryCharges, tipValue);
    if (_lastTotalsSignature == sig) {
      if (_kShowCartLogs) debugPrint(
          '🟢 [TOTALS_MEMO] Skipping recalc, signature match');
      return;
    }
    _lastTotalsSignature = sig;

    if (_kShowCartLogs) debugPrint(
        '🟢 [SUBTOTAL_CALC] _calculateAndUpdateTotals() called OUTSIDE build');

    // Calculate subtotal
    double calculatedSubTotal = 0.00;
    for (int a = 0; a < data.length; a++) {
      CartProduct e = data[a];
      if (e.extras_price != null &&
          e.extras_price != "" &&
          double.parse(e.extras_price!) != 0.0) {
        calculatedSubTotal += double.parse(e.extras_price!) * e.quantity;
      }
      calculatedSubTotal += double.parse(e.price) * e.quantity;
    }

    if (_kShowCartLogs) debugPrint(
        '🟢 [SUBTOTAL_CALC] Calculated subtotal: $calculatedSubTotal from ${data.length} items');

    // Calculate grand total
    double calculatedGrandTotal =
        calculatedSubTotal + double.parse(deliveryCharges) + tipValue;
    if (_kShowCartLogs) debugPrint(
        '🟢 [GRANDTOTAL_CALC] Grand total: $calculatedGrandTotal (subTotal: $calculatedSubTotal + delivery: $deliveryCharges + tip: $tipValue)');

    // Calculate manual coupon discount
    double calculatedDiscountAmount = 0.0;
    double calculatedManualCouponDiscountAmount = 0.0;
    if (manualCoupon != null && couponItemsNeeded == null) {
      calculatedManualCouponDiscountAmount =
          CouponService.calculateDiscountAmount(
              manualCoupon!, calculatedSubTotal);
      calculatedDiscountAmount = calculatedManualCouponDiscountAmount;
      calculatedGrandTotal = calculatedGrandTotal - calculatedDiscountAmount;
    } else if (manualCoupon != null && couponItemsNeeded != null) {
      calculatedManualCouponDiscountAmount = 0.0;
      calculatedDiscountAmount = 0.0;
    }

    // Calculate vendor special discount
    double calculatedSpecialDiscount = 0.0;
    double calculatedSpecialDiscountAmount = 0.0;
    String calculatedSpecialType = "amount";

    if (vendorModel != null) {
      if (vendorModel!.specialDiscountEnable) {
        final now = DateTime.now();
        var day = DateFormat('EEEE', 'en_US').format(now);
        var date = DateFormat('dd-MM-yyyy').format(now);

        vendorModel!.specialDiscount.forEach((element) {
          if (day == element.day.toString()) {
            if (element.timeslot!.isNotEmpty) {
              element.timeslot!.forEach((element) {
                if (element.discountType == "delivery") {
                  var start = DateFormat("dd-MM-yyyy HH:mm")
                      .parse(date + " " + element.from.toString());
                  var end = DateFormat("dd-MM-yyyy HH:mm")
                      .parse(date + " " + element.to.toString());

                  if (isCurrentDateInRange(start, end)) {
                    calculatedSpecialDiscount =
                        double.parse(element.discount.toString());
                    calculatedSpecialType = element.type.toString();

                    if (element.type == "percentage") {
                      calculatedSpecialDiscountAmount =
                          calculatedSubTotal * calculatedSpecialDiscount / 100;
                    } else {
                      calculatedSpecialDiscountAmount =
                          calculatedSpecialDiscount;
                    }

                    calculatedGrandTotal =
                        calculatedGrandTotal - calculatedSpecialDiscountAmount;
                  }
                }
              });
            }
          }
        });
      } else {
        calculatedSpecialDiscount = double.parse("0");
        calculatedSpecialType = "amount";
      }
    }

    // Select best discount (without calling async functions)
    if (_kShowCartLogs) debugPrint(
        '🟢 [STATE_UPDATE] _selectBestDiscount() called from calculation method');
    Map<String, dynamic>? calculatedSelectedDiscount = _selectBestDiscount();
    double promoDiscountAmount = 0.0;

    if (calculatedSelectedDiscount != null) {
      if (calculatedSelectedDiscount['type'] == 'first_order') {
        if (firstOrderCouponDiscount > 0) {
          promoDiscountAmount = firstOrderCouponDiscount;
        }
        calculatedSelectedDiscount['amount'] = promoDiscountAmount;
      } else if (calculatedSelectedDiscount['type'] == 'happy_hour') {
        promoDiscountAmount = happyHourDiscount;
        calculatedSelectedDiscount['amount'] = promoDiscountAmount;
      } else if (calculatedSelectedDiscount['type'] == 'new_user_promo') {
        promoDiscountAmount = newUserPromoDiscount;
        calculatedSelectedDiscount['amount'] = promoDiscountAmount;
      }

      calculatedGrandTotal -= promoDiscountAmount;
    }

    // Calculate gift card (payment order: gift card first)
    double calculatedGiftCardAmountToUse = 0.0;
    List<Map<String, dynamic>> calculatedGiftCardBreakdown = [];
    if (isGiftCardApplied && giftCardBreakdown.isNotEmpty) {
      for (final entry in giftCardBreakdown) {
        final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
        if (amt > 0) {
          calculatedGiftCardAmountToUse += amt;
          calculatedGiftCardBreakdown.add(Map<String, dynamic>.from(entry));
        }
      }
      final maxGiftCard =
          calculatedGiftCardAmountToUse.clamp(0.0, calculatedGrandTotal);
      if (maxGiftCard < calculatedGiftCardAmountToUse) {
        calculatedGiftCardAmountToUse = maxGiftCard;
        calculatedGiftCardBreakdown = _prorateGiftCardBreakdown(
          giftCardBreakdown,
          maxGiftCard,
        );
      }
      calculatedGrandTotal =
          (calculatedGrandTotal - calculatedGiftCardAmountToUse)
              .clamp(0.0, double.infinity);
    }

    // Calculate referral wallet
    double calculatedReferralWalletAmountToUse = 0.0;
    bool calculatedIsReferralWalletApplied = isReferralWalletApplied;

    if (!isNewUserPromoEligible &&
        !isFirstOrderEligible &&
        !MyAppState.currentUser!.hasCompletedFirstOrder &&
        referralWalletAmountAvailable > 0 &&
        isReferralWalletApplied) {
      final double maxUsable =
          referralWalletAmountAvailable.clamp(0.0, calculatedGrandTotal);
      calculatedReferralWalletAmountToUse = maxUsable;
      calculatedGrandTotal =
          (calculatedGrandTotal - calculatedReferralWalletAmountToUse)
              .clamp(0.0, double.infinity);
    } else {
      calculatedIsReferralWalletApplied = false;
      calculatedReferralWalletAmountToUse = 0.0;
    }

    // Loyalty free delivery (auto-applied when available)
    double effectiveLoyaltyFreeDelivery = 0.0;
    if (loyaltyFreeDeliveryRewardId != null && deliveryCharges != "0.0") {
      effectiveLoyaltyFreeDelivery =
          (double.tryParse(deliveryCharges) ?? 0.0)
              .clamp(0.0, calculatedGrandTotal);
      calculatedGrandTotal =
          (calculatedGrandTotal - effectiveLoyaltyFreeDelivery)
              .clamp(0.0, double.infinity);
    }

    // Calculate tax
    String taxAmount = " 0.0";
    if (taxList != null) {
      for (var element in taxList!) {
        final double taxableBase = (calculatedSubTotal -
                calculatedDiscountAmount -
                calculatedSpecialDiscountAmount -
                promoDiscountAmount)
            .clamp(0.0, double.infinity);
        taxAmount = (double.parse(taxAmount) +
                calculateTax(amount: taxableBase.toString(), taxModel: element))
            .toString();
      }
    }

    calculatedGrandTotal += double.parse(taxAmount);

    // Update state with all calculated values in one setState call
    if (mounted) {
      setState(() {
        subTotal = calculatedSubTotal;
        grandtotalNotifier.value = calculatedGrandTotal;
        discountAmount = calculatedDiscountAmount;
        manualCouponDiscountAmount = calculatedManualCouponDiscountAmount;
        specialDiscount = calculatedSpecialDiscount;
        specialDiscountAmount = calculatedSpecialDiscountAmount;
        specialType = calculatedSpecialType;
        selectedDiscount = calculatedSelectedDiscount;
        giftCardAmountToUse = calculatedGiftCardAmountToUse;
        if (calculatedGiftCardBreakdown.isNotEmpty) {
          giftCardBreakdown = calculatedGiftCardBreakdown;
        }
        referralWalletAmountToUse = calculatedReferralWalletAmountToUse;
        loyaltyFreeDeliveryAmount = effectiveLoyaltyFreeDelivery;
        if (isReferralWalletApplied != calculatedIsReferralWalletApplied) {
          isReferralWalletApplied = calculatedIsReferralWalletApplied;
        }
      });
    }

    if (_kShowCartLogs) debugPrint(
        '🟢 [STATE_UPDATE] State updated: subTotal=$subTotal, grandTotal=${grandtotalNotifier.value}');
  }

  // Calculate Happy Hour discount asynchronously
  Future<void> _calculateHappyHourDiscount(
      double subTotal, String vendorID) async {
    if (cartProducts.isEmpty || vendorModel == null) {
      // TODO: large rebuild
      if (!mounted) return;
      setState(() {
        happyHourDiscount = 0.0;
        activeHappyHourConfig = null;
        happyHourError = null;
        happyHourItemsNeeded = null;
        _isHappyHourLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isHappyHourLoading = true;
    });

    try {
      final settings = await HappyHourService.getHappyHourSettings();
      final activeConfig = await HappyHourHelper.getActiveHappyHour(settings);

      if (activeConfig != null) {
        // Calculate total item count
        int totalItemCount =
            cartProducts.fold(0, (sum, item) => sum + item.quantity);

        final validation = await HappyHourHelper.validateHappyHourEligibility(
          config: activeConfig,
          user: MyAppState.currentUser,
          restaurantId: vendorID,
          orderSubtotal: subTotal,
          deliveryCharge: double.tryParse(deliveryCharges) ?? 0.0,
          totalItemCount: totalItemCount,
        );

        if (mounted) {
          // TODO: large rebuild
          if (!mounted) return;
          setState(() {
            if (validation['eligible'] == true) {
              activeHappyHourConfig = activeConfig;
              happyHourDiscount = validation['discount'] as double;
              happyHourError = null;
              happyHourItemsNeeded = null;
            } else {
              // Only keep activeHappyHourConfig if failure is due to minimum item requirement
              // This allows us to show the helpful message
              final isMinItemFailure = validation['itemsNeeded'] != null;
              activeHappyHourConfig = isMinItemFailure ? activeConfig : null;
              happyHourDiscount = 0.0;
              happyHourError = validation['reason'] as String;
              // Extract itemsNeeded if minimum item requirement not met
              happyHourItemsNeeded = validation['itemsNeeded'] as int?;
            }
            _isHappyHourLoading = false;
          });
        }
      } else {
        if (mounted) {
          // TODO: large rebuild
          if (!mounted) return;
          setState(() {
            activeHappyHourConfig = null;
            happyHourDiscount = 0.0;
            happyHourError = null;
            happyHourItemsNeeded = null;
            _isHappyHourLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error applying Happy Hour discount: $e');
      if (mounted) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          activeHappyHourConfig = null;
          happyHourDiscount = 0.0;
          happyHourError = null;
          happyHourItemsNeeded = null;
          _isHappyHourLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final userId = MyAppState.currentUser?.userID;
    if (userId != null && userId.isNotEmpty) {
      AnalyticsService.trackFunnelStep(userId, 'cart_view');
    }

    addressModel = MyAppState.selectedPosition;

    coupon = _fireStoreUtils.getAllCoupons();

    // Initialize caches
    _productCache = {};
    _vendorCache = {};

    // Use addPostFrameCallback for context-dependent operations
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isInitialized) {
        _initializeData();
      }
    });

    _statusCheckTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkCartRestaurantStatus(),
    );
  }

  // Initialize data after first frame
  Future<void> _initializeData() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!mounted) return;
    setState(() {
      _isInitialDataLoading = true;
    });

    await getFoodType();
    await _checkFirstOrderEligibility();
    await _checkReferralPath();
    await _loadReferralWalletBalance();
    await _loadGiftCards();
    await _loadLoyaltyFreeDelivery();
    await _checkNewUserPromoEligibility();

    if (mounted) {
      if (!mounted) return;
      setState(() {
        _isInitialDataLoading = false;
      });
    }
  }

  getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    // TODO: large rebuild
    if (!mounted) return;
    setState(() {
      selctedOrderTypeValue =
          sp.getString("foodType") == "" || sp.getString("foodType") == null
              ? "Delivery"
              : sp.getString("foodType");
      _isDeliveryReady = false;
    });
  }

  Future<void> _checkFirstOrderEligibility() async {
    try {
      if (MyAppState.currentUser == null) return;
      final query = await FirebaseFirestore.instance
          .collection(ORDERS)
          .where('authorID', isEqualTo: MyAppState.currentUser!.userID)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        isFirstOrderEligible = query.docs.isEmpty;
      });
    } catch (e) {
      // If something goes wrong, do not block checkout; just skip the benefit
      if (!mounted) return;
      setState(() {
        isFirstOrderEligible = false;
      });
    }
  }

  Future<void> _checkReferralPath() async {
    try {
      if (MyAppState.currentUser == null) return;

      bool onReferralPath = await FireStoreUtils.isCustomerOnReferralPath(
          MyAppState.currentUser!.userID);

      isReferralPathNotifier.value = onReferralPath;

      print(
          '🔍 Customer referral path status: ${isReferralPathNotifier.value}');
    } catch (e) {
      print('❌ Error checking referral path: $e');
      isReferralPathNotifier.value = false;
    }
  }

  Future<void> _loadGiftCards() async {
    try {
      if (MyAppState.currentUser == null) {
        if (!mounted) return;
        setState(() {
          activeGiftCards = [];
          giftCardConfig = null;
        });
        return;
      }
      final cfg = await GiftCardService.getConfig();
      final cards = await GiftCardService.getUserActiveGiftCards(
        MyAppState.currentUser!.userID,
      );
      if (!mounted) return;
      setState(() {
        activeGiftCards = cards;
        giftCardConfig = cfg;
      });
    } catch (e) {
      debugPrint('Error loading gift cards: $e');
      if (!mounted) return;
      setState(() {
        activeGiftCards = [];
        giftCardConfig = null;
      });
    }
  }

  Future<void> _loadReferralWalletBalance() async {
    try {
      if (MyAppState.currentUser == null) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          referralWalletAmountAvailable = 0.0;
        });
        return;
      }

      // Refresh user data to get latest referral wallet balance
      final user =
          await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);
      if (user != null) {
        MyAppState.currentUser = user;
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          referralWalletAmountAvailable = user.referralWalletAmount;
        });
      }
    } catch (e) {
      print('Error loading referral wallet balance: $e');
      // TODO: large rebuild
      if (!mounted) return;
      setState(() {
        referralWalletAmountAvailable = 0.0;
      });
    }
  }

  Future<void> _loadLoyaltyFreeDelivery() async {
    try {
      if (MyAppState.currentUser == null) return;
      final config = await LoyaltyService.getLoyaltyConfig();
      if (config?['enabled'] != true) return;
      final loyalty = await LoyaltyService.getLoyalty(MyAppState.currentUser!.userID);
      if (loyalty == null || loyalty.currentCycle.isEmpty) return;

      final freeDelivery = loyalty.rewardsClaimed.where((r) {
        return r.rewardId == 'free_delivery' &&
            !r.isExpired &&
            !r.isUsed &&
            r.cycle == loyalty.currentCycle;
      }).toList();

      if (!mounted) return;
      setState(() {
        if (freeDelivery.isNotEmpty) {
          loyaltyFreeDeliveryRewardId = 'free_delivery';
          loyaltyFreeDeliveryCycle = loyalty.currentCycle;
        } else {
          loyaltyFreeDeliveryRewardId = null;
          loyaltyFreeDeliveryCycle = null;
          loyaltyFreeDeliveryAmount = 0.0;
        }
      });
    } catch (e) {
      debugPrint('Error loading loyalty free delivery: $e');
      if (!mounted) return;
      setState(() {
        loyaltyFreeDeliveryRewardId = null;
        loyaltyFreeDeliveryCycle = null;
        loyaltyFreeDeliveryAmount = 0.0;
      });
    }
  }

  Future<void> _checkNewUserPromoEligibility() async {
    try {
      if (mounted) {
        if (!mounted) return;
        setState(() {
          _isNewUserPromoLoading = true;
        });
      }

      if (MyAppState.currentUser == null) {
        if (mounted) {
          if (!mounted) return;
          setState(() {
            isNewUserPromoEligible = false;
            newUserPromoDiscount = 0.0;
            _isNewUserPromoLoading = false;
          });
        }
        return;
      }

      // Calculate current subtotal
      double currentSubTotal = 0.0;
      for (var e in cartProducts) {
        if (e.extras_price != null &&
            e.extras_price != "" &&
            double.tryParse(e.extras_price!) != null &&
            double.parse(e.extras_price!) != 0.0) {
          currentSubTotal += double.parse(e.extras_price!) * e.quantity;
        }
        currentSubTotal += double.parse(e.price) * e.quantity;
      }

      // Check eligibility: not completed first order and not ordered before
      final eligible = NewUserPromoService.isEligible(
        hasCompletedFirstOrder: MyAppState.currentUser!.hasCompletedFirstOrder,
        hasOrderedBefore: MyAppState.currentUser!.hasOrderedBefore,
      );

      if (eligible) {
        final config = await NewUserPromoService.getNewUserPromoConfig();
        if (config.isEnabled && currentSubTotal > 0) {
          final discount = NewUserPromoService.calculateDiscount(
            config: config,
            orderSubtotal: currentSubTotal,
          );

          if (mounted) {
            // TODO: large rebuild
            if (!mounted) return;
            setState(() {
              isNewUserPromoEligible = discount > 0;
              newUserPromoDiscount = discount;
              newUserPromoConfig = config;
              _isNewUserPromoLoading = false;
            });
          }
        } else {
          if (mounted) {
            // TODO: large rebuild
            if (!mounted) return;
            setState(() {
              isNewUserPromoEligible = false;
              newUserPromoDiscount = 0.0;
              _isNewUserPromoLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          // TODO: large rebuild
          if (!mounted) return;
          setState(() {
            isNewUserPromoEligible = false;
            newUserPromoDiscount = 0.0;
            _isNewUserPromoLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error checking New User Promo eligibility: $e');
      if (mounted) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          isNewUserPromoEligible = false;
          newUserPromoDiscount = 0.0;
          _isNewUserPromoLoading = false;
        });
      }
    }
  }

  Future<void> _checkAndApplyFirstOrderCoupon(double subTotal) async {
    if (!mounted) return;
    setState(() {
      _isFirstOrderCouponLoading = true;
    });

    try {
      // Check if user has ordered before - use isFirstOrderEligible which checks orders collection directly
      if (MyAppState.currentUser == null) {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
        return;
      }

      // Use isFirstOrderEligible instead of hasOrderedBefore for more accurate check
      // isFirstOrderEligible is set by _checkFirstOrderEligibility() which queries orders collection
      if (!isFirstOrderEligible) {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
        return;
      }

      // Fetch coupon configuration
      final config = await FirstOrderCouponService.getFirstOrderCouponConfig();

      // Verify coupon is active
      if (!config.isEnabled) {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
        return;
      }

      // Check date validity
      if (!config.isValidDateRange) {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
        return;
      }

      // Check minimum order amount
      if (subTotal < config.minOrderAmount) {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
        return;
      }

      // Calculate discount
      double discount = 0.0;
      if (config.discountType.toLowerCase() == "percentage" ||
          config.discountType.toLowerCase() == "percent") {
        discount = (subTotal * config.discount) / 100;
      } else {
        // Fixed amount discount (handles "fixed", "fixed_amount", etc.)
        discount = config.discount;
      }

      // Apply discount (cannot exceed subtotal)
      discount = discount > subTotal ? subTotal : discount;

      // Update state after build phase
      if (discount > 0) {
        _updateCouponStateAfterBuild(
            true, discount, config.couponId, config.couponCode);
      } else {
        _updateCouponStateAfterBuild(false, 0.0, null, null);
      }
    } catch (e) {
      print('❌ Error checking first-order coupon: $e');
      _updateCouponStateAfterBuild(false, 0.0, null, null);
    }
  }

  // Helper method to update coupon state after build phase
  void _updateCouponStateAfterBuild(
      bool eligible, double discount, String? couponId, String? couponCode) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // TODO: large rebuild
      setState(() {
        isFirstOrderCouponEligible = eligible;
        firstOrderCouponDiscount = discount;
        firstOrderCouponId = couponId;
        firstOrderCouponCode = couponCode;
        _isFirstOrderCouponLoading = false;
      });
    });
  }

  // Select the best available discount based on priority
  // Priority: Manual Coupon > New User Promo > First-User Discount > Happy Hour
  // Note: Referral wallet is handled separately and cannot be used with New User Promo
  Map<String, dynamic>? _selectBestDiscount() {
    // Priority 1: Manual coupon applied - disable all promo discounts
    if (manualCoupon != null) {
      return null;
    }

    // Priority 2: Referral path disables all discounts
    if (isReferralPath) {
      return null;
    }

    // Priority 3: New User Promo (only on first order, cannot stack with referral wallet)
    if (isNewUserPromoEligible && newUserPromoDiscount > 0) {
      // Disable referral wallet if New User Promo is eligible
      isReferralWalletApplied = false;
      referralWalletAmountToUse = 0.0;

      return {
        'type': 'new_user_promo',
        'amount': newUserPromoDiscount,
        'label': 'New User Promo',
        'couponId': newUserPromoConfig?.promoId,
        'couponCode': newUserPromoConfig?.promoCode,
      };
    }

    // Priority 4: First-User Discount (legacy first order coupon)
    // Only use discount from database, no hardcoded fallback
    double firstOrderAmount = 0.0;
    if (firstOrderCouponDiscount > 0) {
      firstOrderAmount = firstOrderCouponDiscount;
    }

    if (firstOrderAmount > 0) {
      // Disable referral wallet on first order
      isReferralWalletApplied = false;
      referralWalletAmountToUse = 0.0;

      return {
        'type': 'first_order',
        'amount': firstOrderAmount,
        'label': firstOrderCouponDiscount > 0
            ? 'First-Order Discount'
            : 'First-Order Discount',
        'couponId': firstOrderCouponId,
        'couponCode': firstOrderCouponCode,
      };
    }

    // Priority 5: Happy Hour
    if (happyHourDiscount > 0) {
      return {
        'type': 'happy_hour',
        'amount': happyHourDiscount,
        'label': 'Happy Hour: ${activeHappyHourConfig?.name ?? ''}',
        'couponId': null,
        'couponCode': null,
      };
    }

    return null;
  }

  // Generate audit note for discount selection (single-discount policy)
  String _generateDiscountAuditNote() {
    List<String> eligibleDiscounts = [];
    String appliedDiscount = 'none';

    // Check which discounts were eligible
    if (isReferralPath) {
      return 'Referral active → all promos disabled (mutually exclusive)';
    }

    if (firstOrderCouponDiscount > 0 || isFirstOrderEligible) {
      eligibleDiscounts.add('first_order');
    }
    if (happyHourDiscount > 0) {
      eligibleDiscounts.add('happy_hour');
    }

    // Determine which discount was applied
    if (selectedDiscount != null) {
      appliedDiscount = selectedDiscount!['type'] as String;
      double appliedAmount = selectedDiscount!['amount'] as double;

      String note =
          'Applied: ${appliedDiscount} (${appliedAmount.toStringAsFixed(2)})';
      if (eligibleDiscounts.length > 1) {
        List<String> notApplied =
            eligibleDiscounts.where((d) => d != appliedDiscount).toList();
        if (notApplied.isNotEmpty) {
          note +=
              ' | Not applied: ${notApplied.join(", ")} (single-discount policy)';
        }
      }
      return note;
    }

    if (eligibleDiscounts.isEmpty) {
      return 'No eligible discounts';
    }

    return 'No discount applied (single-discount policy)';
  }

  // Validate and apply manual coupon
  Future<void> _validateAndApplyManualCoupon() async {
    final couponCode = manualCouponCodeController.text.trim().toUpperCase();

    if (couponCode.isEmpty) {
      // TODO: large rebuild
      if (!mounted) return;
      setState(() {
        manualCouponError = 'Please enter a coupon code';
        manualCoupon = null;
        manualCouponDiscountAmount = 0.0;
        couponItemsNeeded = null;
      });
      return;
    }

    // TODO: large rebuild
    if (!mounted) return;
    setState(() {
      isManualCouponValidating = true;
      manualCouponError = null;
    });

    try {
      final userId = MyAppState.currentUser?.userID ?? '';
      // Calculate total item count
      int totalItemCount =
          cartProducts.fold(0, (sum, item) => sum + item.quantity);

      final validation = await CouponService.validateCoupon(
        couponCode,
        subTotal,
        userId,
        vendorID.isEmpty ? null : vendorID,
        totalItemCount: totalItemCount,
      );

      if (mounted) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          isManualCouponValidating = false;

          if (validation['valid'] == true && validation['coupon'] != null) {
            manualCoupon = validation['coupon'] as OfferModel;
            manualCouponError = null;
            couponItemsNeeded = null;
            // Calculate discount amount
            manualCouponDiscountAmount =
                CouponService.calculateDiscountAmount(manualCoupon!, subTotal);
          } else {
            // Extract itemsNeeded if minimum item requirement not met
            couponItemsNeeded = validation['itemsNeeded'] as int?;
            // Only clear coupon if it's not a minimum item requirement failure
            // (keep coupon to show helpful message)
            if (couponItemsNeeded == null) {
              manualCoupon = null;
              manualCouponDiscountAmount = 0.0;
              manualCouponError =
                  validation['error'] as String? ?? 'Invalid coupon code';
            } else {
              // Keep coupon but set discount to 0
              manualCoupon = validation['coupon'] as OfferModel?;
              manualCouponDiscountAmount = 0.0;
              // Set clear error message for minimum item requirement
              manualCouponError = couponItemsNeeded! > 0
                  ? 'Requires at least ${(couponItemsNeeded! + totalItemCount)} eligible items'
                  : 'This promo does not apply to your cart';
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          isManualCouponValidating = false;
          manualCoupon = null;
          manualCouponDiscountAmount = 0.0;
          couponItemsNeeded = null;
          manualCouponError = 'An error occurred. Please try again.';
        });
      }
    }
  }

  // Remove manual coupon
  void _removeManualCoupon() {
    // TODO: large rebuild
    setState(() {
      manualCoupon = null;
      manualCouponCodeController.clear();
      manualCouponDiscountAmount = 0.0;
      manualCouponError = null;
      couponItemsNeeded = null;
    });
  }

  Future<void> _openVoucherScreen() async {
    final totalItemCount =
        cartProducts.fold(0, (sum, item) => sum + item.quantity);

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VoucherScreen(
          subTotal: subTotal,
          vendorId: vendorID.isEmpty ? null : vendorID,
          totalItemCount: totalItemCount,
          prefillCode:
              manualCoupon?.offerCode ?? manualCouponCodeController.text,
        ),
      ),
    );

    if (!mounted) return;
    if (result is String && result.trim().isNotEmpty) {
      manualCouponCodeController.text = result.trim().toUpperCase();
      await _validateAndApplyManualCoupon();
    }
  }

  // Re-validate manual coupon when cart changes
  Future<void> _revalidateManualCoupon(double calculatedSubTotal) async {
    if (manualCoupon == null) return;

    try {
      // Unfocus any text fields to prevent keyboard from showing during rebuild
      if (mounted) {
        FocusScope.of(context).unfocus();
      }

      final userId = MyAppState.currentUser?.userID ?? '';
      // Calculate total item count from current cart
      int totalItemCount =
          cartProducts.fold(0, (sum, item) => sum + item.quantity);

      final validation = await CouponService.validateCoupon(
        manualCoupon!.offerCode ?? '',
        calculatedSubTotal,
        userId,
        vendorID.isEmpty ? null : vendorID,
        totalItemCount: totalItemCount,
      );

      if (mounted) {
        // TODO: large rebuild
        if (!mounted) return;
        setState(() {
          if (validation['valid'] == true && validation['coupon'] != null) {
            // Coupon is still valid
            manualCoupon = validation['coupon'] as OfferModel;
            manualCouponError = null;
            couponItemsNeeded = null;
            // Recalculate discount amount
            manualCouponDiscountAmount = CouponService.calculateDiscountAmount(
                manualCoupon!, calculatedSubTotal);
          } else {
            // Extract itemsNeeded if minimum item requirement not met
            couponItemsNeeded = validation['itemsNeeded'] as int?;
            // Only clear coupon if it's not a minimum item requirement failure
            if (couponItemsNeeded == null) {
              manualCoupon = null;
              manualCouponDiscountAmount = 0.0;
              manualCouponError =
                  validation['error'] as String? ?? 'Coupon is no longer valid';
            } else {
              // Keep coupon but set discount to 0
              manualCoupon = validation['coupon'] as OfferModel?;
              manualCouponDiscountAmount = 0.0;
              manualCouponError = validation['error'] as String? ??
                  'Coupon requirement not met';
            }
          }
        });
      }
    } catch (e) {
      // On error, keep current state to avoid disrupting user experience
      print('Error re-validating coupon: $e');
    }
  }

  //Future<void> getDeliveyData() async {

  //  isDeliverFound = true;

  //  await _fireStoreUtils

  //      .getVendorByVendorID(cartProducts.first.vendorID)

  //      .then((value) {

  //    vendorModel = value;

  //  });

  /// Generates a cache key from vendor ID and address ID/coordinates
  String _getCacheKey(String vendorID, AddressModel address) {
    final addressKey = address.id ??
        '${address.location?.latitude ?? 0}_${address.location?.longitude ?? 0}';
    return '${vendorID}_$addressKey';
  }

  static const double _kCoordEpsilon = 1e-6;

  /// Checks if distance should be recalculated based on vendor/address changes
  bool _shouldRecalculateDistance(String vendorID, AddressModel address) {
    final hasVendorChanged = vendorID != _lastCalculatedVendorID;

    // Check if address changed
    bool hasAddressChanged = false;
    if (address.id != null) {
      // If address has ID, compare IDs
      hasAddressChanged = address.id != _lastCalculatedAddressID;
    } else {
      // If address has no ID (custom/pinned), compare stored coordinates
      if (_lastCalculatedAddressID != null) {
        // Previously had ID, now we don't - treat as changed
        hasAddressChanged = true;
      } else {
        // Both have no ID: compare current coords with stored last coords
        final loc = address.location;
        if (loc == null ||
            _lastCalculatedLat == null ||
            _lastCalculatedLng == null) {
          hasAddressChanged = true;
        } else {
          hasAddressChanged =
              (loc.latitude - _lastCalculatedLat!).abs() > _kCoordEpsilon ||
                  (loc.longitude - _lastCalculatedLng!).abs() > _kCoordEpsilon;
        }
      }
    }

    return hasVendorChanged || hasAddressChanged;
  }

  /// Debounced wrapper for getDeliveyData to prevent excessive API calls.
  /// [forceFresh] uses live location and bypasses distance/delivery cache.
  void _debouncedGetDeliveryData({
    bool immediate = false,
    bool forceFresh = false,
  }) {
    _distanceCalculationDebounceTimer?.cancel();
    _distanceCalculationDebounceTimer = null;

    if (immediate) {
      getDeliveyData(forceFresh: true);
      return;
    }

    final useFresh = forceFresh;
    _distanceCalculationDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        getDeliveyData(forceFresh: useFresh);
      }
    });
  }

  Future<void> getDeliveyData({bool forceFresh = false}) async {
    final stopwatch = Stopwatch()..start();
    print('🟠 [DELIVERY_DATA] getDeliveyData started');
    debugPrint("getDeliveyData started");

    if (mounted && !_isDeliveryDataLoading) {
      if (!mounted) return;
      setState(() {
        _isDeliveryDataLoading = true;
        _isDeliveryReady = false;
        _deliveryCalcFailed = false;
      });
    }

    try {
      // When using live location and address is current location (no saved id),
      // fetch fresh GPS so delivery charge is based on current position.
      if (forceFresh &&
          addressModel.id == null &&
          selctedOrderTypeValue == "Delivery") {
        try {
          final Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          if (mounted) {
            addressModel.location = UserLocation(
              latitude: position.latitude,
              longitude: position.longitude,
            );
            MyAppState.selectedPosition = addressModel;
          }
        } catch (_) {
          // Keep existing location if GPS fails
        }
      }

      // Early return if no cart products or address not set
      if (cartProducts.isEmpty ||
          addressModel.location == null ||
          selctedOrderTypeValue != "Delivery") {
        // Invalidate cache if cart is empty
        if (cartProducts.isEmpty) {
          _invalidateDeliveryCache();
        }
        // If order type is not Delivery, invalidate cache and mark as ready (no calculation needed)
        if (selctedOrderTypeValue != "Delivery") {
          _invalidateDeliveryCache();
          if (mounted) {
            setState(() {
              _isDeliveryReady = true;
              _estimatedDeliveryTimeText = null;
            });
          }
        }
        return;
      }

      final currentVendorID = cartProducts.first.vendorID;

      // Check if we need to recalculate distance (forceFresh skips cache)
      final shouldRecalculate = forceFresh ||
          _shouldRecalculateDistance(currentVendorID, addressModel);

      // If vendor and address haven't changed, reuse cached distance
      if (!shouldRecalculate && _cachedDistanceKm != null) {
        debugPrint(
            "Reusing cached distance: ${_cachedDistanceKm}km (vendor: $currentVendorID, address: ${addressModel.id ?? 'coord'})");

        isDeliverFound = true;

        // Ensure vendorModel is available (may have been cleared)
        if (vendorModel == null || vendorModel!.id != currentVendorID) {
          await _fireStoreUtils
              .getVendorByVendorID(currentVendorID)
              .then((value) {
            vendorModel = value;
            debugPrint(
                "Fetched vendorModel for cached distance: ${vendorModel?.toJson()}");

            // Recalculate happy hour discount now that vendorModel is available
            if (mounted && cartProducts.isNotEmpty) {
              double calculatedSubTotal = 0.0;
              for (var e in cartProducts) {
                if (e.extras_price != null &&
                    e.extras_price != "" &&
                    double.tryParse(e.extras_price!) != null &&
                    double.parse(e.extras_price!) != 0.0) {
                  calculatedSubTotal +=
                      double.parse(e.extras_price!) * e.quantity;
                }
                calculatedSubTotal += double.parse(e.price) * e.quantity;
              }
              _calculateHappyHourDiscount(calculatedSubTotal, currentVendorID);
            }
          });
        }

        // Continue to delivery charges calculation below
      } else {
        // Vendor or address changed, need to recalculate
        debugPrint(
            "Vendor or address changed, recalculating distance (vendor: $currentVendorID, address: ${addressModel.id ?? 'coord'})");

        isDeliverFound = true;

        // Fetch vendor details
        await _fireStoreUtils
            .getVendorByVendorID(currentVendorID)
            .then((value) {
          vendorModel = value;
          debugPrint("Fetched vendorModel: ${vendorModel?.toJson()}");

          // Recalculate happy hour discount now that vendorModel is available
          if (mounted && cartProducts.isNotEmpty) {
            double calculatedSubTotal = 0.0;
            for (var e in cartProducts) {
              if (e.extras_price != null &&
                  e.extras_price != "" &&
                  double.tryParse(e.extras_price!) != null &&
                  double.parse(e.extras_price!) != 0.0) {
                calculatedSubTotal +=
                    double.parse(e.extras_price!) * e.quantity;
              }
              calculatedSubTotal += double.parse(e.price) * e.quantity;
            }
            _calculateHappyHourDiscount(calculatedSubTotal, currentVendorID);
          }
        });

        if (vendorModel == null || addressModel.location == null) {
          debugPrint(
              "Vendor or address not available, skipping distance calculation");
          return;
        }

        // Calculate road-based distance using Google Directions API
        // Falls back to straight-line distance if API call fails
        final double distanceKm = await DistanceService.getRoadDistanceKm(
          addressModel.location!.latitude,
          addressModel.location!.longitude,
          vendorModel!.latitude,
          vendorModel!.longitude,
          bypassCache: forceFresh,
        );

        // Cache the calculated distance
        _cachedDistanceKm = distanceKm;
        _lastCalculatedVendorID = currentVendorID;
        _lastCalculatedAddressID = addressModel.id;
        if (addressModel.id == null && addressModel.location != null) {
          _lastCalculatedLat = addressModel.location!.latitude;
          _lastCalculatedLng = addressModel.location!.longitude;
        } else {
          _lastCalculatedLat = null;
          _lastCalculatedLng = null;
        }
        _cacheTimestamp = DateTime.now();

        debugPrint("Calculated and cached distance: ${distanceKm}km");
      }

      if (selctedOrderTypeValue == "Delivery" && _cachedDistanceKm != null) {
        // Use cached distance if available, otherwise use the newly calculated one
        final double distanceKm = _cachedDistanceKm!;
        final String estimatedTimeText =
            _buildEstimatedDeliveryTimeText(distanceKm);

        // Fetch delivery charges model
        await _fireStoreUtils.getDeliveryCharges().then((value) {
          if (value != null) {
            DeliveryChargeModel deliveryChargeModel = value;

            debugPrint(
                "Fetched deliveryChargeModel: ${deliveryChargeModel.toJson()}");

            // New_DeliveryCharge formula: < 1km = baseDeliveryCharge,
            // >= 1km = baseDeliveryCharge + distance * deliveryChargePerKm
            final double baseCharge =
                deliveryChargeModel.baseDeliveryCharge.toDouble();
            final double perKm =
                deliveryChargeModel.deliveryChargePerKm.toDouble();
            final double thresholdKm =
                deliveryChargeModel.minimumDistanceKm.toDouble();

            debugPrint(
                "Delivery Charges - Base: $baseCharge, ThresholdKm: $thresholdKm, PerKm: $perKm");

            double calculatedDeliveryCharges = 0.0;
            final double effectiveThreshold = thresholdKm > 0 ? thresholdKm : 1;

            if (distanceKm < effectiveThreshold) {
              calculatedDeliveryCharges = baseCharge;
              debugPrint(
                  "Within base distance (<${effectiveThreshold}km). Charge: $calculatedDeliveryCharges");
            } else {
              calculatedDeliveryCharges = baseCharge + (distanceKm * perKm);
              debugPrint(
                  "Beyond base distance. Charge: $calculatedDeliveryCharges");
            }

            if (calculatedDeliveryCharges <= 0 && baseCharge > 0) {
              calculatedDeliveryCharges = baseCharge;
            }

            // Round to whole number (no decimal points)
            calculatedDeliveryCharges =
                calculatedDeliveryCharges.roundToDouble();
            deliveryCharges = calculatedDeliveryCharges.toStringAsFixed(0);
            print('🟢 [DELIVERY_DATA] Final delivery charge: $deliveryCharges');
            debugPrint("Final delivery charge computed: $deliveryCharges");

            // Validate charge is valid and greater than zero before caching
            final chargeValue = double.tryParse(deliveryCharges);
            if (chargeValue != null && chargeValue > 0) {
              print(
                  '🟢 [DELIVERY_DATA] Delivery calculation complete, updating state');
              // TODO: large rebuild
              if (!mounted) return;
              setState(() {
                // Write cache atomically with state update
                _cachedDeliveryCharge = deliveryCharges;
                _isDeliveryReady = true;
                _estimatedDeliveryTimeText = estimatedTimeText;
              });
            } else {
              // Charge is 0 or invalid - don't cache, but still mark as ready
              // TODO: large rebuild
              if (!mounted) return;
              setState(() {
                _isDeliveryReady = true;
                _estimatedDeliveryTimeText = estimatedTimeText;
              });
            }
          }
        });
      }
    } catch (e, st) {
      debugPrint('Delivery calculation failed: $e');
      debugPrint('StackTrace: $st');
      if (mounted) {
        setState(() {
          _deliveryCalcFailed = true;
        });
      }
    } finally {
      stopwatch.stop();
      PerformanceLogger.logDeliveryCalculation(stopwatch.elapsed);
      if (mounted) {
        setState(() {
          _isDeliveryDataLoading = false;
        });
        if (cartProducts.isNotEmpty) {
          _calculateAndUpdateTotals(cartProducts, lstExtras, vendorID);
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    cartDatabase = Provider.of<CartDatabase>(context, listen: true);

    cartFuture = cartDatabase.allCartProducts;

    // Move async operations to post-frame callback to avoid calling during build
    if (!_isDependenciesInitialized) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeDependencies();
        }
      });
    }
  }

  // Initialize dependencies after frame
  Future<void> _initializeDependencies() async {
    if (_isDependenciesInitialized) return;
    _isDependenciesInitialized = true;

    // Run database diagnostic test (works in release builds)
    // This runs after cartDatabase is initialized in didChangeDependencies
    _testDatabaseAccess();

    setState(() {
      _isAdminCommissionLoading = true;
    });

    _fireStoreUtils.getAdminCommission().then((value) {
      if (!mounted) return;
      setState(() {
        _isAdminCommissionLoading = false;
        if (value != null) {
          adminCommission = value;

          adminCommissionValue = adminCommission!["adminCommission"].toString();

          addminCommissionType =
              adminCommission!["addminCommissionType"].toString();

          isEnableAdminCommission = adminCommission!["isAdminCommission"];
        }
      });
    });

    await getPrefData();
  }

  bool hasDefaultAddress() {
    if (MyAppState.currentUser != null &&
        MyAppState.currentUser!.shippingAddress != null) {
      return MyAppState.currentUser!.shippingAddress!
          .any((address) => address.isDefault == true);
    }
    return false;
  }

  // Handle cart data changes via post-frame callback
  void _handleCartDataChange(
      List<CartProduct> newCartProducts, String newVendorID) {
    if (_kShowCartLogs) print('🔵 [CART_LIFECYCLE] _handleCartDataChange called from build');
    // Check if cart data actually changed
    final bool cartChanged = _lastCartProducts == null ||
        _lastCartProducts!.length != newCartProducts.length ||
        _lastVendorID != newVendorID;

    if (_kShowCartLogs) debugPrint(
        '🟡 [CART_LIFECYCLE] Cart changed: $cartChanged (items: ${newCartProducts.length}, vendor: $newVendorID)');
    if (!cartChanged) return;

    // Update tracking variables
    _lastCartProducts = List.from(newCartProducts);
    _lastVendorID = newVendorID;

    // Use post-frame callback to trigger async operations
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateCartDependentData(newCartProducts, newVendorID);
      }
    });
  }

  // Update data that depends on cart changes
  Future<void> _updateCartDependentData(
      List<CartProduct> cartProducts, String vendorID) async {
    if (_kShowCartLogs) print('🟣 [STATE_UPDATE] _updateCartDependentData started');
    // Update vendorID state
    if (this.vendorID != vendorID) {
      if (_kShowCartLogs) debugPrint(
          '🟣 [STATE_UPDATE] Vendor ID changed from ${this.vendorID} to $vendorID');
      setState(() {
        this.vendorID = vendorID;
      });
    }

    // Ensure vendorModel is loaded before calculating discounts
    final currentVendorID =
        cartProducts.isNotEmpty ? cartProducts.first.vendorID : vendorID;
    if (vendorModel == null || vendorModel!.id != currentVendorID) {
      await _fireStoreUtils.getVendorByVendorID(currentVendorID).then((value) {
        if (!mounted) return;
        setState(() {
          vendorModel = value;
        });
      });
    }

    // Check if vendor or address changed to trigger distance recalculation
    final shouldCheckDistance = cartProducts.isNotEmpty &&
        selctedOrderTypeValue == "Delivery" &&
        addressModel.location != null &&
        !_isDeliveryDataLoading;

    if (shouldCheckDistance) {
      final vendorChanged = currentVendorID != _lastCalculatedVendorID;
      final addressChanged = addressModel.id != _lastCalculatedAddressID ||
          (addressModel.id == null && _lastCalculatedAddressID != null);

      // Invalidate cache if vendor changed
      if (vendorChanged) {
        _invalidateDeliveryCache();
      }

      // Check for valid cached delivery result (skip when using live location)
      if (!_useLiveLocationOnNextDeliveryCalc &&
          !vendorChanged &&
          !addressChanged &&
          _cachedDistanceKm != null &&
          _cachedDeliveryCharge != null) {
        // Check if cache has expired (10 minutes)
        final cacheAge = _cacheTimestamp != null
            ? DateTime.now().difference(_cacheTimestamp!)
            : null;
        final isExpired =
            cacheAge == null || cacheAge.inMinutes >= _cacheExpiryMinutes;

        if (isExpired) {
          _invalidateDeliveryCache();
        } else {
          // Parse cached charge to verify it's greater than zero
          final cachedChargeValue = double.tryParse(_cachedDeliveryCharge!);
          if (cachedChargeValue != null && cachedChargeValue > 0) {
            if (mounted) {
              setState(() {
                deliveryCharges = _cachedDeliveryCharge!;
                _isDeliveryReady = true;
                _isDeliveryDataLoading = false;
                _estimatedDeliveryTimeText =
                    _buildEstimatedDeliveryTimeText(_cachedDistanceKm!);
              });
            }
            return;
          }
        }
      }

      // Trigger delivery calculation (use live location when flag is set)
      if (vendorChanged ||
          addressChanged ||
          _cachedDistanceKm == null ||
          _useLiveLocationOnNextDeliveryCalc) {
        if (mounted && !_isDeliveryDataLoading) {
          setState(() {
            _isDeliveryDataLoading = true;
            _isDeliveryReady = false;
          });
        }
        final useLive = _useLiveLocationOnNextDeliveryCalc;
        _useLiveLocationOnNextDeliveryCalc = false;
        // Use live location immediately when opening cart or after pull-to-refresh
        if (useLive) {
          getDeliveyData(forceFresh: true);
        } else {
          _debouncedGetDeliveryData(immediate: false, forceFresh: false);
        }
      }
    }

    // Calculate subtotal for discount calculations
    double calculatedSubTotal = 0.0;
    for (var e in cartProducts) {
      if (e.extras_price != null &&
          e.extras_price != "" &&
          double.tryParse(e.extras_price!) != null &&
          double.parse(e.extras_price!) != 0.0) {
        calculatedSubTotal += double.parse(e.extras_price!) * e.quantity;
      }
      calculatedSubTotal += double.parse(e.price) * e.quantity;
    }

    if (_kShowCartLogs) debugPrint(
        '🟢 [SUBTOTAL_CALC] Calculated subtotal in _updateCartDependentData: $calculatedSubTotal');
    // Only trigger discount calculations if subtotal changed
    if (_lastSubTotal == null || _lastSubTotal != calculatedSubTotal) {
      if (_kShowCartLogs) debugPrint(
          '🟡 [SUBTOTAL_CALC] Subtotal changed from $_lastSubTotal to $calculatedSubTotal');
      _lastSubTotal = calculatedSubTotal;

      // Trigger discount calculations
      _checkAndApplyFirstOrderCoupon(calculatedSubTotal);
      _calculateHappyHourDiscount(calculatedSubTotal, vendorID);
      _checkNewUserPromoEligibility(); // Recalculate New User Promo
    }

    // Re-validate manual coupon if applied (check on every cart change, not just subtotal change)
    // This ensures minimum item requirement is checked when items are added/removed
    if (manualCoupon != null) {
      _revalidateManualCoupon(calculatedSubTotal);
    }

    // Recalculate totals after all dependencies are updated
    // Use post-frame callback to avoid calling setState during ongoing state updates
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && cartProducts.isNotEmpty) {
        _calculateAndUpdateTotals(cartProducts, lstExtras, vendorID);
      }
    });
  }

  // Pull-to-refresh handler
  Future<void> _onRefresh() async {
    _lastSubTotal = null;
    _lastTotalsSignature = null;
    _invalidateDeliveryCache();
    _useLiveLocationOnNextDeliveryCalc = true;
    _lastCartProducts = null;
    _lastVendorID = null;

    // If cart has items, recalculate all dependent data
    if (cartProducts.isNotEmpty && vendorID.isNotEmpty) {
      await _updateCartDependentData(cartProducts, vendorID);
    }

    // Refresh vendor model if vendorID exists
    if (vendorID.isNotEmpty) {
      await _fireStoreUtils.getVendorByVendorID(vendorID).then((value) {
        if (!mounted) return;
        setState(() {
          vendorModel = value;
        });
      });
    }

    // Small delay to ensure UI updates
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _checkCartRestaurantStatus() async {
    if (!mounted) return;
    try {
      final products = await cartDatabase.allCartProducts;
      if (products.isEmpty) {
        if (_closedVendorsInCart != null && _closedVendorsInCart!.isNotEmpty) {
          setState(() => _closedVendorsInCart = null);
        }
        return;
      }

      final uniqueVendorIds = products
          .map((p) => p.vendorID)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (uniqueVendorIds.isEmpty) return;

      final statusMap = await RestaurantStatusService
          .checkMultipleVendorsStatus(uniqueVendorIds);
      final closed = <Map<String, dynamic>>[];
      for (final vid in uniqueVendorIds) {
        final s = statusMap[vid];
        if (s == null) continue;
        if ((s['isOpen'] as bool? ?? false) != true) {
          closed.add({
            'vendorId': vid,
            'vendorName': (s['vendorName'] ?? 'Restaurant').toString(),
          });
        }
      }

      log('[CART_STATUS] Check: vendorIds=$uniqueVendorIds, closed=$closed');

      if (!mounted) return;
      setState(() {
        _closedVendorsInCart = closed.isEmpty ? null : closed;
      });
    } catch (e) {
      log('[CART_STATUS] Error: $e');
    }
  }

  Widget _buildClosedRestaurantBanner(BuildContext context) {
    final closed = _closedVendorsInCart ?? [];
    final names = closed
        .map((v) => v['vendorName'] as String? ?? 'Restaurant')
        .join(', ');
    return Material(
      color: Colors.orange.shade100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Some restaurants in your cart have closed: $names',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your order may be rejected. Remove items or proceed at your own risk.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await _removeClosedVendorItems();
                    },
                    child: const Text('Remove closed items'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _closedVendorsInCart = null);
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeClosedVendorItems() async {
    final closed = _closedVendorsInCart;
    if (closed == null || closed.isEmpty) return;
    final closedIds = closed
        .map((v) => v['vendorId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();

    final products = await cartDatabase.allCartProducts;
    for (final p in products) {
      if (closedIds.contains(p.vendorID)) {
        await cartDatabase.removeProduct(p.id);
      }
    }
    if (!mounted) return;
    setState(() => _closedVendorsInCart = null);
  }

  Future<bool> _onPopInvoked() async {
    final products = await cartDatabase.allCartProducts;
    if (products.isEmpty) return true;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete your order?'),
        content: const Text(
          'Your cart has items. Are you sure you want to leave?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_kShowCartLogs) debugPrint(
        '🔵 [CART_LIFECYCLE] build() called - Rebuild #${DateTime.now().millisecondsSinceEpoch}');
    cartDatabase = Provider.of<CartDatabase>(context, listen: true);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onPopInvoked();
        if (shouldExit && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: isDarkMode(context)
          ? const Color(DARK_COLOR)
          : const Color(0xffFFFFFF),
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Cart',
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
      body: StreamBuilder<List<CartProduct>>(
        stream: cartDatabase.watchProducts,
        initialData: const [],
        builder: (context, snapshot) {
          // Enhanced error handling for release builds
          if (snapshot.hasError) {
            print('❌ [CART_STREAM_ERROR] Stream error: ${snapshot.error}');
            print(
                '❌ [CART_STREAM_ERROR] Error type: ${snapshot.error.runtimeType}');
            if (snapshot.stackTrace != null) {
              print('❌ [CART_STREAM_ERROR] StackTrace: ${snapshot.stackTrace}');
            }
          }

          // Determine if cart is empty - if we have explicit empty data, show empty cart
          // This prevents flashing by immediately showing empty state when data is empty
          final bool shouldShowEmpty = snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isEmpty;

          final bool isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
                  (!snapshot.hasData || snapshot.data == null);

          // Enhanced debug logging (suppressed when _kShowCartLogs=false for FCM tracing)
          if (_kShowCartLogs) {
            print(
                '📊 [CART_STREAM] connectionState: ${snapshot.connectionState}');
            print('📊 [CART_STREAM] hasData: ${snapshot.hasData}');
            print('📊 [CART_STREAM] hasError: ${snapshot.hasError}');
            print('📊 [CART_STREAM] data is null: ${snapshot.data == null}');
            if (snapshot.data != null && snapshot.data is List) {
              print(
                  '📊 [CART_STREAM] data length: ${(snapshot.data as List).length}');
            }
            print('📊 [CART_STREAM] isLoading (shimmer condition): $isLoading');
            if (snapshot.connectionState == ConnectionState.active) {
              print('✅ [CART_STREAM] Stream is ACTIVE');
            } else if (snapshot.connectionState == ConnectionState.waiting) {
              print('⏳ [CART_STREAM] Stream is WAITING');
            } else if (snapshot.connectionState == ConnectionState.done) {
              print('⚠️ [CART_STREAM] Stream is DONE (unexpected)');
            }
          }

          // Trigger data processing via post-frame callback (not during build)
          // Skip processing if cart is empty to prevent unnecessary rebuilds
          if (!isLoading &&
              snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            final newCartData = snapshot.data!;
            final String newVendorID =
                newCartData.isNotEmpty ? newCartData.first.vendorID : "";
            if (_kShowCartLogs) {
              print(
                  '🟢 [CART_DATA] Cart data arrived - ${newCartData.length} items');
              print('🟡 [VENDOR_DATA] Current vendor ID: $newVendorID');
              print(
                  '⏱️ [CART_DATA] Timestamp: ${DateTime.now().toIso8601String()}');
            }

            // Schedule cart data processing and calculations after build completes
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              // Update cart products and quantity notifiers
              cartProducts = newCartData;
              _updateQuantityNotifiers(cartProducts);

              // Handle cart data changes (vendor detection, delivery calculation)
              _handleCartDataChange(cartProducts, newVendorID);

              // Calculate and update totals
              _calculateAndUpdateTotals(cartProducts, lstExtras, newVendorID);
            });
          } else if (!isLoading &&
              snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isEmpty) {
            // For empty cart, just update cartProducts without triggering calculations
            if (_kShowCartLogs) {
              print('🟢 [CART_DATA] Cart is empty - skipping calculations');
              print(
                  '⏱️ [CART_DATA] Empty cart timestamp: ${DateTime.now().toIso8601String()}');
            }
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (cartProducts.isNotEmpty) {
                cartProducts = [];
              }
            });
          }

          // Calculate vendorID for buildTotalRow (use empty string if no data)
          final String currentVendorID =
              cartProducts.isNotEmpty ? cartProducts.first.vendorID : "";

          if (shouldShowEmpty) {
            // Empty cart state - show full empty state
            return RefreshIndicator(
              onRefresh: _onRefresh,
              color: Color(COLOR_PRIMARY),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height,
                  width: MediaQuery.of(context).size.width * 1,
                  child: const _EmptyCartState(),
                ),
              ),
            );
          }

          return Column(
            children: [
              if (_closedVendorsInCart != null &&
                  _closedVendorsInCart!.isNotEmpty)
                _buildClosedRestaurantBanner(context),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: Color(COLOR_PRIMARY),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        EstimatedDeliveryTimeCard(
                          deliveryTime: _estimatedDeliveryTimeText,
                          isLoading: _isDeliveryDataLoading,
                          hasFailed: _deliveryCalcFailed,
                          onRetry: () =>
                              getDeliveyData(forceFresh: true),
                        ),
                        if (isLoading)
                          ShimmerWidgets.cartListShimmer(
                            isDarkMode: isDarkMode(context),
                          )
                        else
                          Builder(
                            builder: (context) {
                              // Cached to avoid recalculating on every
                              // item build
                              final entries =
                                  _buildCartEntries(cartProducts);
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const ClampingScrollPhysics(),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                              if (entry.isBundleHeader) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    left: 13,
                                    top: 16,
                                    right: 13,
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    'Bundle: ${entry.bundleName ?? "Value Meal"}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDarkMode(context)
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                );
                              }
                              final product = entry.product!;
                              return Container(
                                key: Key(product.id),
                                margin: const EdgeInsets.only(
                                    left: 13, top: 13, right: 13, bottom: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: isDarkMode(context)
                                          ? const Color(
                                              DarkContainerBorderColor)
                                          : Colors.grey.shade100,
                                      width: 1),
                                  color: isDarkMode(context)
                                      ? const Color(DarkContainerColor)
                                      : Colors.white,
                                  boxShadow: [
                                    isDarkMode(context)
                                        ? const BoxShadow()
                                        : BoxShadow(
                                            color: Colors.grey
                                                .withValues(alpha: 0.5),
                                            blurRadius: 5,
                                          ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    buildCartRow(product, lstExtras),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                        if (cartProducts.isNotEmpty && currentVendorID.isNotEmpty)
                          _CartCompleteYourMealSection(
                            cartProducts: cartProducts,
                            vendorID: currentVendorID,
                            cartDatabase: cartDatabase,
                          ),
                        buildTotalRow(
                            (snapshot.hasData &&
                                    snapshot.data != null &&
                                    !isLoading)
                                ? snapshot.data!
                                : (cartProducts.isNotEmpty
                                    ? cartProducts
                                    : const []),
                            lstExtras,
                            currentVendorID),
                        BannerAdWidget(
                            adUnitId: AdService.instance.bannerAdUnitId),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              AbsorbPointer(
                absorbing:
                    selctedOrderTypeValue == "Delivery" && !_isDeliveryReady,
                child: GestureDetector(
                  onTap: () async {
                    // Early return if delivery not ready
                    if (selctedOrderTypeValue == "Delivery" &&
                        !_isDeliveryReady) {
                      return;
                    }
                    
                    // Ensure user is logged in before proceeding
                    if (!await _ensureUserLoggedIn(context)) {
                      return;
                    }
                    
                    // Ensure user has first and last name before proceeding
                    if (MyAppState.currentUser != null) {
                      final user = MyAppState.currentUser!;
                      if ((user.firstName.isEmpty) || (user.lastName.isEmpty)) {
                        await showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(
                                "Profile Incomplete",
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              content: Text(
                                "Please complete your first and last name before checkout",
                                style: TextStyle(
                                  fontFamily: "Poppinsr",
                                  fontSize: 16,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: Text(
                                    "Cancel",
                                    style: TextStyle(
                                      fontFamily: "Poppinsm",
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    push(context, ProfileScreen(user: user));
                                  },
                                  child: Text(
                                    "Update Now",
                                    style: TextStyle(
                                      fontFamily: "Poppinsm",
                                      fontSize: 16,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        return;
                      }
                    }
                    final canProceed = await _ensurePhoneNumber(context);
                    if (!canProceed) {
                      return;
                    }
                    if (!hasDefaultAddress()) {
                      // Show dialog when no default address is found
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(
                              "No Default Address",
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            content: Text(
                              "Please add a default address first to proceed.",
                              style: TextStyle(
                                fontFamily: "Poppinsr",
                                fontSize: 16,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context); // Close the dialog
                                },
                                child: Text(
                                  "Cancel",
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context); // Close the dialog
                                  // Navigate to the DeliveryAddressScreen
                                  await Navigator.of(context)
                                      .push(MaterialPageRoute(
                                          builder: (context) =>
                                              DeliveryAddressScreen()))
                                      .then((value) async {
                                    // Refresh user data to get latest addresses
                                    if (MyAppState.currentUser != null) {
                                      var updatedUser =
                                          await FireStoreUtils.getCurrentUser(
                                              MyAppState.currentUser!.userID);
                                      if (updatedUser != null) {
                                        MyAppState.currentUser = updatedUser;
                                      }
                                    }

                                    if (value != null) {
                                      // Re-determine default address from updated shippingAddress list
                                      final resolvedDefaultAddress =
                                          MyAppState.resolveDefaultAddress(
                                              MyAppState.currentUser!
                                                  .shippingAddress);
                                      if (resolvedDefaultAddress != null) {
                                        MyAppState.selectedPosition =
                                            resolvedDefaultAddress;
                                        addressModel = resolvedDefaultAddress;
                                      } else {
                                        // Fallback to returned address if no default found
                                        MyAppState.selectedPosition = value;
                                        addressModel = value;
                                      }

                                      // Clear cache when address changes to force recalculation
                                      _invalidateDeliveryCache();
                                      // Reset delivery ready state when address changes
                                      setState(() {
                                        _isDeliveryReady = false;
                                      });
                                      // Immediate call for user-initiated address change
                                      await getDeliveyData();
                                    } else {
                                      // If no address was returned, still resolve default from updated list
                                      final resolvedDefaultAddress =
                                          MyAppState.resolveDefaultAddress(
                                              MyAppState.currentUser!
                                                  .shippingAddress);
                                      if (resolvedDefaultAddress != null) {
                                        MyAppState.selectedPosition =
                                            resolvedDefaultAddress;
                                        addressModel = resolvedDefaultAddress;
                                        // Clear cache and recalculate
                                        _invalidateDeliveryCache();
                                        setState(() {
                                          _isDeliveryReady = false;
                                        });
                                        await getDeliveyData();
                                      }
                                    }
                                  });
                                },
                                child: Text(
                                  "Add Address",
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 16,
                                    color: Color(COLOR_PRIMARY),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                      return;
                    }

                    txt.clear();

                    // Get selected discount amount (single-discount policy)
                    // If manual coupon is applied, ignore promo discounts
                    double promoDiscountAmount = 0.0;
                    String? promoCouponCode;
                    String? promoCouponId;
                    String? appliedDiscountType;

                    if (manualCoupon != null) {
                      // Manual coupon is applied, no promo discounts
                      promoDiscountAmount = 0.0;
                      promoCouponCode = null;
                      promoCouponId = null;
                      appliedDiscountType = null;
                    } else if (selectedDiscount != null) {
                      promoDiscountAmount =
                          selectedDiscount!['amount'] as double;
                      promoCouponCode =
                          selectedDiscount!['couponCode'] as String?;
                      promoCouponId = selectedDiscount!['couponId'] as String?;
                      appliedDiscountType = selectedDiscount!['type'] as String;
                    } else {
                      appliedDiscountType = null;
                    }

                    // Manual coupon data
                    String? manualCouponCode;
                    String? manualCouponId;
                    double? manualCouponDiscount;
                    String? manualCouponImage;

                    if (manualCoupon != null) {
                      manualCouponCode = manualCoupon!.offerCode;
                      manualCouponId = manualCoupon!.offerId;
                      manualCouponDiscount = manualCouponDiscountAmount;
                      manualCouponImage = manualCoupon!.imageOffer;
                    }

                    // Build specialDiscountMap with only selected discount info
                    Map<String, dynamic> specialDiscountMap = {
                      'special_discount': specialDiscountAmount,
                      'special_discount_label': specialDiscount,
                      'specialType': specialType,
                    };

                    // Add selected promo discount info if applicable
                    if (selectedDiscount != null) {
                      specialDiscountMap['applied_discount_type'] =
                          appliedDiscountType;
                      specialDiscountMap['applied_discount_amount'] =
                          promoDiscountAmount;
                      if (selectedDiscount!['type'] == 'happy_hour' &&
                          activeHappyHourConfig != null) {
                        specialDiscountMap['happy_hour_discount'] =
                            promoDiscountAmount;
                        specialDiscountMap['happy_hour_config_id'] =
                            activeHappyHourConfig!.id;
                        specialDiscountMap['happy_hour_name'] =
                            activeHappyHourConfig!.name;
                      }
                    }

                    // Generate audit note for discount selection
                    String auditNote = _generateDiscountAuditNote();

                    if (selctedOrderTypeValue == "Delivery") {
                      // Force fresh distance calculation at checkout for accuracy
                      _invalidateDeliveryCache();
                      await getDeliveyData(forceFresh: true);

                      if (!mounted) return;
                      push(
                        context,
                        PaymentScreen(
                          total: grandtotalNotifier.value,
                          products: cartProducts,
                          discount: discountAmount + promoDiscountAmount,
                          couponCode: manualCouponCode ?? promoCouponCode,
                          notes: noteController.text,
                          couponId: manualCouponId ?? promoCouponId,
                          extraAddons: commaSepratedAddOns,
                          tipValue: tipValue.toString(),
                          takeAway: selctedOrderTypeValue == "Delivery"
                              ? false
                              : true,
                          deliveryCharge: deliveryCharges,
                          taxModel: taxList,
                          specialDiscountMap: specialDiscountMap,
                          scheduleTime: scheduleTime,
                          addressModel: addressModel,
                          // Referral system parameters
                          isReferralPath: isReferralPath,
                          referralAuditNote: auditNote,
                          // Manual coupon parameters
                          manualCouponCode: manualCouponCode,
                          manualCouponId: manualCouponId,
                          manualCouponDiscountAmount: manualCouponDiscount,
                          manualCouponImage: manualCouponImage,
                          // Referral wallet parameter
                          referralWalletAmountUsed:
                              referralWalletAmountToUse > 0
                                  ? referralWalletAmountToUse
                                  : null,
                          giftCardAmountUsed:
                              giftCardAmountToUse > 0 ? giftCardAmountToUse : null,
                          giftCardBreakdown:
                              giftCardBreakdown.isNotEmpty ? giftCardBreakdown : null,
                          loyaltyFreeDeliveryAmount:
                              loyaltyFreeDeliveryAmount > 0
                                  ? loyaltyFreeDeliveryAmount
                                  : null,
                          loyaltyFreeDeliveryRewardId: loyaltyFreeDeliveryRewardId,
                          loyaltyFreeDeliveryCycle: loyaltyFreeDeliveryCycle,
                        ),
                      );
                    } else {
                      push(
                        context,
                        PaymentScreen(
                          total: grandtotalNotifier.value,
                          discount: discountAmount + promoDiscountAmount,
                          couponCode: manualCouponCode ?? promoCouponCode,
                          couponId: manualCouponId ?? promoCouponId,
                          notes: noteController.text,
                          products: cartProducts,
                          extraAddons: commaSepratedAddOns,
                          tipValue: "0",
                          takeAway: true,
                          deliveryCharge: "0",
                          taxModel: taxList,
                          specialDiscountMap: specialDiscountMap,
                          scheduleTime: scheduleTime,
                          addressModel: addressModel,
                          // Referral system parameters
                          isReferralPath: isReferralPath,
                          referralAuditNote: auditNote,
                          // Manual coupon parameters
                          manualCouponCode: manualCouponCode,
                          manualCouponId: manualCouponId,
                          manualCouponDiscountAmount: manualCouponDiscount,
                          manualCouponImage: manualCouponImage,
                          referralWalletAmountUsed:
                              referralWalletAmountToUse > 0
                                  ? referralWalletAmountToUse
                                  : null,
                          giftCardAmountUsed:
                              giftCardAmountToUse > 0 ? giftCardAmountToUse : null,
                          giftCardBreakdown:
                              giftCardBreakdown.isNotEmpty ? giftCardBreakdown : null,
                          loyaltyFreeDeliveryAmount:
                              loyaltyFreeDeliveryAmount > 0
                                  ? loyaltyFreeDeliveryAmount
                                  : null,
                          loyaltyFreeDeliveryRewardId: loyaltyFreeDeliveryRewardId,
                          loyaltyFreeDeliveryCycle: loyaltyFreeDeliveryCycle,
                        ),
                      );
                    }
                  },
                  child: ValueListenableBuilder<double>(
                    valueListenable: grandtotalNotifier,
                    builder: (context, grandtotal, child) {
                      return _CheckoutButton(
                        grandtotal: grandtotal,
                        isEnabled: selctedOrderTypeValue == "Delivery"
                            ? _isDeliveryReady
                            : true,
                      );
                    },
                  ),
                ),
              )
            ],
          );
        },
      ),
    ),
    );
  }

  static List<_CartEntry> _buildCartEntries(List<CartProduct> products) {
    final List<_CartEntry> entries = [];
    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final bid = p.bundleId;
      final bname = p.bundleName;
      if (bid != null &&
          bid.isNotEmpty &&
          (i == 0 || products[i - 1].bundleId != bid)) {
        entries.add(_CartEntry.bundleHeader(bname ?? 'Bundle'));
      }
      entries.add(_CartEntry.item(p));
    }
    return entries;
  }

  buildCartRow(CartProduct cartProduct, List<AddAddonsDemo> addons) {
    var quen = cartProduct.quantity;
    final variantInfo = cartProduct.parseVariantInfo();
    final priceTotalValue = cartProduct.computeLineTotal();
    final addOnVal = cartProduct.parseExtrasAsList();

    return InkWell(
      onTap: () async {
        // Use cached vendor if available, otherwise fetch
        VendorModel? vendor;
        if (_vendorCache != null &&
            _vendorCache!.containsKey(cartProduct.vendorID)) {
          vendor = _vendorCache![cartProduct.vendorID];
        } else {
          vendor =
              await _fireStoreUtils.getVendorByVendorID(cartProduct.vendorID);
          _vendorCache ??= {};
          _vendorCache![cartProduct.vendorID] = vendor;
        }

        if (vendor != null && mounted) {
          push(
            context,
            NewVendorProductsScreen(vendorModel: vendor),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                      height: 80,
                      width: 80,
                      imageUrl: getImageVAlidUrl(cartProduct.photo),
                      imageBuilder: (context, imageProvider) => Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            )),
                          ),
                      errorWidget: (context, url, error) => ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CachedNetworkImage(
                            imageUrl: AppGlobal.placeHolderImage!,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            fit: BoxFit.cover,
                          ))),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cartProduct.name,
                        style: const TextStyle(
                            fontSize: 18, fontFamily: "Poppinsm"),
                      ),
                      Text(
                        amountShow(amount: priceTotalValue.toString()),
                        style: TextStyle(
                            fontSize: 20, color: Color(COLOR_PRIMARY)),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (quen != 0) {
                          quen--;
                          _getQuantityNotifier(cartProduct.id, quen).value =
                              quen;
                          _scheduleQuantityUpdate(cartProduct, quen);
                        }
                      },
                      child: Image(
                        image: const AssetImage("assets/images/minus.png"),
                        color: Color(COLOR_PRIMARY),
                        height: 30,
                      ),
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _getQuantityNotifier(
                        cartProduct.id,
                        cartProduct.quantity,
                      ),
                      builder: (context, quantity, child) {
                        return Text(
                          '$quantity',
                          style: const TextStyle(fontSize: 20),
                        );
                      },
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    GestureDetector(
                      onTap: () async {
                        // Fetch productModel on demand (not during build)
                        final String productId =
                            cartProduct.id.split('~').first;
                        ProductModel? productModel;

                        // Check cache first
                        if (_productCache != null &&
                            _productCache!.containsKey(productId)) {
                          productModel = _productCache![productId];
                        } else {
                          // Fetch from Firestore if not in cache
                          productModel =
                              await FireStoreUtils().getProductByID(productId);
                          // Cache it for future use
                          _productCache ??= {};
                          _productCache![productId] = productModel;
                        }

                        if (productModel == null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Unable to load product information"),
                          ));
                          return;
                        }

                        if (productModel.itemAttributes != null) {
                          if (productModel.itemAttributes!.variants!
                              .where((element) =>
                                  element.variantSku == variantInfo!.variantSku)
                              .isNotEmpty) {
                            if (int.parse(productModel.itemAttributes!.variants!
                                        .where((element) =>
                                            element.variantSku ==
                                            variantInfo!.variantSku)
                                        .first
                                        .variantQuantity
                                        .toString()) >
                                    quen ||
                                int.parse(productModel.itemAttributes!.variants!
                                        .where((element) =>
                                            element.variantSku ==
                                            variantInfo!.variantSku)
                                        .first
                                        .variantQuantity
                                        .toString()) ==
                                    -1) {
                              quen++;
                              _getQuantityNotifier(cartProduct.id, quen).value =
                                  quen;
                              _scheduleQuantityUpdate(cartProduct, quen);
                            } else {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text("Food out of stock"),
                              ));
                            }
                          } else {
                            if (productModel.quantity > quen ||
                                productModel.quantity == -1) {
                              quen++;
                              _getQuantityNotifier(cartProduct.id, quen).value =
                                  quen;
                              _scheduleQuantityUpdate(cartProduct, quen);
                            } else {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text("Food out of stock"),
                              ));
                            }
                          }
                        } else {
                          if (productModel.quantity > quen ||
                              productModel.quantity == -1) {
                            quen++;
                            _getQuantityNotifier(cartProduct.id, quen).value =
                                quen;
                            _scheduleQuantityUpdate(cartProduct, quen);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text("Food out of stock"),
                            ));
                          }
                        }
                      },
                      child: Image(
                        image: const AssetImage("assets/images/plus.png"),
                        color: Color(COLOR_PRIMARY),
                        height: 30,
                      ),
                    )
                  ],
                )
              ],
            ),

            (variantInfo != null &&
                    variantInfo.variantOptions != null &&
                    variantInfo.variantOptions!.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 10),
                    child: Wrap(
                      spacing: 6.0,
                      runSpacing: 6.0,
                      children:
                          variantInfo.variantOptions!.entries.toList().asMap().entries
                              .map((e) => _buildChip(
                                    "${e.value.key} : ${e.value.value}",
                                    e.key,
                                  ))
                              .toList(),
                    ),
                  )
                : const SizedBox.shrink(),

            SizedBox(
              height: addOnVal.isEmpty ? 0 : 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: ListView.builder(
                    itemCount: addOnVal.length,
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      return Text(
                        "${addOnVal[index].toString().replaceAll("\"", "")} ${(index == addOnVal.length - 1) ? "" : ","}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                      );
                    }),
              ),
            ),

            // cartProduct.variant_info != null?ListView.builder(

            //   itemCount: variantInfo.variantOptions!.length,

            //   shrinkWrap: true,

            //   itemBuilder: (context, index) {

            //     String key = cartProduct.variant_info.variantOptions!.keys.elementAt(index);

            //     return Padding(

            //       padding: const EdgeInsets.symmetric(vertical: 2),

            //       child: Row(

            //         children: [

            //           Text("$key : "),

            //           Text("${cartProduct.variant_info.variantOptions![key]}"),

            //         ],

            //       ),

            //     );

            //   },

            // ):Container(),
          ],
        ),
      ),
    );
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();

    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  Widget buildTotalRow(
      List<CartProduct> data, List<AddAddonsDemo> lstExtras, String vendorID) {
    if (_kShowCartLogs) {
      print('🟢 [PURE_BUILD] buildTotalRow() rendering UI - NO state mutations');
      print(
          '🟢 [PURE_BUILD] Rendering with subTotal: $subTotal, grandTotal: ${grandtotalNotifier.value}');
    }
    var _font = 16.00;

    // Pure build method - only renders UI based on existing state
    // All calculations are done in _calculateAndUpdateTotals()

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        //Container(
        //  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        //  margin:
        //      const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 5),
        //  decoration: BoxDecoration(
        //    borderRadius: BorderRadius.circular(10),
        //    border: Border.all(
        //        color: isDarkMode(context)
        //            ? const Color(DarkContainerBorderColor)
        //            : Colors.grey.shade100,
        //        width: 1),
        //    color: isDarkMode(context)
        //        ? const Color(DarkContainerColor)
        //        : Colors.white,
        //    boxShadow: [
        //      isDarkMode(context)
        //          ? const BoxShadow()
        //          : BoxShadow(
        //              color: Colors.grey.withOpacity(0.5),
        //              blurRadius: 5,
        //            ),
        //    ],
        //  ),
        //  //child: Row(
        //  //  mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //  //  children: [
        //  //    //Row(children: [
        //  //    //  const Image(
        //  //    //    image: AssetImage("assets/images/reedem.png"),
        //  //    //    width: 50,
        //  //    //  ),
        //  //    //  Padding(
        //  //    //    padding: const EdgeInsets.only(left: 10),
        //  //    //    child: Column(
        //  //    //      children: [
        //  //    //        Text(
        //  //    //          "Redeem Coupon",
        //  //    //          style: const TextStyle(
        //  //    //            fontFamily: "Poppinsm",
        //  //    //          ),
        //  //    //        ),
        //  //    //        Text("Add coupon code",
        //  //    //            style: const TextStyle(
        //  //    //              fontFamily: "Poppinsr",
        //  //    //            )),
        //  //    //      ],
        //  //    //    ),
        //  //    //  )
        //  //    //]),
        //  //    //GestureDetector(
        //  //    //  onTap: () {
        //  //    //    showModalBottomSheet(
        //  //    //        isScrollControlled: true,
        //  //    //        isDismissible: true,
        //  //    //        context: context,
        //  //    //        backgroundColor: Colors.transparent,
        //  //    //        enableDrag: true,
        //  //    //        builder: (BuildContext context) => sheet());
        //  //    //  },
        //  //    //  child: const Image(
        //  //    //      image: AssetImage("assets/images/add.png"), width: 40),
        //  //    //)
        //  //  ],
        //  //))
        //),
        ValueListenableBuilder<Timestamp?>(
          valueListenable: scheduleTimeNotifier,
          builder: (context, scheduleTimeValue, _) {
            return _ScheduleOrderCard(
              scheduleTime: scheduleTimeValue,
              onTap: () {
                BottomPicker.dateTime(
                  pickerTitle: Text('Select Date & Time',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)), // Wrap title in a Text widget

                  onSubmit: (index) {
                    DateTime dateAndTime = index;
                    scheduleTime = Timestamp.fromDate(dateAndTime);
                  },

                  minDateTime: DateTime.now(),
                ).show(context);
              },
              isDarkMode: isDarkMode(context),
            );
          },
        ),
        selctedOrderTypeValue == "Delivery"
            ? _DeliveryAddressCard(
                addressModel: addressModel,
                onChangeTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (context) => DeliveryAddressScreen()))
                      .then((value) async {
                    // Refresh user data to get latest addresses
                    if (MyAppState.currentUser != null) {
                      var updatedUser = await FireStoreUtils.getCurrentUser(
                          MyAppState.currentUser!.userID);
                      if (updatedUser != null) {
                        MyAppState.currentUser = updatedUser;
                      }
                    }

                    if (value != null) {
                      // Re-determine default address from updated shippingAddress list
                      final resolvedDefaultAddress =
                          MyAppState.resolveDefaultAddress(
                              MyAppState.currentUser!.shippingAddress);
                      if (resolvedDefaultAddress != null) {
                        MyAppState.selectedPosition = resolvedDefaultAddress;
                        addressModel = resolvedDefaultAddress;
                      } else {
                        // Fallback to returned address if no default found
                        MyAppState.selectedPosition = value;
                        addressModel = value;
                      }

                      // Clear cache when address changes to force recalculation
                      _invalidateDeliveryCache();
                      // Reset delivery ready state when address changes
                      setState(() {
                        _isDeliveryReady = false;
                      });
                      // Immediate call for user-initiated address change
                      await getDeliveyData();
                    } else {
                      // If no address was returned, still resolve default from updated list
                      final resolvedDefaultAddress =
                          MyAppState.resolveDefaultAddress(
                              MyAppState.currentUser!.shippingAddress);
                      if (resolvedDefaultAddress != null) {
                        MyAppState.selectedPosition = resolvedDefaultAddress;
                        addressModel = resolvedDefaultAddress;
                        // Clear cache and recalculate
                        _invalidateDeliveryCache();
                        setState(() {
                          _isDeliveryReady = false;
                        });
                        await getDeliveyData();
                      }
                    }
                  });
                },
                isDarkMode: isDarkMode(context),
              )
            : const SizedBox(),
        // Manual Coupon Input Section - Moved below delivery address card
        _ManualCouponSection(
          manualCoupon: manualCoupon,
          manualCouponDiscountAmount: manualCouponDiscountAmount,
          manualCouponError: manualCouponError,
          isManualCouponValidating: isManualCouponValidating,
          manualCouponCodeController: manualCouponCodeController,
          onApplyCoupon: _validateAndApplyManualCoupon,
          onRemoveCoupon: _removeManualCoupon,
          onBrowsePromos: _openVoucherScreen,
          isDarkMode: isDarkMode(context),
          fontSize: _font,
        ),
        _DeliveryOptionCard(
          selectedOrderType: selctedOrderTypeValue!,
          deliveryCharges: deliveryCharges,
          isDeliveryReady: _isDeliveryReady,
          isDarkMode: isDarkMode(context),
          fontSize: _font,
        ),
        Container(
          margin:
              const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDarkMode(context)
                    ? const Color(DarkContainerBorderColor)
                    : Colors.grey.shade100,
                width: 1),
            color: isDarkMode(context)
                ? const Color(DarkContainerColor)
                : Colors.white,
            boxShadow: [
              isDarkMode(context)
                  ? const BoxShadow()
                  : BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.5),
                      blurRadius: 5,
                    ),
            ],
          ),
          child: Column(
            children: [
              const Divider(
                color: Color(0xffE2E8F0),
                height: 0.1,
              ),

              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Subtotal",
                        style:
                            TextStyle(fontFamily: "Poppinsm", fontSize: _font),
                      ),
                      Text(
                        amountShow(amount: subTotal.toString()),
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? const Color(0xffFFFFFF)
                                : const Color(0xff333333),
                            fontSize: _font),
                      ),
                    ],
                  )),

              const Divider(
                thickness: 1,
              ),

              // Gift Card Section (above Referral Wallet per payment order)
              if (activeGiftCards.isNotEmpty &&
                  (giftCardConfig?.enabled ?? true))
                _GiftCardSection(
                  activeGiftCards: activeGiftCards,
                  giftCardAmountToUse: giftCardAmountToUse,
                  isGiftCardApplied: isGiftCardApplied,
                  onApply: (cardId, amount) {
                    setState(() {
                      giftCardBreakdown = [
                        {'cardId': cardId, 'amount': amount}
                      ];
                      isGiftCardApplied = true;
                    });
                    if (cartProducts.isNotEmpty) {
                      _calculateAndUpdateTotals(
                          cartProducts, lstExtras, vendorID);
                    }
                  },
                  onRemove: () {
                    setState(() {
                      giftCardBreakdown = [];
                      isGiftCardApplied = false;
                    });
                    if (cartProducts.isNotEmpty) {
                      _calculateAndUpdateTotals(
                          cartProducts, lstExtras, vendorID);
                    }
                  },
                  isDarkMode: isDarkMode(context),
                ),

              // Referral Wallet Section
              if (referralWalletAmountAvailable > 0 &&
                  !isNewUserPromoEligible &&
                  MyAppState.currentUser!.hasCompletedFirstOrder)
                _ReferralWalletCard(
                  referralWalletAmountAvailable: referralWalletAmountAvailable,
                  referralWalletAmountToUse: referralWalletAmountToUse,
                  isReferralWalletApplied: isReferralWalletApplied,
                  onApply: () {
                    // TODO: large rebuild
                    setState(() {
                      isReferralWalletApplied = true;
                    });
                    // Recalculate totals after referral wallet applied
                    if (cartProducts.isNotEmpty) {
                      _calculateAndUpdateTotals(
                          cartProducts, lstExtras, vendorID);
                    }
                  },
                  onRemove: () {
                    // TODO: large rebuild
                    setState(() {
                      isReferralWalletApplied = false;
                      referralWalletAmountToUse = 0.0;
                    });
                    // Recalculate totals after referral wallet removed
                    if (cartProducts.isNotEmpty) {
                      _calculateAndUpdateTotals(
                          cartProducts, lstExtras, vendorID);
                    }
                  },
                  isDarkMode: isDarkMode(context),
                ),

              // Single-discount policy informational message
              ValueListenableBuilder<bool>(
                valueListenable: isReferralPathNotifier,
                builder: (context, isReferralPathValue, _) {
                  if (selectedDiscount != null ||
                      isReferralPathValue ||
                      manualCoupon != null) {
                    return _DiscountInfoMessage(
                      message: manualCoupon != null
                          ? "Manual coupon applied → promo discounts disabled (one coupon per order)"
                          : selectedDiscount != null
                              ? "Best available discount applied (promos are not stackable)"
                              : "Referral active → promos disabled (mutually exclusive)",
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Selected promo discount display (single-discount policy)
              if (selectedDiscount != null)
                _SelectedDiscountRow(
                  label: selectedDiscount!['label'] as String,
                  amount: selectedDiscount!['amount'] as double,
                  discountType: selectedDiscount!['type'] as String,
                  isDarkMode: isDarkMode(context),
                  fontSize: _font,
                ),

              // Happy Hour minimum item requirement message
              if (activeHappyHourConfig != null &&
                  happyHourDiscount == 0.0 &&
                  happyHourItemsNeeded != null &&
                  happyHourItemsNeeded! > 0)
                _HappyHourInfoMessage(
                  itemsNeeded: happyHourItemsNeeded!,
                  happyHourName: activeHappyHourConfig!.name,
                ),

              // Manual coupon discount display
              if (manualCoupon != null && discountAmount > 0)
                _ManualCouponDiscountRow(
                  couponCode: manualCoupon!.offerCode ?? '',
                  discountAmount: discountAmount,
                  fontSize: _font,
                ),

              // Vendor special discount (not part of promo stacking policy)
              Visibility(
                visible: vendorModel != null
                    ? vendorModel!.specialDiscountEnable
                    : false,
                child: _SpecialDiscountRow(
                  specialDiscount: specialDiscount,
                  specialType: specialType,
                  specialDiscountAmount: specialDiscountAmount,
                  currencySymbol: currencyModel!.symbol,
                  fontSize: _font,
                ),
              ),

              selctedOrderTypeValue == "Delivery"
                  ? (widget.fromContainer &&
                          !isDeliverFound &&
                          addressModel.location!.latitude == 0.0 &&
                          addressModel.location!.longitude == 0)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 5),
                          child: Text("Delivery Charge Will Applied Next Step.",
                              style: TextStyle(
                                  fontFamily: "Poppinsm", fontSize: _font)),
                        )
                      : _DeliveryChargesRow(
                          deliveryCharges: deliveryCharges,
                          distanceKm: _cachedDistanceKm,
                          isDeliveryReady: _isDeliveryReady,
                          isDarkMode: isDarkMode(context),
                          fontSize: _font,
                        )
                  : Container(),

              ListView.builder(
                itemCount: taxList!.length,
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  TaxModel taxModel = taxList![index];

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "${taxModel.title.toString()} (${taxModel.type == "fix" ? amountShow(amount: taxModel.tax) : "${taxModel.tax}%"})",
                                style: TextStyle(
                                    fontFamily: "Poppinsm", fontSize: _font),
                              ),
                            ),
                            Text(
                              amountShow(
                                  amount: calculateTax(
                                          amount: (double.parse(
                                                      subTotal.toString()) -
                                                  discountAmount -
                                                  specialDiscountAmount -
                                                  firstOrderCouponDiscount)
                                              .toString(),
                                          taxModel: taxModel)
                                      .toString()),
                              style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  color: isDarkMode(context)
                                      ? const Color(0xffFFFFFF)
                                      : const Color(0xff333333),
                                  fontSize: _font),
                            ),
                          ],
                        ),
                      ),
                      const Divider(
                        thickness: 1,
                      ),
                    ],
                  );
                },
              ),

              // taxModel != null

              //     ? Container(

              //         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),

              //         child: Row(

              //           mainAxisAlignment: MainAxisAlignment.spaceBetween,

              //           children: [

              //             Text(

              //               ((taxModel!.label!.isNotEmpty) ? taxModel!.label.toString() : "Tax") + " ${(taxModel!.type == "fix") ? "" : "(${taxModel!.tax} %)"}",

              //               style: TextStyle(fontFamily: "Poppinsm", fontSize: _font),

              //             ),

              //             Text(

              //               amountShow(amount: getTaxValue(taxModel, subTotal - discountVal - specialDiscountAmount).toString()),

              //               style: TextStyle(fontFamily: "Poppinsm", color: isDarkMode(context) ? const Color(0xffFFFFFF) : const Color(0xff333333), fontSize: _font),

              //             ),

              //           ],

              //         ))

              //     : Container(),

              Visibility(
                  visible: ((tipValue) > 0),
                  child: Column(
                    children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Sadaqa amount",
                                style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    color: isDarkMode(context)
                                        ? const Color(0xffFFFFFF)
                                        : const Color(0xff333333),
                                    fontSize: _font),
                              ),
                              Text(
                                '${amountShow(amount: tipValue.toString())}',
                                style: TextStyle(
                                    color: isDarkMode(context)
                                        ? const Color(0xffFFFFFF)
                                        : const Color(0xff333333),
                                    fontSize: _font),
                              ),
                            ],
                          )),
                      const Divider(
                        thickness: 1,
                      ),
                    ],
                  )),

              ValueListenableBuilder<double>(
                valueListenable: grandtotalNotifier,
                builder: (context, grandtotal, child) {
                  return _OrderTotalRow(
                    grandtotal: grandtotal,
                    isDarkMode: isDarkMode(context),
                    fontSize: _font,
                  );
                },
              ),

              // Referral path indicator
              ValueListenableBuilder<bool>(
                valueListenable: isReferralPathNotifier,
                builder: (context, isReferralPath, _) {
                  if (isReferralPath) {
                    return const _ReferralPathIndicator();
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        selctedOrderTypeValue == "Delivery"
            ? _SadaqaSection(
                tipValue: tipValue,
                isTipSelected: isTipSelected,
                isTipSelected1: isTipSelected1,
                isTipSelected2: isTipSelected2,
                isTipSelected3: isTipSelected3,
                onTip10Tap: () {
                  // TODO: large rebuild
                  setState(() {
                    if (isTipSelected) {
                      isTipSelected = false;
                      tipValue = 0;
                      checkTipSelection(context);
                    } else {
                      tipValue = 10;
                      isTipSelected = true;
                    }
                    isTipSelected1 = false;
                    isTipSelected2 = false;
                    isTipSelected3 = false;
                  });
                  // Recalculate totals after tip change
                  if (cartProducts.isNotEmpty) {
                    _calculateAndUpdateTotals(
                        cartProducts, lstExtras, vendorID);
                  }
                },
                onTip20Tap: () {
                  // TODO: large rebuild
                  setState(() {
                    if (isTipSelected1) {
                      isTipSelected1 = false;
                      tipValue = 0;
                    } else {
                      tipValue = 20;
                      isTipSelected1 = true;
                    }
                    isTipSelected = false;
                    isTipSelected2 = false;
                    isTipSelected3 = false;
                  });
                  // Recalculate totals after tip change
                  if (cartProducts.isNotEmpty) {
                    _calculateAndUpdateTotals(
                        cartProducts, lstExtras, vendorID);
                  }
                },
                onTip30Tap: () {
                  // TODO: large rebuild
                  setState(() {
                    if (isTipSelected2) {
                      isTipSelected2 = false;
                      tipValue = 0;
                    } else {
                      tipValue = 30;
                      isTipSelected2 = true;
                    }
                    isTipSelected = false;
                    isTipSelected1 = false;
                    isTipSelected3 = false;
                  });
                  // Recalculate totals after tip change
                  if (cartProducts.isNotEmpty) {
                    _calculateAndUpdateTotals(
                        cartProducts, lstExtras, vendorID);
                  }
                },
                onOtherTap: () {
                  if (isTipSelected3) {
                    // TODO: large rebuild
                    setState(() {
                      if (isTipSelected3) {
                        isTipSelected3 = false;
                        tipValue = 0;
                      }
                      isTipSelected = false;
                      isTipSelected1 = false;
                      isTipSelected2 = false;
                    });
                    // Recalculate totals after tip change
                    if (cartProducts.isNotEmpty) {
                      _calculateAndUpdateTotals(
                          cartProducts, lstExtras, vendorID);
                    }
                  } else {
                    _displayDialog(context);
                  }
                },
                isDarkMode: isDarkMode(context),
              )
            : Container(),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDarkMode(context)
                      ? const Color(DarkContainerBorderColor)
                      : Colors.grey.shade100,
                  width: 1),
              color: isDarkMode(context)
                  ? const Color(DarkContainerColor)
                  : Colors.white,
              boxShadow: [
                isDarkMode(context)
                    ? const BoxShadow()
                    : BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        blurRadius: 5,
                      ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Remarks",
                      style: TextStyle(
                        fontFamily: "Poppinsm",
                      ),
                    ),
                    const Text("Write remarks for restaurant",
                        style: TextStyle(
                          fontFamily: "Poppinsr",
                        )),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                        isScrollControlled: true,
                        isDismissible: true,
                        context: context,
                        backgroundColor: Colors.transparent,
                        enableDrag: true,
                        builder: (BuildContext context) => noteSheet());
                  },
                  child: const Image(
                      image: AssetImage("assets/images/add.png"), width: 40),
                )
              ],
            )),
      ],
    );
  }

  void checkTipSelection(BuildContext context) {
    if (!isTipSelected) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              "Your Sadaqa is important",
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
            content: Text(
              "Giving Sadaqa to your delivery partner is a noble act. Consider helping them with a small gesture of kindness.",
              style: TextStyle(
                fontFamily: "Poppinsr",
                fontSize: 16,
                color:
                    isDarkMode(context) ? Colors.grey.shade300 : Colors.black,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text(
                  "Close",
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 16,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ),
            ],
            backgroundColor:
                isDarkMode(context) ? const Color(DARK_COLOR) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          );
        },
      );
    }
  }

  // showSheet(CartProduct cartProduct) async {

  //   bool? shouldUpdate = await showModalBottomSheet(

  //     isDismissible: true,

  //     context: context,

  //     backgroundColor: Colors.transparent,

  //     builder: (context) => CartOptionsSheet(

  //       cartProduct: cartProduct,

  //     ),

  //   );

  //   if (shouldUpdate != null) {

  //     cartFuture = cartDatabase.allCartProducts;

  //     setState(() {});

  //   }

  // }

  addtocard(CartProduct cartProduct, qun) async {
    final stopwatch = Stopwatch()..start();
    await cartDatabase.updateProduct(CartProduct(
        id: cartProduct.id,
        category_id: cartProduct.category_id,
        name: cartProduct.name,
        photo: cartProduct.photo,
        price: cartProduct.price,
        vendorID: cartProduct.vendorID,
        quantity: qun,
        extras_price: cartProduct.extras_price,
        extras: cartProduct.extras,
        discountPrice: cartProduct.discountPrice ?? "",
        variant_info: cartProduct.variant_info,
        bundleId: cartProduct.bundleId,
        bundleName: cartProduct.bundleName,
        addonPromoId: cartProduct.addonPromoId,
        addonPromoName: cartProduct.addonPromoName,
        addedAt: cartProduct.addedAt));
    stopwatch.stop();
    PerformanceLogger.logUpdateQuantity(stopwatch.elapsed);
  }

  removetocard(CartProduct cartProduct, qun) async {
    final stopwatch = Stopwatch()..start();
    if (qun >= 1) {
      await cartDatabase.updateProduct(CartProduct(
          id: cartProduct.id,
          category_id: cartProduct.category_id,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          vendorID: cartProduct.vendorID,
          quantity: qun,
          extras_price: cartProduct.extras_price,
          extras: cartProduct.extras,
          discountPrice: cartProduct.discountPrice ?? "",
          variant_info: cartProduct.variant_info,
          bundleId: cartProduct.bundleId,
          bundleName: cartProduct.bundleName,
          addonPromoId: cartProduct.addonPromoId,
        addonPromoName: cartProduct.addonPromoName,
        addedAt: cartProduct.addedAt));
    } else {
      await cartDatabase.removeProduct(cartProduct.id);
    }
    stopwatch.stop();
    if (qun >= 1) {
      PerformanceLogger.logUpdateQuantity(stopwatch.elapsed);
    } else {
      PerformanceLogger.logRemoveFromCart(stopwatch.elapsed);
    }
  }

  OfferModel? couponModel;

  sheet() {
    return Container(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height / 4.3,
            left: 25,
            right: 25),
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(style: BorderStyle.none)),
        child: FutureBuilder<List<OfferModel>>(
            future: coupon,
            initialData: const [],
            builder: (context, snapshot) {
              snapshot = snapshot;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return ShimmerWidgets.couponSectionShimmer(
                  isDarkMode: isDarkMode(context),
                );
              }

              // coupon = snapshot.data as Future<List<CouponModel>> ;

              return Column(children: [
                InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 45,

                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 0.3),
                          color: Colors.transparent,
                          shape: BoxShape.circle),

                      // radius: 20,

                      child: const Center(
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    )),

                const SizedBox(
                  height: 25,
                ),

                Expanded(
                    child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isDarkMode(context)
                            ? const Color(DarkContainerBorderColor)
                            : Colors.grey.shade100,
                        width: 1),
                    color: isDarkMode(context)
                        ? const Color(DarkContainerColor)
                        : Colors.white,
                    boxShadow: [
                      isDarkMode(context)
                          ? const BoxShadow()
                          : BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              blurRadius: 5,
                            ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                            padding: const EdgeInsets.only(top: 30),
                            child: const Image(
                              image:
                                  AssetImage('assets/images/redeem_coupon.png'),
                              width: 100,
                            )),
                        Container(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              'Redeem Your Coupons',
                              style: const TextStyle(
                                  fontFamily: 'Poppinssb', fontSize: 16),
                            )),
                        Container(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              "Voucher or Coupon code",
                              style: const TextStyle(
                                  fontFamily: 'Poppinsr',
                                  color: Color(0XFF9091A4),
                                  letterSpacing: 0.5,
                                  height: 2),
                            )),
                        Container(
                            padding: const EdgeInsets.only(
                                left: 20, right: 20, top: 20),

                            // height: 120,

                            child: DottedBorder(
                                borderType: BorderType.RRect,
                                radius: const Radius.circular(12),
                                dashPattern: const [4, 2],
                                color: const Color(0XFFB7B7B7),
                                child: ClipRRect(
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(12)),
                                    child: Container(
                                        padding: const EdgeInsets.only(
                                            left: 20,
                                            right: 20,
                                            top: 20,
                                            bottom: 20),

                                        // height: 120,

                                        alignment: Alignment.center,
                                        child: TextFormField(
                                          textAlign: TextAlign.center,

                                          controller: txt,

                                          // textAlignVertical: TextAlignVertical.center,

                                          decoration: InputDecoration(
                                            border: InputBorder.none,

                                            hintText: "Write Coupon Code",

                                            //  hintTextDirection: TextDecoration.lineThrough

                                            // contentPadding: EdgeInsets.only(left: 80,right: 30),
                                          ),
                                        ))))),
                        Padding(
                          padding: const EdgeInsets.only(top: 30, bottom: 30),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 100, vertical: 15),
                              backgroundColor: Color(COLOR_PRIMARY),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              // Find matching coupon first (accumulate value)
                              OfferModel? foundCoupon;
                              for (int a = 0; a < snapshot.data!.length; a++) {
                                OfferModel coupon = snapshot.data![a];

                                if (vendorID == coupon.restaurantId ||
                                    coupon.restaurantId == "") {
                                  if (txt.text.toString() ==
                                      coupon.offerCode!.toString()) {
                                    print(coupon.toJson());
                                    foundCoupon = coupon;

                                    // if (couponModel.discountTypeOffer == 'Percentage' || couponModel.discountTypeOffer == 'Percent') {

                                    //   percentage = double.parse(couponModel.discountOffer!);

                                    //   couponId = couponModel.offerId!;

                                    //   break;

                                    // } else {

                                    //   type = double.parse(couponModel.discountOffer!);

                                    //   couponId = couponModel.offerId!;

                                    // }
                                  }
                                }
                              }

                              // Call setState once after the loop
                              if (foundCoupon != null) {
                                setState(() {
                                  couponModel = foundCoupon!;
                                });
                              }

                              Navigator.pop(context);
                            },
                            child: Text(
                              "REDEEM NOW",
                              style: TextStyle(
                                  color: isDarkMode(context)
                                      ? Colors.black
                                      : Colors.white,
                                  fontFamily: 'Poppinsm',
                                  fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),

                //buildcouponItem(snapshot)

                //  listData(snapshot)
              ]);
            }));
  }

  _displayDialog(BuildContext context) async {
    return showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text('Tip your driver partner'),
            content: TextField(
              controller: _textFieldController,
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.numberWithOptions(),
              decoration: InputDecoration(hintText: "Enter your tip"),
            ),
            actions: <Widget>[
              new ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                    textStyle: TextStyle(fontWeight: FontWeight.normal)),
                child: new Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              new ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                    textStyle: TextStyle(fontWeight: FontWeight.normal)),
                child: new Text('Submit'),
                onPressed: () {
                  // TODO: large rebuild
                  setState(() {
                    var value = _textFieldController.text.toString();

                    if (value.isEmpty) {
                      isTipSelected3 = false;

                      tipValue = 0;
                    } else {
                      isTipSelected3 = true;

                      tipValue = double.parse(value);
                    }

                    isTipSelected = false;

                    isTipSelected1 = false;

                    isTipSelected2 = false;

                    Navigator.of(context).pop();
                  });
                  // Recalculate totals after custom tip change
                  if (cartProducts.isNotEmpty) {
                    _calculateAndUpdateTotals(
                        cartProducts, lstExtras, vendorID);
                  }
                },
              )
            ],
          );
        });
  }

  Future<void> getPrefData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (prefs.containsKey('musics_key')) {
      final String musicsString = prefs.getString('musics_key')!;

      if (musicsString.isNotEmpty) {
        lstExtras = AddAddonsDemo.decode(musicsString);

        lstExtras.forEach((element) {
          commaSepratedAddOns.add(element.name!);
        });

        commaSepratedAddOnsString = commaSepratedAddOns.join(", ");

        commaSepratedAddSizeString = commaSepratedAddSize.join(", ");
      }
    }
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    sp.setString("musics_key", "");

    sp.setString("addsize", "");
  }

  Widget tipWidgetMethod({String? amount}) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: 5),
        padding: EdgeInsets.fromLTRB(15, 10, 15, 10),
        decoration: BoxDecoration(
          color: tipValue == 10 && isTipSelected
              ? Color(COLOR_PRIMARY)
              : tipValue == 20 && isTipSelected1
                  ? Color(COLOR_PRIMARY)
                  : tipValue == 30 && isTipSelected2
                      ? Color(COLOR_PRIMARY)
                      : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xff9091A4), width: 1),
        ),
        child: Center(
            child: Text(
          amountShow(amount: amount),
          style: TextStyle(
              fontFamily: "Poppinssm",
              color:
                  isDarkMode(context) ? Color(0xffFFFFFF) : Color(0xff333333),
              fontSize: 14),
        )),
      ),
    );
  }

  noteSheet() {
    return Container(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height / 4.3,
            left: 25,
            right: 25),
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(style: BorderStyle.none)),
        child: Column(children: [
          InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 45,

                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 0.3),
                    color: Colors.transparent,
                    shape: BoxShape.circle),

                // radius: 20,

                child: Center(
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              )),
          const SizedBox(
            height: 25,
          ),
          Expanded(
              child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isDarkMode(context)
                      ? const Color(DarkContainerBorderColor)
                      : Colors.grey.shade100,
                  width: 1),
              color: isDarkMode(context)
                  ? const Color(DarkContainerColor)
                  : Colors.white,
              boxShadow: [
                isDarkMode(context)
                    ? const BoxShadow()
                    : BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        blurRadius: 5,
                      ),
              ],
            ),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                      padding: EdgeInsets.only(top: 20),
                      child: Text(
                        'Remarks',
                        style: TextStyle(
                            fontFamily: 'Poppinssb',
                            color: isDarkMode(context)
                                ? Color(0XFFD5D5D5)
                                : Color(0XFF2A2A2A),
                            fontSize: 16),
                      )),
                  Container(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Write remarks for restaurant',
                        style: TextStyle(
                            fontFamily: 'Poppinsr',
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Color(0XFF9091A4),
                            letterSpacing: 0.5,
                            height: 2),
                      )),
                  Container(
                      padding: EdgeInsets.only(left: 20, right: 20, top: 20),

                      // height: 120,

                      child: DottedBorder(
                          borderType: BorderType.RRect,
                          radius: Radius.circular(12),
                          dashPattern: [4, 2],
                          child: ClipRRect(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              child: Container(
                                  padding: EdgeInsets.only(
                                      left: 20, right: 20, top: 20, bottom: 20),
                                  alignment: Alignment.center,
                                  child: TextFormField(
                                    textAlign: TextAlign.center,
                                    controller: noteController,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: 'Write Remarks',
                                    ),
                                  ))))),
                  Padding(
                    padding: const EdgeInsets.only(top: 30, bottom: 30),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 100, vertical: 15),
                        backgroundColor: Color(COLOR_PRIMARY),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text(
                        'SUBMIT',
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                            fontFamily: 'Poppinsm',
                            fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
        ]));
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
    _quantityDebounceTimer?.cancel();
    _quantityDebounceTimer = null;
    _flushPendingQuantityUpdates();
    _distanceCalculationDebounceTimer?.cancel();
    _distanceCalculationDebounceTimer = null;
    // Dispose ValueNotifiers
    scheduleTimeNotifier.dispose();
    isReferralPathNotifier.dispose();
    // Dispose quantity notifiers
    for (var notifier in _itemQuantityNotifiers.values) {
      notifier.dispose();
    }
    _itemQuantityNotifiers.clear();
    super.dispose();
  }
}

Widget _buildChip(String label, int attributesOptionIndex) {
  return Container(
    decoration: BoxDecoration(
        color: const Color(0xffEEEDED), borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
        ),
      ),
    ),
  );
}

// Extracted UI Widgets

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/cart.png',
            width: 200,
            height: 200,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 20),
          showEmptyState('Empty Cart', context),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              push(context, const ViewAllRestaurant());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Order Now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutButton extends StatelessWidget {
  final double grandtotal;
  final bool isEnabled;

  const _CheckoutButton({
    required this.grandtotal,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 1,
        height: MediaQuery.of(context).size.height * 0.080,
        child: Container(
          color: Color(COLOR_PRIMARY),
          padding:
              const EdgeInsets.only(left: 15, right: 10, bottom: 8, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text("Total : ",
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: "Poppinsm",
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFFFFF),
                      )),
                  Text(
                    amountShow(amount: grandtotal.toString()),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ],
              ),
              const Text("PROCEED TO CHECKOUT",
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    color: Color(0xFFFFFFFF),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleOrderCard extends StatelessWidget {
  final Timestamp? scheduleTime;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _ScheduleOrderCard({
    required this.scheduleTime,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      margin: const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDarkMode
                ? const Color(DarkContainerBorderColor)
                : Colors.grey.shade100,
            width: 1),
        color: isDarkMode ? const Color(DarkContainerColor) : Colors.white,
        boxShadow: [
          isDarkMode
              ? const BoxShadow()
              : BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Schedule Order",
                style: TextStyle(
                  fontFamily: "Poppinsm",
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: onTap,
            child: Text(
              scheduleTime == null
                  ? "Select"
                  : DateFormat("EEE dd MMMM , HH:mm aa")
                      .format(scheduleTime!.toDate()),
              style: TextStyle(
                  fontFamily: "Poppinsm", color: Color(COLOR_PRIMARY)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryAddressCard extends StatelessWidget {
  final AddressModel addressModel;
  final VoidCallback onChangeTap;
  final bool isDarkMode;

  const _DeliveryAddressCard({
    required this.addressModel,
    required this.onChangeTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      margin: const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDarkMode
                ? const Color(DarkContainerBorderColor)
                : Colors.grey.shade100,
            width: 1),
        color: isDarkMode ? const Color(DarkContainerColor) : Colors.white,
        boxShadow: [
          isDarkMode
              ? const BoxShadow()
              : BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Address",
                  style: TextStyle(
                      fontFamily: "Poppinsm", fontWeight: FontWeight.w700),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  addressModel.getFullAddress(),
                  style: const TextStyle(
                    fontFamily: "Poppinsm",
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          GestureDetector(
            onTap: onChangeTap,
            child: Text(
              "Change",
              style: TextStyle(
                  fontFamily: "Poppinsm", color: Color(COLOR_PRIMARY)),
            ),
          )
        ],
      ),
    );
  }
}

class _DeliveryOptionCard extends StatelessWidget {
  final String selectedOrderType;
  final String deliveryCharges;
  final bool isDeliveryReady;
  final bool isDarkMode;
  final double fontSize;

  const _DeliveryOptionCard({
    required this.selectedOrderType,
    required this.deliveryCharges,
    required this.isDeliveryReady,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDarkMode
                ? const Color(DarkContainerBorderColor)
                : Colors.grey.shade100,
            width: 1),
        color: isDarkMode ? const Color(DarkContainerColor) : Colors.white,
        boxShadow: [
          isDarkMode
              ? const BoxShadow()
              : BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
        ],
      ),
      child: Column(
        children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Delivery Option: ",
                    style:
                        TextStyle(fontFamily: "Poppinsm", fontSize: fontSize),
                  ),
                  selectedOrderType == "Delivery"
                      ? (isDeliveryReady
                          ? Text(
                              "Delivery (${amountShow(amount: deliveryCharges.toString())})",
                              style: TextStyle(
                                  color: isDarkMode
                                      ? const Color(0xffFFFFFF)
                                      : const Color(0xff333333),
                                  fontSize: fontSize),
                            )
                          : Row(
                              children: [
                                const Text("Delivery ("),
                                ShimmerWidgets.baseShimmer(
                                  baseColor: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[300],
                                  highlightColor: isDarkMode
                                      ? Colors.grey[700]
                                      : Colors.grey[100],
                                  child: Container(
                                    width: 70,
                                    height: fontSize,
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? const Color(0xffFFFFFF)
                                          : const Color(0xff333333),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const Text(")"),
                              ],
                            ))
                      : Text(
                          selectedOrderType + " (Free)",
                          style: TextStyle(
                              color: isDarkMode
                                  ? const Color(0xffFFFFFF)
                                  : const Color(0xff333333),
                              fontSize: 14),
                        ),
                ],
              )),
          const Divider(
            color: Color(0xffE2E8F0),
            height: 0.1,
          ),
        ],
      ),
    );
  }
}

class _OrderTotalRow extends StatelessWidget {
  final double grandtotal;
  final bool isDarkMode;
  final double fontSize;

  const _OrderTotalRow({
    required this.grandtotal,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Order Total",
              style: TextStyle(
                  fontFamily: "Poppinsm",
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? const Color(0xffFFFFFF)
                      : const Color(0xff333333),
                  fontSize: fontSize * 1.0),
            ),
            Text(
              amountShow(amount: grandtotal.toString()),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? const Color(0xffFFFFFF)
                      : const Color(0xff333333),
                  fontSize: fontSize * 1.0),
            ),
          ],
        ));
  }
}

class _ReferralPathIndicator extends StatelessWidget {
  const _ReferralPathIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.people_alt,
            color: Colors.blue,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Referral active → ₱20 promo disabled (mutually exclusive)",
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontFamily: "Poppinsm",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountInfoMessage extends StatelessWidget {
  final String message;

  const _DiscountInfoMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blue.shade700,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontFamily: "Poppinsm",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDiscountRow extends StatelessWidget {
  final String label;
  final double amount;
  final String discountType;
  final bool isDarkMode;
  final double fontSize;

  const _SelectedDiscountRow({
    required this.label,
    required this.amount,
    required this.discountType,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: fontSize,
                              color: discountType == 'happy_hour'
                                  ? Color(COLOR_PRIMARY)
                                  : null),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  "(-${amountShow(amount: amount.toString())})",
                  style: TextStyle(
                      color: isDarkMode
                          ? const Color(0xffFFFFFF)
                          : const Color(0xff333333),
                      fontSize: fontSize),
                ),
              ],
            )),
        const Divider(
          thickness: 1,
        ),
      ],
    );
  }
}

class _HappyHourInfoMessage extends StatelessWidget {
  final int itemsNeeded;
  final String happyHourName;

  const _HappyHourInfoMessage({
    required this.itemsNeeded,
    required this.happyHourName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.orange.shade700,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Add $itemsNeeded more item${itemsNeeded > 1 ? 's' : ''} to qualify for Happy Hour: $happyHourName',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
                fontFamily: "Poppinsm",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCouponDiscountRow extends StatelessWidget {
  final String couponCode;
  final double discountAmount;
  final double fontSize;

  const _ManualCouponDiscountRow({
    required this.couponCode,
    required this.discountAmount,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_offer,
                      size: 16,
                      color: Color(COLOR_PRIMARY),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Coupon Discount ($couponCode)",
                      style:
                          TextStyle(fontFamily: "Poppinsm", fontSize: fontSize),
                    ),
                  ],
                ),
                Text(
                  "(-${amountShow(amount: discountAmount.toString())})",
                  style: TextStyle(color: Colors.red, fontSize: fontSize),
                ),
              ],
            )),
        const Divider(
          thickness: 1,
        ),
      ],
    );
  }
}

class _SpecialDiscountRow extends StatelessWidget {
  final double specialDiscount;
  final String specialType;
  final double specialDiscountAmount;
  final String currencySymbol;
  final double fontSize;

  const _SpecialDiscountRow({
    required this.specialDiscount,
    required this.specialType,
    required this.specialDiscountAmount,
    required this.currencySymbol,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Special Discount" +
                      "($specialDiscount ${specialType == "amount" ? currencySymbol : "%"})",
                  style: TextStyle(fontSize: fontSize),
                ),
                Text(
                  "(-${amountShow(amount: specialDiscountAmount.toString())})",
                  style: TextStyle(
                      fontFamily: "Poppinsm",
                      color: Colors.red,
                      fontSize: fontSize),
                ),
              ],
            )),
        const Divider(
          thickness: 1,
        ),
      ],
    );
  }
}

class _DeliveryChargesRow extends StatelessWidget {
  final String deliveryCharges;
  final double? distanceKm;
  final bool isDeliveryReady;
  final bool isDarkMode;
  final double fontSize;

  const _DeliveryChargesRow({
    required this.deliveryCharges,
    this.distanceKm,
    required this.isDeliveryReady,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Delivery Charges",
                style: TextStyle(
                    fontFamily: "Poppinsm", fontSize: fontSize),
              ),
              isDeliveryReady
                  ? Text(
                      amountShow(amount: deliveryCharges.toString()),
                      style: TextStyle(
                          color: isDarkMode
                              ? const Color(0xffFFFFFF)
                              : const Color(0xff333333),
                          fontSize: fontSize),
                    )
                  : ShimmerWidgets.baseShimmer(
                      baseColor:
                          isDarkMode ? Colors.grey[800] : Colors.grey[300],
                      highlightColor:
                          isDarkMode ? Colors.grey[700] : Colors.grey[100],
                      child: Container(
                        width: 70,
                        height: fontSize,
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xffFFFFFF)
                              : const Color(0xff333333),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
            ],
          ),
          const Divider(
            thickness: 1,
          ),
        ],
      ),
    );
  }
}

class _GiftCardSection extends StatefulWidget {
  final List<Map<String, dynamic>> activeGiftCards;
  final double giftCardAmountToUse;
  final bool isGiftCardApplied;
  final void Function(String cardId, double amount) onApply;
  final VoidCallback onRemove;
  final bool isDarkMode;

  const _GiftCardSection({
    required this.activeGiftCards,
    required this.giftCardAmountToUse,
    required this.isGiftCardApplied,
    required this.onApply,
    required this.onRemove,
    required this.isDarkMode,
  });

  @override
  State<_GiftCardSection> createState() => _GiftCardSectionState();
}

class _GiftCardSectionState extends State<_GiftCardSection> {
  int _selectedIndex = 0;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.activeGiftCards;
    if (cards.isEmpty) return const SizedBox.shrink();

    final selected = cards[_selectedIndex.clamp(0, cards.length - 1)];
    final balance = (selected['remainingBalance'] as num?)?.toDouble() ?? 0.0;
    final cardId = selected['cardId'] as String? ?? '';
    final maskedCode = selected['maskedCode'] as String? ?? '****';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard,
                  color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Gift Card',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!widget.isGiftCardApplied) ...[
            if (cards.length > 1)
              DropdownButton<int>(
                value: _selectedIndex.clamp(0, cards.length - 1),
                items: List.generate(cards.length, (i) {
                  final c = cards[i];
                  final m = c['maskedCode'] ?? '****';
                  final b = (c['remainingBalance'] as num?)?.toDouble() ?? 0;
                  return DropdownMenuItem(
                    value: i,
                    child: Text('$m - ${amountShow(amount: b.toStringAsFixed(0))}'),
                  );
                }),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedIndex = v);
                },
              ),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Amount (max ${amountShow(amount: balance.toStringAsFixed(0))})',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    final amt = double.tryParse(_amountController.text.trim());
                    if (amt == null || amt <= 0 || amt > balance) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Enter amount between 1 and ${balance.toStringAsFixed(0)}',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    widget.onApply(cardId, amt);
                    _amountController.clear();
                  },
                  child: const Text('Apply'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Applied: ${amountShow(amount: widget.giftCardAmountToUse.toStringAsFixed(2))}',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                color: Colors.orange.shade800,
                fontSize: 14,
              ),
            ),
            TextButton(
              onPressed: widget.onRemove,
              child: Text(
                'Remove',
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferralWalletCard extends StatelessWidget {
  final double referralWalletAmountAvailable;
  final double referralWalletAmountToUse;
  final bool isReferralWalletApplied;
  final VoidCallback onApply;
  final VoidCallback onRemove;
  final bool isDarkMode;

  const _ReferralWalletCard({
    required this.referralWalletAmountAvailable,
    required this.referralWalletAmountToUse,
    required this.isReferralWalletApplied,
    required this.onApply,
    required this.onRemove,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet,
                  color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Referral Wallet',
                style: TextStyle(
                  fontFamily: "Poppinsm",
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Available: ${amountShow(amount: referralWalletAmountAvailable.toStringAsFixed(2))}',
            style: TextStyle(
              fontFamily: "Poppinsr",
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          if (isReferralWalletApplied)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Applied: ${amountShow(amount: referralWalletAmountToUse.toStringAsFixed(2))}',
                      style: TextStyle(
                        fontFamily: "Poppinsm",
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: onRemove,
                    color: Colors.grey.shade600,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Apply Referral Wallet',
                style: TextStyle(
                  fontFamily: "Poppinsm",
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'For order use only. Cannot be withdrawn or transferred.',
            style: TextStyle(
              fontFamily: "Poppinsr",
              fontSize: 10,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _SadaqaSection extends StatelessWidget {
  final double tipValue;
  final bool isTipSelected;
  final bool isTipSelected1;
  final bool isTipSelected2;
  final bool isTipSelected3;
  final VoidCallback onTip10Tap;
  final VoidCallback onTip20Tap;
  final VoidCallback onTip30Tap;
  final VoidCallback onOtherTap;
  final bool isDarkMode;

  const _SadaqaSection({
    required this.tipValue,
    required this.isTipSelected,
    required this.isTipSelected1,
    required this.isTipSelected2,
    required this.isTipSelected3,
    required this.onTip10Tap,
    required this.onTip20Tap,
    required this.onTip30Tap,
    required this.onOtherTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Image(
              image: const AssetImage('assets/images/sadaqa.png'),
              width: 200,
            ),
          ),
          Text(
            "Give sadaqa your delivery partner",
            textAlign: TextAlign.start,
            style: TextStyle(
                fontFamily: "Poppinsm",
                fontWeight: FontWeight.bold,
                color: isDarkMode
                    ? const Color(0xffFFFFFF)
                    : const Color(0xff333333),
                fontSize: 15),
          ),
          const Text(
            "100% of your sadaqa will go to your delivery partner",
            style: TextStyle(
                fontFamily: "Poppinsm", color: Color(0xff9091A4), fontSize: 14),
          ),
          const SizedBox(
            height: 15,
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onTip10Tap,
                child: Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                  decoration: BoxDecoration(
                    color: tipValue == 10 && isTipSelected
                        ? Color(COLOR_PRIMARY)
                        : isDarkMode
                            ? const Color(DARK_COLOR)
                            : const Color(0xffFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xff9091A4), width: 1),
                  ),
                  child: Center(
                      child: Text(
                    amountShow(amount: "10"),
                    style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xffFFFFFF)
                            : const Color(0xff333333),
                        fontSize: 14),
                  )),
                ),
              ),
              GestureDetector(
                onTap: onTip20Tap,
                child: Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                  decoration: BoxDecoration(
                    color: tipValue == 20 && isTipSelected1
                        ? Color(COLOR_PRIMARY)
                        : isDarkMode
                            ? const Color(DARK_COLOR)
                            : const Color(0xffFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xff9091A4), width: 1),
                  ),
                  child: Center(
                      child: Text(
                    amountShow(amount: "20"),
                    style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xffFFFFFF)
                            : const Color(0xff333333),
                        fontSize: 14),
                  )),
                ),
              ),
              GestureDetector(
                onTap: onTip30Tap,
                child: Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                  decoration: BoxDecoration(
                    color: tipValue == 30 && isTipSelected2
                        ? Color(COLOR_PRIMARY)
                        : isDarkMode
                            ? const Color(DARK_COLOR)
                            : const Color(0xffFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xff9091A4), width: 1),
                  ),
                  child: Center(
                      child: Text(
                    amountShow(amount: "30"),
                    style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xffFFFFFF)
                            : const Color(0xff333333),
                        fontSize: 14),
                  )),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onOtherTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                    decoration: BoxDecoration(
                      color: isTipSelected3
                          ? Color(COLOR_PRIMARY)
                          : isDarkMode
                              ? const Color(DARK_COLOR)
                              : const Color(0xffFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xff9091A4), width: 1),
                    ),
                    child: Center(
                        child: Text(
                      "Other",
                      style: TextStyle(
                          fontFamily: "Poppinsm",
                          color: isDarkMode
                              ? const Color(0xffFFFFFF)
                              : const Color(0xff333333),
                          fontSize: 14),
                    )),
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}

class _ManualCouponSection extends StatelessWidget {
  final OfferModel? manualCoupon;
  final double manualCouponDiscountAmount;
  final String? manualCouponError;
  final bool isManualCouponValidating;
  final TextEditingController manualCouponCodeController;
  final VoidCallback onApplyCoupon;
  final VoidCallback onRemoveCoupon;
  final VoidCallback onBrowsePromos;
  final bool isDarkMode;
  final double fontSize;

  const _ManualCouponSection({
    required this.manualCoupon,
    required this.manualCouponDiscountAmount,
    required this.manualCouponError,
    required this.isManualCouponValidating,
    required this.manualCouponCodeController,
    required this.onApplyCoupon,
    required this.onRemoveCoupon,
    required this.onBrowsePromos,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode
              ? const Color(DarkContainerBorderColor)
              : Colors.grey.shade200,
          width: 1,
        ),
        color: isDarkMode ? const Color(DarkContainerColor) : Colors.white,
        boxShadow: [
          if (!isDarkMode)
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Apply Coupon',
                style: TextStyle(
                  fontFamily: "Poppinsm",
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (manualCoupon != null)
                GestureDetector(
                  onTap: onBrowsePromos,
                  child: Text(
                    'Browse Promos',
                    style: TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 12,
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (manualCoupon != null && manualCouponDiscountAmount > 0)
            // Applied coupon display (success state)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manualCoupon!.offerCode ?? '',
                          style: TextStyle(
                            fontFamily: "Poppinsm",
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Discount: ${amountShow(amount: manualCouponDiscountAmount.toStringAsFixed(2))}',
                          style: TextStyle(
                            fontFamily: "Poppinsr",
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onRemoveCoupon,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            )
          else if (manualCoupon != null && manualCouponDiscountAmount == 0.0)
            // Unavailable coupon display (warning/info state)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manualCoupon!.offerCode ?? '',
                          style: TextStyle(
                            fontFamily: "Poppinsm",
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          manualCouponError ??
                              'This promo does not apply to your cart',
                          style: TextStyle(
                            fontFamily: "Poppinsr",
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onRemoveCoupon,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onBrowsePromos,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  side: BorderSide(
                    color: isDarkMode
                        ? const Color(DarkContainerBorderColor)
                        : const Color(0xffE5E7EB),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  backgroundColor: isDarkMode
                      ? const Color(DarkContainerColor)
                      : Colors.white,
                ),
                icon: Icon(
                  Icons.confirmation_number_outlined,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
                label: Text(
                  'Apply a voucher',
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          if (manualCouponError != null && manualCoupon == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText.rich(
                      TextSpan(
                        text: manualCouponError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontFamily: "Poppinsm",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CartCompleteYourMealSection extends StatelessWidget {
  final List<CartProduct> cartProducts;
  final String vendorID;
  final CartDatabase cartDatabase;

  const _CartCompleteYourMealSection({
    required this.cartProducts,
    required this.vendorID,
    required this.cartDatabase,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AddonPromoModel>>(
      future: AddonPromoService.getActiveAddonPromos(
        restaurantId: vendorID,
        limit: 50,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final allPromos = snapshot.data!;
        final cartProductIds =
            cartProducts.map((p) => p.id.split('~').first).toSet();
        final addonCountByPromo = <String, int>{};
        for (final p in cartProducts) {
          if (p.addonPromoId != null && p.addonPromoId!.isNotEmpty) {
            addonCountByPromo[p.addonPromoId!] =
                (addonCountByPromo[p.addonPromoId!] ?? 0) + p.quantity;
          }
        }
        final promos = allPromos.where((promo) {
          if (promo.triggerType != 'product') return false;
          if (!cartProductIds.contains(promo.triggerProductId)) return false;
          final count = addonCountByPromo[promo.addonPromoId] ?? 0;
          return count < promo.maxQuantityPerOrder;
        }).toList();
        if (promos.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(13, 16, 13, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete your meal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: promos.length,
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AddonPromoCard(
                        promo: promo,
                        onAdd: () async {
                          await cartDatabase.addAddonToCart(
                            addonPromoId: promo.addonPromoId,
                            addonPromoName: promo.addonName,
                            productId: promo.addonProductId,
                            productName: promo.addonProductName,
                            photo: promo.imageUrl ?? '',
                            addonPrice: promo.addonPrice,
                            vendorID: vendorID,
                            quantity: 1,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${promo.addonName} added to cart',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
