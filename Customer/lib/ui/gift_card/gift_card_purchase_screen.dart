import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/gift_cards_model.dart';
import 'package:foodie_customer/model/gift_cards_order_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:uuid/uuid.dart';

class GiftCardPurchaseScreen extends StatefulWidget {
  final GiftCardsModel giftCardModel;
  final String price;
  final String msg;

  const GiftCardPurchaseScreen({
    super.key,
    required this.giftCardModel,
    required this.price,
    required this.msg,
  });

  @override
  State<GiftCardPurchaseScreen> createState() => _GiftCardPurchaseScreenState();
}

class _GiftCardPurchaseScreenState extends State<GiftCardPurchaseScreen> {
  GiftCardsModel giftCardModel = GiftCardsModel();
  String gradTotal = "0";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    giftCardModel = widget.giftCardModel;
    gradTotal = widget.price;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text("Complete purchase",
            style: TextStyle(
                color: Color(COLOR_PRIMARY),
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white, width: 5),
                  image: DecorationImage(
                    fit: BoxFit.cover,
                    image: NetworkImage(giftCardModel.image ?? ''),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Color(COLOR_PRIMARY).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Text(
                    "Complete payment and share this e-gift card with loved ones using any app.",
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text("BILL SUMMARY".toUpperCase(),
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade100, width: 1),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Subtotal",
                              style: TextStyle(fontFamily: "Poppinsm")),
                          Text(amountShow(amount: widget.price),
                              style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  color: Color(0xff333333))),
                        ],
                      ),
                    ),
                    const Divider(thickness: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Grand Total",
                              style: TextStyle(fontFamily: "Poppinsm")),
                          Text(amountShow(amount: widget.price),
                              style: TextStyle(
                                  fontFamily: "Poppinsm", color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "Gift Card expires in ${giftCardModel.expiryDay} days after purchase",
                style: TextStyle(color: Colors.grey),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding:
            const EdgeInsets.only(right: 40.0, left: 40.0, top: 10, bottom: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
            child: Text(
              'Confirm COD Purchase',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            onPressed: () {
              paymentCompleted(paymentMethod: "Cash on Delivery");
            },
          ),
        ),
      ),
    );
  }

  paymentCompleted({required String paymentMethod}) async {
    GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel();
    giftCardsOrderModel.id = Uuid().v4();
    giftCardsOrderModel.giftId = giftCardModel.id.toString();
    giftCardsOrderModel.giftTitle = giftCardModel.title.toString();
    giftCardsOrderModel.price = gradTotal.toString();
    giftCardsOrderModel.redeem = false;
    giftCardsOrderModel.message = widget.msg;
    giftCardsOrderModel.giftPin = generateGiftPin();
    giftCardsOrderModel.giftCode = generateGiftCode();
    giftCardsOrderModel.paymentType = paymentMethod;
    giftCardsOrderModel.createdDate = Timestamp.now();
    DateTime dateTime = DateTime.now()
        .add(Duration(days: int.parse(giftCardModel.expiryDay.toString())));
    giftCardsOrderModel.expireDate = Timestamp.fromDate(dateTime);
    giftCardsOrderModel.userid = MyAppState.currentUser!.userID;

    await FireStoreUtils()
        .placeGiftCardOrder(giftCardsOrderModel)
        .then((value) {
      Navigator.pop(context);
    });
  }

  String generateGiftCode() {
    var rng = Random();
    return List.generate(16, (_) => rng.nextInt(9) + 1).join();
  }

  String generateGiftPin() {
    var rng = Random();
    return List.generate(6, (_) => rng.nextInt(9) + 1).join();
  }
}
