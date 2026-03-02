import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/CodModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/network_safe_api.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/checkoutScreen/CheckoutScreen.dart';
import 'package:foodie_customer/userPrefrence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/OrderModel.dart';
import '../../model/TaxModel.dart';
import '../../model/User.dart';
import '../../model/VendorModel.dart';
import '../placeOrderScreen/PlaceOrderScreen.dart';

class PaymentScreen extends StatefulWidget {
  final double total;
  final double? discount;
  final String? couponCode;
  final String? couponId, notes;
  final List<CartProduct> products;

  final List<String>? extraAddons;
  final String? tipValue;
  final bool? takeAway;
  final String? deliveryCharge;
  final List<TaxModel>? taxModel;
  final Map<String, dynamic>? specialDiscountMap;
  final Timestamp? scheduleTime;
  final AddressModel? addressModel;

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

  const PaymentScreen(
      {Key? key,
      required this.total,
      this.discount,
      this.couponCode,
      this.couponId,
      required this.products,
      this.extraAddons,
      this.tipValue,
      this.takeAway,
      this.deliveryCharge,
      this.notes,
      this.taxModel,
      this.specialDiscountMap,
      this.scheduleTime,
      this.addressModel,
      this.isReferralPath = false,
      this.referralAuditNote,
      this.manualCouponCode,
      this.manualCouponId,
      this.manualCouponDiscountAmount,
      this.manualCouponImage,
      this.referralWalletAmountUsed})
      : super(key: key);

  @override
  PaymentScreenState createState() => PaymentScreenState();
}

class PaymentScreenState extends State<PaymentScreen> {
  final fireStoreUtils = FireStoreUtils();

  //List<PaymentMethod> _cards = [];
  late Future<CodModel?> futurecod;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? userQuery;

  static FirebaseFirestore fireStore = FirebaseFirestore.instance;

  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String paymentOption = 'Pay Via Wallet';

  bool walletBalanceError = false;
  String paymentType = "";

  late Map<String, dynamic>? adminCommission;
  String? adminCommissionValue = "", addminCommissionType = "";
  bool? isEnableAdminCommission = false;

