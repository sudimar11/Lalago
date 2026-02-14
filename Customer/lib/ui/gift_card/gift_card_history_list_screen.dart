import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/gift_cards_order_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';

class GiftCardHistoryListScreen extends StatefulWidget {
  const GiftCardHistoryListScreen({super.key});

  @override
  State<GiftCardHistoryListScreen> createState() => _GiftCardHistoryListScreenState();
}

class _GiftCardHistoryListScreenState extends State<GiftCardHistoryListScreen> {
  @override
  void initState() {
    // TODO: implement initState
    getList();
    super.initState();
  }

  List<GiftCardsOrderModel> giftCardsOrderList = [];

  bool isLoading = true;

  getList() async {
    await FireStoreUtils().getGiftHistory().then((value) {
      setState(() {
        giftCardsOrderList = value;
      });
    });
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text("History", style: TextStyle(color: Color(COLOR_PRIMARY), fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: isLoading == true
          ? Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: giftCardsOrderList.isEmpty
                  ? Center(
                      child: Text("No History Found "),
                    )
                  : ListView.builder(
                      itemCount: giftCardsOrderList.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        GiftCardsOrderModel giftCardOrderModel = giftCardsOrderList[index];
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            decoration: BoxDecoration(color: isDarkMode(context) ? Color(DarkContainerColor) : Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          giftCardOrderModel.giftTitle.toString(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        giftCardOrderModel.redeem == true ? "Redeemed" : "Not Redeem",
                                        style: TextStyle(
                                          color: giftCardOrderModel.redeem == true ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 10,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Gift code".toUpperCase(),
                                          style: TextStyle(
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        giftCardOrderModel.giftCode.toString().replaceAllMapped(RegExp(r".{4}"), (match) => "${match.group(0)} "),
                                        style: TextStyle(
                                          color: isDarkMode(context) ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Gift Pin".toUpperCase(),
                                          style: TextStyle(
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      giftCardOrderModel.isPasswordShow == true
                                          ? Text(
                                              giftCardOrderModel.giftPin.toString(),
                                              style: TextStyle(
                                                color: isDarkMode(context) ? Colors.white : Colors.black,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            )
                                          : Text(
                                              "****",
                                              style: TextStyle(
                                                color: isDarkMode(context) ? Colors.white : Colors.black,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      giftCardOrderModel.isPasswordShow == true
                                          ? InkWell(
                                              onTap: () {
                                                setState(() {
                                                  giftCardOrderModel.isPasswordShow = false;
                                                });
                                              },
                                              child: Icon(Icons.visibility_off))
                                          : InkWell(
                                              onTap: () {
                                                setState(() {
                                                  giftCardOrderModel.isPasswordShow = true;
                                                });
                                              },
                                              child: Icon(Icons.remove_red_eye)),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        amountShow(amount: giftCardOrderModel.price.toString()),
                                        style: TextStyle(
                                          color: isDarkMode(context)
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
