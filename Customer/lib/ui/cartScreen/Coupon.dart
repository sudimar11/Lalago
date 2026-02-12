import 'package:flutter/material.dart';


import 'package:dotted_border/dotted_border.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';


class CouponCodeScreen extends StatefulWidget {

  final dynamic per;


  const CouponCodeScreen(this.per, {Key? key}) : super(key: key);


  @override

  _CouponCodeScreenState createState() => _CouponCodeScreenState();

}


class _CouponCodeScreenState extends State<CouponCodeScreen> {

  late Future<List<OfferModel>> coupon;


  TextEditingController txt = TextEditingController();


  FireStoreUtils _fireStoreUtils = FireStoreUtils();


  var percentage, type;


  @override

  void initState() {

    super.initState();


    coupon = _fireStoreUtils.getAllCoupons();

  }


  @override

  Widget build(BuildContext context) {

    double _height = MediaQuery.of(context).size.height;


    return Container(

      padding: EdgeInsets.only(bottom: _height / 3.6, left: 25, right: 25),

      height: MediaQuery.of(context).size.height * 0.90,

      decoration: BoxDecoration(

        color: Colors.transparent,

        border: Border.all(style: BorderStyle.none),

      ),

      child: FutureBuilder<List<OfferModel>>(

        future: coupon, // Use List<OfferModel>

        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {

            return Center(

              child: CircularProgressIndicator.adaptive(

                valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),

              ),

            );

          }


          if (!snapshot.hasData || snapshot.data!.isEmpty) {

            return Center(

              child: Column(

                mainAxisAlignment: MainAxisAlignment.center,

                children: [

                  Icon(Icons.fastfood, size: 80, color: Colors.grey),

                  const SizedBox(height: 16),

                  Text(

                    'No Previous Orders',

                    style: const TextStyle(

                        fontSize: 18, fontWeight: FontWeight.bold),

                    textAlign: TextAlign.center,

                  ),

                  const SizedBox(height: 8),

                  Text(

                    'Let\'s order food!',

                    style: const TextStyle(fontSize: 14, color: Colors.grey),

                    textAlign: TextAlign.center,

                  ),

                ],

              ),

            );

          }


          return Column(

            children: [

              InkWell(

                onTap: () => Navigator.pop(context),

                child: Container(

                  height: 45,

                  decoration: BoxDecoration(

                    border: Border.all(color: Colors.white, width: 0.3),

                    color: Colors.transparent,

                    shape: BoxShape.circle,

                  ),

                  child: const Center(

                    child: Icon(

                      Icons.close,

                      color: Colors.white,

                      size: 28,

                    ),

                  ),

                ),

              ),

              const SizedBox(height: 25),

              Expanded(

                child: Container(

                  decoration: BoxDecoration(

                    borderRadius: BorderRadius.circular(10),

                    color: Colors.white,

                  ),

                  alignment: Alignment.center,

                  child: Column(

                    children: [

                      Container(

                        padding: const EdgeInsets.only(top: 40),

                        child: Image.asset(

                          'assets/images/redeem_coupon.png',

                          width: 100,

                        ),

                      ),

                      const SizedBox(height: 30),

                      Text(

                        'Redeem Your Coupons',

                        style: const TextStyle(fontFamily: 'Poppinsm'),

                      ),

                      const SizedBox(height: 30),

                      Text(

                        "EnterVoucherCoupon" +

                            '\nget the discount on all over the budget',

                        style: const TextStyle(fontFamily: 'Poppinsl'),

                        textAlign: TextAlign.center,

                      ),

                      const SizedBox(height: 40),

                      Padding(

                        padding: const EdgeInsets.symmetric(horizontal: 20),

                        child: DottedBorder(

                          borderType: BorderType.RRect,

                          radius: const Radius.circular(12),

                          dashPattern: const [4, 4],

                          child: ClipRRect(

                            borderRadius:

                                const BorderRadius.all(Radius.circular(12)),

                            child: Center(

                              child: TextFormField(

                                textAlign: TextAlign.center,

                                controller: txt,

                                decoration: const InputDecoration(

                                  border: InputBorder.none,

                                  hintText: 'Write Coupon Code',

                                ),

                              ),

                            ),

                          ),

                        ),

                      ),

                      const SizedBox(height: 40),

                      ElevatedButton(

                        style: ElevatedButton.styleFrom(

                          padding: const EdgeInsets.symmetric(

                              horizontal: 100, vertical: 15),

                          backgroundColor: Color(COLOR_PRIMARY),

                          shape: RoundedRectangleBorder(

                            borderRadius: BorderRadius.circular(8),

                          ),

                        ),

                        onPressed: () {

                          setState(() {

                            Navigator.pop(context);

                          });

                        },

                        child: Text(

                          'REDEEM NOW',

                          style: TextStyle(

                            color: isDarkMode(context)

                                ? Colors.black

                                : Colors.white,

                            fontWeight: FontWeight.bold,

                            fontSize: 16,

                          ),

                        ),

                      ),

                    ],

                  ),

                ),

              ),

              ListView.builder(

                shrinkWrap: true,

                itemCount: snapshot.data!.length,

                itemBuilder: (context, index) {

                  final offerModel = snapshot.data![index];

                  return buildCouponItem(offerModel as Map<String, dynamic>);

                },

              ),

            ],

          );

        },

      ),

    );

  }


  Widget buildCouponItem(Map<String, dynamic> couponData) {

    try {

      final String code = couponData['code'] ?? '';

      final bool isEnabled = couponData['isEnable'] ?? false;

      final String discountType = couponData['discountType'] ?? '';

      final double discount = (couponData['discount'] ?? 0).toDouble();


      if (txt.text == code || isEnabled) {

        if (discountType == 'Percent') {

          percentage = discount;

          print('Discount Percentage: $discount');

        } else if (discountType == 'fixed') {

          type = discount;

          print('Fixed Discount: $discount');

        }

      } else {

        print("No applicable offer for the entered code.");

      }

    } catch (e) {

      print("Error processing coupon data: $e");

    }


    return const SizedBox.shrink();

  }

}

