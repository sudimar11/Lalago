import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

//import 'package:flutterwave_standard/flutterwave.dart';
import 'package:foodie_customer/model/FlutterWaveSettingDataModel.dart';
import 'package:foodie_customer/model/paypalSettingData.dart';
import 'package:foodie_customer/model/paytmSettingData.dart';
import 'package:foodie_customer/model/topupTranHistory.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:http/http.dart' as http;

import '../../constants.dart';
import '../../main.dart';
import '../../model/OrderModel.dart';
import '../../model/User.dart';
import '../../model/getPaytmTxtToken.dart';
import '../../services/helper.dart';
import '../../userPrefrence.dart';
import '../orderDetailsScreen/OrderDetailsScreen.dart';
import '../auth/AuthScreen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({Key? key}) : super(key: key);

  @override
  WalletScreenState createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  static FirebaseFirestore fireStore = FirebaseFirestore.instance;
  Stream<QuerySnapshot>? topupHistoryQuery;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? userQuery;

  String? selectedRadioTile;

  GlobalKey<FormState> _globalKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  PaytmSettingData? paytmSettingData;
  PaypalSettingData? paypalSettingData;
  FlutterWaveSettingData? flutterWaveSettingData;

  TextEditingController _amountController =
      TextEditingController(text: 50.toString());

  Map<String, dynamic>? paymentIntentData;

  showAlert(context, {required String response, required Color colors}) {
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(response),
      backgroundColor: colors,
      duration: Duration(seconds: 8),
    ));
  }

  final userId = MyAppState.currentUser!.userID;

  getPaymentSettingData() async {
    topupHistoryQuery = fireStore
        .collection(Wallet)
        .where('user_id', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots();
    userQuery = fireStore
        .collection(USERS)
        .doc(MyAppState.currentUser!.userID)
        .snapshots();

    paytmSettingData = await UserPreference.getPaytmData();
    paypalSettingData = await UserPreference.getPayPalData();
    //flutterWaveSettingData = await UserPreference.getFlutterWaveData();
    initPayPal();
  }

  @override
  void initState() {
    setRef();
    getPaymentSettingData();
    selectedRadioTile = "PayTm";

    super.initState();
  }

  void initPayPal() async {
    // Simulate successful payment directly
    await Future.delayed(Duration(seconds: 1)); // simulate loading

    // Notify user payment was successful
    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
      content: Text("Payment Successfully" + "\n"),
      backgroundColor: Colors.green,
    ));

    // Trigger post-payment logic
    paymentCompleted(paymentMethod: "COD");
  }

  @override
  Widget build(BuildContext context) {
    // Show guest placeholder if user is not logged in
    if (MyAppState.currentUser == null) {
      return Scaffold(
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
            'Wallet',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text('Login to view your wallet', style: TextStyle(fontSize: 18)),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => push(context, AuthScreen()),
                child: Text('Login / Register'),
              ),
            ],
          ),
        ),
      );
    }
    
    final size = MediaQuery.of(context).size;
    return Scaffold(
      key: _scaffoldKey,
      body: Container(
        color: Colors.black.withOpacity(0.03),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 120.0),
              child: showTopupHistory(context),
            ),
            Positioned(
              top: 0,
              child: Container(
                decoration: BoxDecoration(
                    image: DecorationImage(
                        fit: BoxFit.fitWidth,
                        image: AssetImage(
                            "assets/images/wallet_background@3x.png"))),
                //color: Colors.deepOrange,
                //height: size.height*0.3,
                width: size.width,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 0.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 15,
                                  ),
                                  Text(
                                    "Total Balance",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10.0, bottom: 20.0),
                                    child: StreamBuilder<
                                        DocumentSnapshot<Map<String, dynamic>>>(
                                      stream: userQuery,
                                      builder: (context,
                                          AsyncSnapshot<
                                                  DocumentSnapshot<
                                                      Map<String, dynamic>>>
                                              asyncSnapshot) {
                                        if (asyncSnapshot.hasError) {
                                          return Text(
                                            "error",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 30),
                                          );
                                        }
                                        if (asyncSnapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return Center(
                                              child: SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 0.8,
                                                    color: Colors.white,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                  )));
                                        }
                                        User userData = User.fromJson(
                                            asyncSnapshot.data!.data()!);
                                        return Text(
                                          "${amountShow(amount: userData.walletAmount.toString())}",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 30),
                                        );
                                      },
                                    ),
                                  ),

                                  // Padding(
                                  //   padding: const EdgeInsets.only(top: 10.0,bottom: 20.0),
                                  //   child: Text("\$$walletAmount",
                                  //     style: TextStyle(color: Colors.white,
                                  //         fontWeight: FontWeight.bold,
                                  //         fontSize: 30),),
                                  // ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 28.0, right: 15, left: 15),
                              child: buildTopUpButton(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTopUpButton() {
    return GestureDetector(
      onTap: () {
        topUpBalance();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10),
          child: Text(
            "TOPUP WALLET",
            style: TextStyle(
                color: Color(COLOR_PRIMARY),
                fontWeight: FontWeight.w700,
                fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget showTopupHistory(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: topupHistoryQuery,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: SizedBox(
                  height: 35, width: 35, child: CircularProgressIndicator()));
        }
        if (snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text(
            "No Transaction History",
            style: TextStyle(fontSize: 18),
          ));
        } else {
          return ListView(
            physics: BouncingScrollPhysics(),
            children: snapshot.data!.docs.map((DocumentSnapshot document) {
              final topUpData = TopupTranHistoryModel.fromJson(
                  document.data() as Map<String, dynamic>);
              //Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
              return buildTransactionCard(
                topupTranHistory: topUpData,
                date: topUpData.date.toDate(),
              );
            }).toList(),
          );
        }
      },
    );
  }

  paymentCompleted({required String paymentMethod}) async {
    await FireStoreUtils.createPaymentId().then((value) async {
      final paymentID = value;
      await FireStoreUtils.topUpWalletAmount(
              paymentMethod: paymentMethod,
              amount: double.parse(_amountController.text),
              id: paymentID)
          .then((value) {
        FireStoreUtils.updateWalletAmount(
                amount: double.parse(_amountController.text))
            .then((value) {
          FireStoreUtils.sendTopUpMail(
              paymentMethod: paymentMethod,
              amount: _amountController.text,
              tractionId: paymentID);
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
              .showSnackBar(SnackBar(
            content: Text("Payment Successful!!" + "\n"),
            backgroundColor: Colors.green,
          ));
        });
      });
    });
  }

  Widget buildTransaction(BuildContext context) {
    return FutureBuilder<List<TopupTranHistoryModel>>(
        future: FireStoreUtils.getTopUpTransaction(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ListView.builder(
                physics: BouncingScrollPhysics(),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  List<TopupTranHistoryModel>? tranHistoryModel = snapshot.data;
                  return buildTransactionCard(
                    topupTranHistory: tranHistoryModel![index],
                    date: tranHistoryModel[index].date.toDate(),
                  );
                });
          } else {
            return Center(
                child: SizedBox(
                    height: 45, width: 45, child: CircularProgressIndicator()));
          }
        });
  }

  Widget buildTransactionCard({
    required TopupTranHistoryModel topupTranHistory,
    required DateTime date,
  }) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3),
      child: GestureDetector(
        onTap: () => showTransactionDetails(topupTranHistory: topupTranHistory),
        child: Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipOval(
                  child: Container(
                    color: Color(COLOR_PRIMARY).withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Icon(Icons.account_balance_wallet_rounded,
                          size: 28, color: Color(COLOR_PRIMARY)),
                    ),
                  ),
                ),
                SizedBox(
                  width: size.width * 0.78,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: size.width * 0.48,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topupTranHistory.isTopup
                                  ? "Wallet Topup"
                                  : "Wallet Amount Deducted",
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(
                              height: 5,
                            ),
                            Opacity(
                              opacity: 0.65,
                              child: Text(
                                "${DateFormat('KK:mm:ss a, dd MMM yyyy').format(topupTranHistory.date.toDate()).toUpperCase()}",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0, left: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${topupTranHistory.isTopup ? "+" : "-"} ${amountShow(amount: topupTranHistory.amount.toString())}",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: topupTranHistory.isTopup
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(
                              height: 8,
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  showLoadingAlert() {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircularProgressIndicator(),
              const Text('Please wait!!'),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                SizedBox(
                  height: 15,
                ),
                Text(
                  'Please wait!! while completing Transaction',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(
                  height: 15,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  showTransactionDetails({
    required TopupTranHistoryModel topupTranHistory,
  }) {
    final size = MediaQuery.of(context).size;
    return showModalBottomSheet(
        elevation: 5,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15), topRight: Radius.circular(15))),
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return Container(
              height: size.height * 0.80,
              width: size.width,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 25.0),
                      child: Text(
                        "Transaction Details",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15.0,
                      ),
                      child: Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Transaction ID",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 10,
                                  ),
                                  Opacity(
                                    opacity: 0.8,
                                    child: Text(
                                      topupTranHistory.id,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 30),
                        child: Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ClipOval(
                                  child: Container(
                                    color:
                                        Color(COLOR_PRIMARY).withOpacity(0.05),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Icon(
                                          Icons.account_balance_wallet_rounded,
                                          size: 28,
                                          color: Color(COLOR_PRIMARY)),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: size.width * 0.48,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${DateFormat('KK:mm:ss a, dd MMM yyyy').format(topupTranHistory.date.toDate())}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(
                                        height: 5,
                                      ),
                                      Opacity(
                                        opacity: 0.7,
                                        child: Text(
                                          topupTranHistory.isTopup
                                              ? "Wallet Topup"
                                              : "Wallet Amount Deducted",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${topupTranHistory.isTopup ? "+" : "-"} ${amountShow(amount: topupTranHistory.amount.toString())}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: topupTranHistory.isTopup
                                            ? Colors.green
                                            : Colors.red,
                                        fontSize: 18,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 8,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 25.0, vertical: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Payment Details",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(
                                        height: 10,
                                      ),
                                      Row(
                                        children: [
                                          Opacity(
                                            opacity: 0.7,
                                            child: Text(
                                              "Pay Via",
                                              style: TextStyle(
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          Visibility(
                                            visible: !topupTranHistory.isTopup,
                                            child: Text(
                                              "  " +
                                                  topupTranHistory.paymentMethod
                                                      .toUpperCase(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Color(COLOR_PRIMARY),
                                                fontSize: 16,
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      if (!topupTranHistory.isTopup) {
                                        FireStoreUtils.firestore
                                            .collection(ORDERS)
                                            .doc(topupTranHistory.orderId)
                                            .get()
                                            .then((value) {
                                          OrderModel orderModel =
                                              OrderModel.fromJson(
                                                  value.data()!);
                                          push(
                                              context,
                                              OrderDetailsScreen(
                                                orderModel: orderModel,
                                              ));
                                        });
                                      }
                                    },
                                    child: Text(
                                      topupTranHistory.isTopup
                                          ? topupTranHistory.paymentMethod
                                              .toUpperCase()
                                          : "View Order".toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(COLOR_PRIMARY),
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 15),
                              child: Divider(),
                            ),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 25.0, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Date in UTC Format",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(
                                        height: 10,
                                      ),
                                      Opacity(
                                        opacity: 0.7,
                                        child: Text(
                                          "${DateFormat('KK:mm:ss a, dd MMM yyyy').format(topupTranHistory.date.toDate()).toUpperCase()}",
                                          style: TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
        });
  }

  topUpBalance() {
    final size = MediaQuery.of(context).size;
    return showModalBottomSheet(
        elevation: 5,
        enableDrag: true,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15), topRight: Radius.circular(15))),
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) => Container(
              //height: size.height * 0.85,
              width: size.width,
              height: size.height * 0.95,
              child: Form(
                key: _globalKey,
                autovalidateMode: AutovalidateMode.always,
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15.0,
                              ),
                              child: RichText(
                                text: TextSpan(
                                  text: "Topup Wallet",
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20.0, vertical: 5),
                            child: RichText(
                              text: TextSpan(
                                text: "Add Topup Amount",
                                style: TextStyle(
                                    fontSize: 16,
                                    color: isDarkMode(context)
                                        ? Colors.white54
                                        : Colors.black54),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 2),
                        child: Card(
                          elevation: 2.0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 0.0, horizontal: 8),
                            child: TextFormField(
                              controller: _amountController,
                              style: TextStyle(
                                color: Color(COLOR_PRIMARY),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              //initialValue:"50",
                              maxLines: 1,
                              validator: (value) {
                                if (value!.isEmpty) {
                                  return "*required Field";
                                } else {
                                  return null;
                                }
                              },
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefix: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 2),
                                  child: Text(
                                    currencyModel!.symbol.toString(),
                                    style: TextStyle(
                                      color: Colors.blueGrey.shade900,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20.0, vertical: 5),
                            child: RichText(
                              text: TextSpan(
                                text: "Select Payment Option",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Visibility(
                        visible: flutterWaveSettingData != null &&
                            flutterWaveSettingData!.isEnable,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3.0, horizontal: 20),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: flutterWave ? 0 : 2,
                            child: RadioListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                      color: flutterWave
                                          ? Color(COLOR_PRIMARY)
                                          : Colors.transparent)),
                              controlAffinity: ListTileControlAffinity.trailing,
                              value: "FlutterWave",
                              groupValue: selectedRadioTile,
                              onChanged: (String? value) {
                                setState(() {
                                  flutterWave = true;
                                  payTm = false;
                                  paypal = false;
                                  selectedRadioTile = value!;
                                });
                              },
                              selected: flutterWave,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4.0, horizontal: 10),
                                        child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 6.0),
                                            child: Image.asset(
                                              "assets/images/flutterwave.png",
                                            ),
                                          ),
                                        ),
                                      )),
                                  SizedBox(
                                    width: 20,
                                  ),
                                  Text("FlutterWave"),
                                ],
                              ),
                              //toggleable: true,
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: paytmSettingData!.isEnabled,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3.0, horizontal: 20),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: payTm ? 0 : 2,
                            child: RadioListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                      color: payTm
                                          ? Color(COLOR_PRIMARY)
                                          : Colors.transparent)),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                              value: "PayTm",
                              groupValue: selectedRadioTile,
                              onChanged: (String? value) {
                                setState(() {
                                  flutterWave = false;
                                  payTm = true;
                                  paypal = false;
                                  selectedRadioTile = value!;
                                });
                              },
                              selected: payTm,
                              //selectedRadioTile == "strip" ? true : false,
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3.0, horizontal: 10),
                                        child: SizedBox(
                                            width: 80,
                                            height: 35,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3.0),
                                              child: Image.asset(
                                                "assets/images/paytm_@3x.png",
                                              ),
                                            )),
                                      )),
                                  SizedBox(
                                    width: 20,
                                  ),
                                  Text("Paytm"),
                                ],
                              ),
                              //toggleable: true,
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: paypalSettingData != null &&
                            paypalSettingData!.isEnabled,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3.0, horizontal: 20),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: paypal ? 0 : 2,
                            child: RadioListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                      color: paypal
                                          ? Color(COLOR_PRIMARY)
                                          : Colors.transparent)),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                              value: "PayPal",
                              groupValue: selectedRadioTile,
                              onChanged: (String? value) {
                                setState(() {
                                  payTm = false;
                                  flutterWave = false;
                                  paypal = true;
                                  selectedRadioTile = value!;
                                });
                              },
                              selected: paypal,
                              //selectedRadioTile == "strip" ? true : false,
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3.0, horizontal: 10),
                                        child: SizedBox(
                                            width: 80,
                                            height: 35,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3.0),
                                              child: Image.asset(
                                                  "assets/images/paypal_@3x.png"),
                                            )),
                                      )),
                                  SizedBox(
                                    width: 20,
                                  ),
                                  Text("PayPal"),
                                ],
                              ),
                              //toggleable: true,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 22),
                        child: GestureDetector(
                          onTap: () async {
                            if (selectedRadioTile == "PayTm") {
                              showLoadingAlert();
                              getPaytmCheckSum(context,
                                  amount: double.parse(_amountController.text));
                            } else if (selectedRadioTile == "PayPal") {
                              Navigator.pop(context);
                              showLoadingAlert();
                              paypalPaymentSheet();
                            } else if (selectedRadioTile == "FlutterWave") {
                              //_flutterWaveInitiatePayment(context);
                            }
                          },
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              color: Color(COLOR_PRIMARY),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                                child: Text(
                              "CONTINUE",
                              style: TextStyle(color: Colors.white),
                            )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
  }

  /// PayPal Payment Gateway
  void paypalPaymentSheet() {
    // Simulate adding one item to cart (for COD logic preservation)
    double amount = double.tryParse(_amountController.text) ?? 0.0;
    String referenceId = DateTime.now().millisecondsSinceEpoch.toString();

    // You can log or print this info for tracking if needed
    print("Simulated payment - Amount: $amount, Reference ID: $referenceId");

    // Directly simulate success, replacing _flutterPaypalNativePlugin.makeOrder
    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
      content: Text("Payment Successfully" + "\n"),
      backgroundColor: Colors.green,
    ));

    // Continue to next step (e.g., updating wallet or marking payment complete)
    paymentCompleted(paymentMethod: "COD");
  }

  buildPaymentCard(
      {required image,
      PaymentOptionString value = PaymentOptionString.PayTm,
      required String title}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 20),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: paypal ? 0 : 2,
        child: RadioListTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                  color: paypal ? Color(COLOR_PRIMARY) : Colors.transparent)),
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          controlAffinity: ListTileControlAffinity.trailing,
          value: "",
          groupValue: selectedRadioTile,
          onChanged: (String? value) {
            setState(() {
              payTm = false;
              paypal = true;
              selectedRadioTile = value!;
            });
          },
          selected: paypal,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 4.0, horizontal: 10),
                    child: SizedBox(
                        width: 80, height: 40, child: Image.asset(image)),
                  )),
              SizedBox(
                width: 20,
              ),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }

  bool payTm = false;
  bool paypal = false;
  bool flutterWave = false;

  calculateAmount(String amount) {
    final a = (int.parse(amount)) * 100;
    return a.toString();
  }

  /// Paytm Payment Gateway
  bool isStaging = true;
  String callbackUrl =
      "http://162.241.125.167/~foodie/payments/paytmpaymentcallback?ORDER_ID=";
  bool restrictAppInvoke = false;
  bool enableAssist = true;
  String result = "";

  getPaytmCheckSum(
    context, {
    required double amount,
  }) async {
    final String orderId = UserPreference.getPaymentId();
    String getChecksum = "${GlobalURL}payments/getpaytmchecksum";

    final response = await http.post(
        Uri.parse(
          getChecksum,
        ),
        headers: {},
        body: {
          "mid": paytmSettingData?.paytmMID,
          "order_id": orderId,
          "key_secret": paytmSettingData?.paytmMerchantKey,
        });

    final data = jsonDecode(response.body);

    await verifyCheckSum(
            checkSum: data["code"], amount: amount, orderId: orderId)
        .then((value) {
      initiatePayment(context, amount: amount, orderId: orderId).then((value) {
        GetPaymentTxtTokenModel result = value;
        String callback = "";
        if (paytmSettingData!.isSandboxEnabled) {
          callback = callback +
              "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        } else {
          callback = callback +
              "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        }

        _startTransaction(
          context,
          txnTokenBy: result.body.txnToken,
          orderId: orderId,
          amount: amount,
        );
      });
    });
  }

  Future verifyCheckSum(
      {required String checkSum,
      required double amount,
      required orderId}) async {
    String getChecksum = "${GlobalURL}payments/validatechecksum";
    final response = await http.post(
        Uri.parse(
          getChecksum,
        ),
        headers: {},
        body: {
          "mid": paytmSettingData?.paytmMID,
          "order_id": orderId,
          "key_secret": paytmSettingData?.paytmMerchantKey,
          "checksum_value": checkSum,
        });
    final data = jsonDecode(response.body);
    return data['status'];
  }

  Future<GetPaymentTxtTokenModel> initiatePayment(BuildContext context,
      {required double amount, required orderId}) async {
    String initiateURL = "${GlobalURL}payments/initiatepaytmpayment";
    String callback = "";
    if (paytmSettingData!.isSandboxEnabled) {
      callback = callback +
          "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    } else {
      callback = callback +
          "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    }
    final response = await http.post(
        Uri.parse(
          initiateURL,
        ),
        headers: {},
        body: {
          "mid": paytmSettingData?.paytmMID,
          "order_id": orderId,
          "key_secret": paytmSettingData?.paytmMerchantKey.toString(),
          "amount": amount.toString(),
          "currency": currencyModel!.code,
          "callback_url": callback,
          "custId": MyAppState.currentUser!.userID,
          "issandbox": paytmSettingData!.isSandboxEnabled ? "1" : "2",
        });
    final data = jsonDecode(response.body);
    if (data["body"]["txnToken"] == null ||
        data["body"]["txnToken"].toString().isEmpty) {
      Navigator.pop(_scaffoldKey.currentContext!);
      showAlert(_scaffoldKey.currentContext!,
          response: "something went wrong, please contact admin.",
          colors: Colors.red);
    }
    return GetPaymentTxtTokenModel.fromJson(data);
  }

  Future<void> _startTransaction(
    context, {
    required String txnTokenBy,
    required orderId,
    required double amount,
  }) async {
    try {
      // Simulate Paytm transaction delay
      await Future.delayed(Duration(seconds: 1));

      // Simulate a successful response
      bool success = true; // change to false to test failure

      if (success) {
        Navigator.pop(context);
        paymentCompleted(paymentMethod: "Paytm (Simulated)");
      } else {
        throw PlatformException(
            code: 'TXN_FAILED', message: 'Transaction Failed');
      }
    } catch (onError) {
      if (onError is PlatformException) {
        Navigator.pop(_scaffoldKey.currentContext!);

        result = "${onError.message} \n  ${onError.code}";
        showAlert(_scaffoldKey.currentContext!,
            response: onError.message.toString(), colors: Colors.red);
      } else {
        result = onError.toString();
        Navigator.pop(_scaffoldKey.currentContext!);
        showAlert(_scaffoldKey.currentContext!,
            response: result, colors: Colors.red);
      }
    }
  }


  ///FlutterWave Payment Method
  String? _ref;

  setRef() {
    Random numRef = Random();
    int year = DateTime.now().year;
    int refNumber = numRef.nextInt(20000);
    if (Platform.isAndroid) {
      setState(() {
        _ref = "AndroidRef$year$refNumber";
      });
    } else if (Platform.isIOS) {
      setState(() {
        _ref = "IOSRef$year$refNumber";
      });
    }
  }

  Future<void> showLoading(
      {required String message, Color txtColor = Colors.black}) {
    return showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Container(
            margin: EdgeInsets.fromLTRB(30, 20, 30, 20),
            width: double.infinity,
            height: 30,
            child: Text(
              message,
              style: TextStyle(color: txtColor),
            ),
          ),
        );
      },
    );
  }
}

enum PaymentOptionString { PayTm, PayPal, FlutterWave }
