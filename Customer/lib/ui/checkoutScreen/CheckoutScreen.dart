import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/dispatch_precheck_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/placeOrderScreen/PlaceOrderScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/TaxModel.dart';
import 'package:foodie_customer/services/happy_hour_helper.dart';
import 'package:foodie_customer/services/happy_hour_service.dart';

class CheckoutScreen extends StatefulWidget {
  final String paymentOption, paymentType;
  final double total;
  final double? discount;
  final String? couponCode;
  final String? couponId, notes;
  final List<CartProduct> products;
  final List<String>? extraAddons;
  final String? tipValue;
  final bool? takeAway;
  final String? deliveryCharge;
  final String? size;
  final bool isPaymentDone;
  final List<TaxModel>? taxModel;
  final Map<String, dynamic>? specialDiscountMap;
  final Timestamp? scheduleTime;
  final AddressModel? address;

  // Referral system parameters
  final bool isReferralPath;
  final String? referralAuditNote;

  // Manual coupon parameters
  final String? manualCouponCode;
  final String? manualCouponId;
  final double? manualCouponDiscountAmount;
  final String? manualCouponImage;

  // Referral wallet parameter
  final double? referralWalletAmountUsed;

  const CheckoutScreen(
      {Key? key,
      required this.isPaymentDone,
      required this.paymentOption,
      required this.paymentType,
      required this.total,
      this.discount,
      this.couponCode,
      this.couponId,
      this.notes,
      required this.products,
      this.extraAddons,
      this.tipValue,
      this.takeAway,
      this.deliveryCharge,
      this.taxModel,
      this.specialDiscountMap,
      this.size,
      this.scheduleTime,
      this.address,
      this.isReferralPath = false,
      this.referralAuditNote,
      this.manualCouponCode,
      this.manualCouponId,
      this.manualCouponDiscountAmount,
      this.manualCouponImage,
      this.referralWalletAmountUsed})
      : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final fireStoreUtils = FireStoreUtils();
  final DispatchPrecheckService _dispatchPrecheckService =
      DispatchPrecheckService();
  late Map<String, dynamic>? adminCommission;
  String? adminCommissionValue = "", addminCommissionType = "";
  bool? isEnableAdminCommission = false;
  bool isLoading = false; // Manage loading state