  Future<void> _redirectGuestToAuth() async {
    if (!mounted || MyAppState.currentUser != null) return;

    final shouldLogin = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text('Please login to proceed to checkout.'),
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

  getPaymentSettingData() async {
    userQuery = fireStore
        .collection(USERS)
        .doc(MyAppState.currentUser!.userID)
        .snapshots();
  }

  Future<void> _onRefresh() async {
    setState(() {
      futurecod = fireStoreUtils.getCod();
      getPaymentSettingData();
    });
    await futurecod;
  }

  showAlert(context, {required String response, required Color colors}) {
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(response),
      backgroundColor: colors,
    ));
  }

  @override
  void initState() {
    super.initState();

    futurecod = fireStoreUtils.getCod();

    if (MyAppState.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectGuestToAuth();
      });
      return;
    }

    getPaymentSettingData();
    FireStoreUtils.createOrder();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: false,
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        centerTitle: false,
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        title: Text(
          'Payment Method',
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: Color(COLOR_PRIMARY),
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16),
          children: [
          Visibility(
            visible: UserPreference.getWalletData() ?? false,
            child: Column(
              children: [
                Divider(),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: userQuery,
                    builder: (context,
                        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                            asyncSnapshot) {
                      if (asyncSnapshot.hasError) {
                        return Text(
                          "error",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        );
                      }
                      if (asyncSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Center(
                            child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 0.8,
                                  color: Colors.white,
                                  backgroundColor: Colors.transparent,
                                )));
                      }
                      if (asyncSnapshot.data == null) {
                        return Container();
                      }
                      User userData =
                          User.fromJson(asyncSnapshot.data!.data()!);

                      walletBalanceError =
                          double.parse(userData.walletAmount.toString()) <
                                  double.parse(widget.total.toString())
                              ? true
                              : false;
                      return Column(
                        children: [
                          CheckboxListTile(
                            onChanged: (bool? value) {
                              setState(() {
                                if (!walletBalanceError) {
                                  wallet = true;
                                  codPay = false;
                                } else {
                                  wallet = false;
                                }
                                paymentOption = "Pay Online Via Wallet";
                              });
                            },
                            value: wallet,
                            contentPadding: EdgeInsets.all(0),
                            secondary: FaIcon(FontAwesomeIcons.wallet),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('G-Cash'),
                                Column(
                                  children: [],
                                )
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Visibility(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 0.0),
                                  child: walletBalanceError
                                      ? Text(
                                          "Sorry G-Cash Payment is not yet available for now.",
                                          style: TextStyle(
                                              fontSize: 14, color: Colors.red),
                                        )
                                      : Text(
                                          'Sufficient Balance',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.green),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }),
              ],
            ),
          ),
          Visibility(
            visible: true,
            child: Column(
              children: [
                Divider(),
                FutureBuilder<CodModel?>(
                    future: futurecod,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting)
                        return Center(
                          child: CircularProgressIndicator.adaptive(
                            valueColor:
                                AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                          ),
                        );
                      if (snapshot.hasData) {
                        return snapshot.data!.cod == true
                            ? CheckboxListTile(
                                onChanged: (bool? value) {
                                  setState(() {
                                    wallet = false;
                                    codPay = true;
                                    paymentOption = 'Cash on Delivery';
                                  });
                                },
                                value: codPay,
                                contentPadding: EdgeInsets.all(0),
                                secondary:
                                    FaIcon(FontAwesomeIcons.handHoldingDollar),
                                title: Text('Cash on Delivery'),
                              )
                            : Center();
                      }
                      return Center();
                    }),
              ],
            ),
          ),
          Divider(),
          SizedBox(
            height: 24,
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(20),
              backgroundColor: Color(COLOR_PRIMARY),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              if (MyAppState.currentUser == null) {
                await _redirectGuestToAuth();
                return;
              }

              await FireStoreUtils.createPaymentId();

              if (wallet) {
                paymentType = 'wallet';
                if (widget.takeAway!) {
                  placeOrder(_scaffoldKey.currentContext!);
                } else {
                  toCheckOutScreen(true, context);
                }
              } else if (codPay) {
                paymentType = 'cod';
                if (widget.takeAway!) {
                  placeOrder(_scaffoldKey.currentContext!);
                } else {
                  toCheckOutScreen(false, context);
                }
              } else {
                final SnackBar snackBar = SnackBar(
                  content: Text(
                    "Select Payment Method",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Color(COLOR_PRIMARY),
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              }
            },
            child: Text(
              'PROCEED',
              style: TextStyle(
                  color: isDarkMode(context) ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
        ],
        ),
      ),
    );
  }

  bool wallet = false;
  bool codPay = false;

  placeOrder(BuildContext buildContext, {String? oid}) async {
    FireStoreUtils fireStoreUtils = FireStoreUtils();
    List<CartProduct> tempProduc = [];

    if (paymentType.isEmpty) {
      ShowDialogToDismiss(
          title: "Empty payment type",
          buttonText: "ok",
          content: "Select payment type");
      return;
    }

    for (CartProduct cartProduct in widget.products) {
      CartProduct tempCart = cartProduct;
      tempProduc.add(tempCart);
    }

    showProgress(buildContext, 'Placing Order...', false);

    try {
      VendorModel vendorModel = await fireStoreUtils
          .getVendorByVendorID(widget.products.first.vendorID)
          .whenComplete(() => setPrefData());

      // Extract discount metadata from specialDiscountMap (single-discount policy)
      String? appliedDiscountType;
      double? appliedDiscountAmount;
      if (widget.specialDiscountMap != null) {
        appliedDiscountType = widget.specialDiscountMap!['applied_discount_type'] as String?;
        if (widget.specialDiscountMap!['applied_discount_amount'] != null) {
          final amountValue = widget.specialDiscountMap!['applied_discount_amount'];
          appliedDiscountAmount = amountValue is num
              ? amountValue.toDouble()
              : double.tryParse(amountValue.toString());
        }
      }

      OrderModel orderModel = OrderModel(
        address: widget.addressModel,
        author: MyAppState.currentUser,
        authorID: MyAppState.currentUser!.userID,
        createdAt: Timestamp.now(),
        products: tempProduc,
        status: ORDER_STATUS_PLACED,
        vendor: vendorModel,
        paymentMethod: paymentType,
        notes: widget.notes,
        taxModel: widget.taxModel,
        vendorID: widget.products.first.vendorID,
        discount: widget.discount,
        specialDiscount: widget.specialDiscountMap,
        couponCode: widget.couponCode,
        couponId: widget.couponId,
        adminCommission: isEnableAdminCommission! ? adminCommissionValue : "0",
        adminCommissionType:
            isEnableAdminCommission! ? addminCommissionType : "",
        scheduleTime: widget.scheduleTime,
        // Referral system fields
        isReferralPath: widget.isReferralPath,
        referralAuditNote: widget.referralAuditNote,
        // Single-discount policy tracking
        appliedDiscountType: appliedDiscountType,
        appliedDiscountAmount: appliedDiscountAmount,
        // Manual coupon fields
        manualCouponCode: widget.manualCouponCode,
        manualCouponId: widget.manualCouponId,
        manualCouponDiscountAmount: widget.manualCouponDiscountAmount,
        manualCouponImage: widget.manualCouponImage,
      );

      if (oid != null && oid.isNotEmpty) {
        orderModel.id = oid;
      }

      final placedOrder = await NetworkSafeAPI.runWithNetworkCheck(
        () => fireStoreUtils.placeOrderWithTakeAWay(orderModel),
        onOffline: () {
          ScaffoldMessenger.of(buildContext).showSnackBar(
            const SnackBar(
              content: Text(
                'No network. Please check your connection and try again.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        },
      );

      for (int i = 0; i < tempProduc.length; i++) {
        await FireStoreUtils()
            .getProductByID(tempProduc[i].id.split('~').first)
            .then((value) async {
          ProductModel? productModel = value;
          if (tempProduc[i].variant_info != null) {
            for (int j = 0;
                j < productModel.itemAttributes!.variants!.length;
                j++) {
              if (productModel.itemAttributes!.variants![j].variantId ==
                  tempProduc[i].id.split('~').last) {
                if (productModel.itemAttributes!.variants![j].variantQuantity !=
                    "-1") {
                  productModel.itemAttributes!.variants![j].variantQuantity =
                      (int.parse(productModel
                                  .itemAttributes!.variants![j].variantQuantity
                                  .toString()) -
                              tempProduc[i].quantity)
                          .toString();
                }
              }
            }
          } else {
            if (productModel.quantity != -1) {
              productModel.quantity =
                  productModel.quantity - tempProduc[i].quantity;
            }
          }

          await FireStoreUtils.updateProduct(productModel).then((value) {});
        });
      }

      showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: false,
        context: buildContext,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => PlaceOrderScreen(orderModel: placedOrder),
      );
    } on NetworkUnavailableException catch (e) {
      ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(
        content: Text(e.message ?? 'No network. Please try again.'),
        backgroundColor: Colors.red,
      ));
      print("Order placement failed (offline): $e");
    } catch (e) {
      ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(
        content: Text("Order placement failed: ${e.toString()}"),
        backgroundColor: Colors.red,
      ));
      print("Order placement failed: $e");
    } finally {
      hideProgress();
    }
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    sp.setString("musics_key", "");
  }

  toCheckOutScreen(bool val, BuildContext context) {
    push(
      context,
      CheckoutScreen(
        address: widget.addressModel,
        isPaymentDone: val,
        paymentType: this.paymentType,
        total: widget.total,
        discount: widget.discount!,
        couponCode: widget.couponCode,
        couponId: widget.couponId,
        notes: widget.notes!,
        paymentOption: paymentOption,
        products: widget.products,
        deliveryCharge: widget.deliveryCharge,
        tipValue: widget.tipValue,
        takeAway: widget.takeAway,
        taxModel: widget.taxModel,
        specialDiscountMap: widget.specialDiscountMap,
        scheduleTime: widget.scheduleTime,
        manualCouponCode: widget.manualCouponCode,
        manualCouponId: widget.manualCouponId,
        manualCouponDiscountAmount: widget.manualCouponDiscountAmount,
        manualCouponImage: widget.manualCouponImage,
        referralWalletAmountUsed: widget.referralWalletAmountUsed,
      ),
    );
  }
}