  Future<void> _redirectGuestToAuth() async {
    if (!mounted || MyAppState.currentUser != null) return;

    final shouldLogin = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text('Please login to place your order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Login'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (shouldLogin == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void initState() {
    super.initState();

    if (MyAppState.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectGuestToAuth();
      });
      return;
    }

    placeAutoOrder();
    fireStoreUtils.getAdminCommission().then((value) {
      if (value != null) {
        setState(() {
          adminCommission = value;
          adminCommissionValue = adminCommission!["adminCommission"].toString();
          addminCommissionType =
              adminCommission!["adminCommissionType"].toString();
          isEnableAdminCommission = adminCommission!["isAdminCommission"];
        });
      }
    });
  }

  placeAutoOrder() {
    if (MyAppState.currentUser == null) {
      return;
    }
    if (widget.isPaymentDone) {
      Future.delayed(Duration(seconds: 2), () {
        placeOrder();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _calculateSubtotal(widget.products);
    final promoDiscountAmount = _getPromoDiscountAmount();
    final promoDiscountLabel = _getPromoDiscountLabel();
    final specialDiscountAmount = _getSpecialDiscountAmount();
    final specialDiscountLabel = _getSpecialDiscountLabel();
    final tipAmount = double.tryParse(widget.tipValue ?? '') ?? 0.0;
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        centerTitle: false,
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        title: Text(
          'Checkout',
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          // Main UI
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    // Payment Details
                    Container(
                      color: isDarkMode(context) ? Colors.black : Colors.white,
                      child: ListTile(
                        leading: Text(
                          'Payment',
                          style: TextStyle(
                              color: Color(COLOR_PRIMARY),
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                        trailing: Text(
                          widget.paymentOption,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    Divider(height: 3),
                    // Delivery Address
                    Container(
                      color: isDarkMode(context) ? Colors.black : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Deliver to',
                              style: TextStyle(
                                  color: Color(COLOR_PRIMARY),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                            Container(
                              width: MediaQuery.of(context).size.width / 2,
                              child: Text(
                                widget.address?.getFullAddress() ??
                                    'No address selected',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 3),
                    // Order Summary
                    Container(
                      color: isDarkMode(context) ? Colors.black : Colors.white,
                      child: Column(
                        children: [
                          // Subtotal
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Subtotal',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16),
                                ),
                                Text(
                              amountShow(amount: subtotal.toString()),
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          // Delivery Fee
                          if (widget.deliveryCharge != null &&
                              double.parse(widget.deliveryCharge ?? "0") > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Delivery Fee',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    amountShow(amount: widget.deliveryCharge!),
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          // Manual Coupon Discount
                          if (widget.manualCouponId != null &&
                              widget.manualCouponId!.isNotEmpty &&
                              (widget.manualCouponDiscountAmount ?? 0.0) > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Coupon Discount (${widget.manualCouponCode ?? ''})',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: Colors.green),
                                  ),
                                  Text(
                                    "(-${amountShow(amount: widget.manualCouponDiscountAmount.toString())})",
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          // Referral Wallet Deduction
                          if (widget.referralWalletAmountUsed != null &&
                              widget.referralWalletAmountUsed! > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Referral Wallet',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: Colors.green),
                                  ),
                                  Text(
                                    "(-${amountShow(amount: widget.referralWalletAmountUsed.toString())})",
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          // Promo Discount (single-discount policy)
                          if (promoDiscountAmount > 0 &&
                              promoDiscountLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      promoDiscountLabel,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                          color: Colors.green),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    "(-${amountShow(amount: promoDiscountAmount.toString())})",
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          // Vendor Special Discount
                          if (specialDiscountAmount > 0 &&
                              specialDiscountLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      specialDiscountLabel,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    "(-${amountShow(amount: specialDiscountAmount.toString())})",
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          // Tax
                          if (widget.taxModel != null &&
                              widget.taxModel!.isNotEmpty)
                            ...widget.taxModel!.map(
                              (tax) {
                                final taxableBase = (subtotal -
                                        (widget.manualCouponDiscountAmount ??
                                            0.0) -
                                        specialDiscountAmount -
                                        promoDiscountAmount)
                                    .clamp(0.0, double.infinity);
                                final taxAmount = calculateTax(
                                  amount: taxableBase.toString(),
                                  taxModel: tax,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "${tax.title} (${tax.type == "fix" ? amountShow(amount: tax.tax) : "${tax.tax}%"})",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        amountShow(amount: taxAmount.toString()),
                                        style: TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          // Tip (Sadaqa)
                          if (tipAmount > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Sadaqa amount',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16),
                                  ),
                                  Text(
                                    amountShow(amount: tipAmount.toString()),
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          Divider(height: 1),
                          // Final Total
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: TextStyle(
                                      color: Color(COLOR_PRIMARY),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                                Text(
                                  amountShow(amount: widget.total.toString()),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  shrinkWrap: true,
                ),
              ),
              // Place Order Button
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Color(COLOR_PRIMARY),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: (widget.isPaymentDone || isLoading)
                      ? null
                      : () {
                          placeOrder();
                        },
                  child: Text(
                    'PLACE ORDER',
                    style: TextStyle(
                        color:
                            isDarkMode(context) ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
          // Loading Indicator
          if (isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Future<void> placeOrder() async {
    if (isLoading) return;
    if (MyAppState.currentUser == null) {
      await _redirectGuestToAuth();
      return;
    }

    setState(() {
      isLoading = true; // Show loading indicator
    });
    try {
      log("Step 1: Validating products list");
      if (widget.products.isEmpty || widget.products.first.vendorID.isEmpty) {
        throw Exception("Invalid or missing vendorID");
      }

      if (widget.address == null) {
        throw Exception("Delivery address is null");
      }

      print('[CHECKOUT] ===== PLACE ORDER STARTED =====');
      print('[CHECKOUT] Calling DispatchPrecheckService...');
      print('[CHECKOUT] Address: '
          '${widget.address?.getFullAddress()}');
      print('[CHECKOUT] Location: '
          'lat=${widget.address?.location?.latitude}, '
          'lng=${widget.address?.location?.longitude}');
      print('[CHECKOUT] Locality: '
          '${widget.address?.locality}');

      final precheck = await _dispatchPrecheckService.runPrecheck(
        customerId: MyAppState.currentUser?.userID ?? '',
        vendorId: widget.products.first.vendorID,
        deliveryLat: widget.address?.location?.latitude,
        deliveryLng: widget.address?.location?.longitude,
        deliveryLocality: widget.address?.locality,
      );

      print('[CHECKOUT] Precheck result: '
          'canCheckout=${precheck.canCheckout}, '
          'orders=${precheck.activeOrders}, '
          'riders=${precheck.activeRiders}');

      if (!precheck.canCheckout) {
        print('[CHECKOUT] BLOCKED by capacity precheck');
        await _showCheckoutBlockedDialog(
          message: precheck.blockedMessage ??
            'We are unable to process checkout at the moment. Please try again shortly.',
        );
        return;
      }
      print('[CHECKOUT] Proceeding with order...');

      log("Step 2: Fetching vendor details");
      final vendorModel = await fireStoreUtils
          .getVendorByVendorID(widget.products.first.vendorID)
          .whenComplete(() => setPrefData());

      log("Vendor details fetched: ${vendorModel.toJson()}");

      log("Delivery address: ${widget.address?.getFullAddress()}");

      // Re-validate Happy Hour before placing order
      Map<String, dynamic>? happyHourInfo;
      String? happyHourExpiredMessage;
      
      if (widget.specialDiscountMap != null && 
          widget.specialDiscountMap!.containsKey('happy_hour_config_id')) {
        try {
          final settings = await HappyHourService.getHappyHourSettings();
          final configId = widget.specialDiscountMap!['happy_hour_config_id'] as String;
          
          // Check if Happy Hour is still active
          final activeConfig = await HappyHourHelper.getActiveHappyHour(settings);
          
          if (activeConfig == null || activeConfig.id != configId) {
            // Happy Hour has expired
            happyHourExpiredMessage = "Happy Hour promo has ended";
            log("Happy Hour expired: $happyHourExpiredMessage");
            
            // Remove Happy Hour discount from specialDiscountMap
            final updatedMap = Map<String, dynamic>.from(widget.specialDiscountMap!);
            updatedMap.remove('happy_hour_discount');
            updatedMap.remove('happy_hour_config_id');
            updatedMap.remove('happy_hour_name');
            
            // Show message but continue with order
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(happyHourExpiredMessage),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            // Happy Hour still active, keep the info
            happyHourInfo = {
              'happy_hour_discount': widget.specialDiscountMap!['happy_hour_discount'],
              'happy_hour_config_id': configId,
              'happy_hour_name': widget.specialDiscountMap!['happy_hour_name'],
            };
          }
        } catch (e) {
          log("Error validating Happy Hour: $e");
          // Continue without Happy Hour if validation fails
        }
      }

      // Prepare specialDiscountMap with or without Happy Hour
      Map<String, dynamic>? finalSpecialDiscountMap;
      if (widget.specialDiscountMap != null) {
        finalSpecialDiscountMap = Map<String, dynamic>.from(widget.specialDiscountMap!);
        if (happyHourInfo != null) {
          // Update with validated Happy Hour info
          finalSpecialDiscountMap.addAll(happyHourInfo);
        } else {
          // Remove Happy Hour info if expired
          finalSpecialDiscountMap.remove('happy_hour_discount');
          finalSpecialDiscountMap.remove('happy_hour_config_id');
          finalSpecialDiscountMap.remove('happy_hour_name');
        }
      }

      // Check if first-order coupon was applied
      bool isFirstOrderCoupon = widget.couponId == "FIRST_ORDER_AUTO";
      double? firstOrderDiscountAmount =
          isFirstOrderCoupon ? widget.discount : null;

      // Single-discount policy: one applied discount for Rider/display
      String? appliedDiscountType;
      double? appliedDiscountAmount;
      if (widget.specialDiscountMap != null &&
          widget.specialDiscountMap!['applied_discount_amount'] != null) {
        appliedDiscountType = widget.specialDiscountMap!['applied_discount_type'] as String?;
        final v = widget.specialDiscountMap!['applied_discount_amount'];
        appliedDiscountAmount = v is num ? v.toDouble() : double.tryParse(v.toString());
      } else if (isFirstOrderCoupon && widget.discount != null) {
        appliedDiscountType = 'first_order';
        appliedDiscountAmount = widget.discount;
      } else if (widget.manualCouponDiscountAmount != null &&
          widget.manualCouponDiscountAmount! > 0) {
        appliedDiscountType = 'manual_coupon';
        appliedDiscountAmount = widget.manualCouponDiscountAmount;
      }

      OrderModel orderModel = OrderModel(
        address: widget.address,
        author: MyAppState.currentUser,
        authorID: MyAppState.currentUser?.userID ?? '',
        createdAt: Timestamp.now(),
        products: widget.products,
        status: ORDER_STATUS_PLACED,
        vendor: vendorModel,
        vendorID: widget.products.first.vendorID,
        discount: widget.discount,
        couponCode: widget.couponCode,
        couponId: widget.couponId,
        notes: widget.notes,
        taxModel: widget.taxModel,
        paymentMethod: widget.paymentType,
        specialDiscount: finalSpecialDiscountMap,
        tipValue: widget.tipValue,
        adminCommission:
            (isEnableAdminCommission ?? false) ? adminCommissionValue : "0",
        adminCommissionType:
            (isEnableAdminCommission ?? false) ? addminCommissionType : "",
        deliveryCharge: widget.deliveryCharge,
        scheduleTime: widget.scheduleTime,
        // Referral system fields
        isReferralPath: widget.isReferralPath,
        referralAuditNote: widget.referralAuditNote,
        // First-order coupon tracking
        appliedCouponId: isFirstOrderCoupon ? widget.couponId : null,
        couponDiscountAmount: firstOrderDiscountAmount,
        // Single-discount policy (one discount only)
        appliedDiscountType: appliedDiscountType,
        appliedDiscountAmount: appliedDiscountAmount,
        // Referral wallet usage
        referralWalletAmountUsed: widget.referralWalletAmountUsed,
      );

      log("Placing order with Firestore...");
      OrderModel placedOrder = await fireStoreUtils.placeOrder(orderModel);
      log("Order placed successfully: ${placedOrder.id}");

      // Mark first order as completed if this is the user's first order
      if (MyAppState.currentUser != null &&
          !MyAppState.currentUser!.hasCompletedFirstOrder) {
        try {
          // Check if this is truly the first order (no previous completed orders)
          final previousOrders = await FirebaseFirestore.instance
              .collection(ORDERS)
              .where('authorID', isEqualTo: MyAppState.currentUser?.userID ?? '')
              .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
              .limit(1)
              .get();

          if (previousOrders.docs.isEmpty) {
            // This will be the first completed order once it's delivered
            // We'll mark it when status changes to completed
            // For now, just mark hasOrderedBefore
            await FirebaseFirestore.instance
                .collection(USERS)
                .doc(MyAppState.currentUser!.userID)
                .update({
              'hasOrderedBefore': true,
            });
            MyAppState.currentUser!.hasOrderedBefore = true;
          }
        } catch (e) {
          log("❌ Error updating first order status: $e");
        }
      }

      // Deduct referral wallet amount if used
      if (widget.referralWalletAmountUsed != null &&
          widget.referralWalletAmountUsed! > 0 &&
          MyAppState.currentUser != null) {
        try {
          final currentUser = MyAppState.currentUser!;
          final newReferralWalletAmount =
              (currentUser.referralWalletAmount - widget.referralWalletAmountUsed!).clamp(0.0, double.infinity);
          
          // Update user's referral wallet balance
          await FirebaseFirestore.instance
              .collection(USERS)
              .doc(currentUser.userID)
              .update({
            'referralWalletAmount': newReferralWalletAmount,
          });

          // Create transaction record
          await FirebaseFirestore.instance
              .collection('referral_wallet_transactions')
              .add({
            'userId': currentUser.userID,
            'type': 'debit',
            'amount': widget.referralWalletAmountUsed,
            'orderId': placedOrder.id,
            'description': 'Used for order ${placedOrder.id}',
            'createdAt': Timestamp.now(),
          });

          // Update current user object
          currentUser.referralWalletAmount = newReferralWalletAmount;
          MyAppState.currentUser = currentUser;

          log("✅ Referral wallet deducted: ${widget.referralWalletAmountUsed}");
        } catch (e) {
          log("❌ Error deducting referral wallet: $e");
          // Don't block order placement if wallet deduction fails
        }
      }

      showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: false,
        context: context,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => PlaceOrderScreen(orderModel: placedOrder),
      );
    } catch (e) {
      log("Error in placeOrder: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to place order: $e"),
        ),
      );
    } finally {
      setState(() {
        isLoading = false; // Hide loading indicator
      });
    }
  }

  Future<void> _showCheckoutBlockedDialog({required String message}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.schedule,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Checkout Unavailable',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.delivery_dining_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            SelectableText.rich(
              TextSpan(
                text: message,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black87,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateSubtotal(List<CartProduct> products) {
    double subtotal = 0.0;

    for (final product in products) {
      final extrasPrice = double.tryParse(product.extras_price ?? '');
      if (extrasPrice != null && extrasPrice != 0.0) {
        subtotal += extrasPrice * product.quantity;
      }

      final price = double.tryParse(product.price) ?? 0.0;
      subtotal += price * product.quantity;
    }

    return subtotal;
  }

  double _getPromoDiscountAmount() {
    final map = widget.specialDiscountMap;
    if (map == null) return 0.0;
    final amount = map['applied_discount_amount'];
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0.0;
    return 0.0;
  }

  String _getPromoDiscountLabel() {
    final map = widget.specialDiscountMap;
    if (map == null) return '';
    final type = map['applied_discount_type']?.toString() ?? '';
    if (type.isEmpty) return '';
    if (type == 'happy_hour') {
      final name = map['happy_hour_name']?.toString() ?? '';
      return name.isNotEmpty ? 'Happy Hour: $name' : 'Happy Hour';
    }
    if (type == 'first_order') {
      return 'First-Order Discount';
    }
    if (type == 'new_user_promo') {
      return 'New User Promo';
    }
    return 'Promo Discount';
  }

  double _getSpecialDiscountAmount() {
    final map = widget.specialDiscountMap;
    if (map == null) return 0.0;
    final amount = map['special_discount'];
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0.0;
    return 0.0;
  }

  String _getSpecialDiscountLabel() {
    final map = widget.specialDiscountMap;
    if (map == null) return '';
    final labelValue = map['special_discount_label'];
    final type = map['specialType']?.toString() ?? '';
    if (labelValue == null || type.isEmpty) return '';
    final valueText = labelValue.toString();
    final suffix = type == 'amount' ? currencyModel?.symbol ?? '' : '%';
    return 'Special Discount ($valueText $suffix)';
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    // Save any necessary data here
    sp.setString("musics_key", "");
    sp.setString("addsize", "");
    log("Preferences have been set.");
  }
}
