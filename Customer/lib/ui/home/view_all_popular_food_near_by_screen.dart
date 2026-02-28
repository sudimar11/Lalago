import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../AppGlobal.dart';
import '../../constants.dart';
import '../vendorProductsScreen/NewVendorProductsScreen.dart';

class ViewAllPopularFoodNearByScreen extends StatefulWidget {
  const ViewAllPopularFoodNearByScreen({Key? key}) : super(key: key);

  @override
  _ViewAllPopularFoodNearByScreenState createState() =>
      _ViewAllPopularFoodNearByScreenState();
}

class _ViewAllPopularFoodNearByScreenState
    extends State<ViewAllPopularFoodNearByScreen> {
  late Stream<List<VendorModel>> vendorsFuture;
  StreamSubscription<List<VendorModel>>? _storeSubscription;
  final fireStoreUtils = FireStoreUtils();
  Stream<List<VendorModel>>? lstAllStore;
  late Future<List<ProductModel>> productsFuture;
  List<ProductModel> lstNearByFood = [];
  List<VendorModel> vendors = [];
  bool showLoader = true;
  String? selctedOrderTypeValue = "Delivery";
  VendorModel? popularNearFoodVendorModel;
  int totItem = 0;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getFoodType();
    fireStoreUtils.getRestaurantNearBy().whenComplete(() {
      lstAllStore = fireStoreUtils.getAllRestaurants().asBroadcastStream();
      _storeSubscription = lstAllStore!.listen((event) {
        vendors.clear();
        vendors.addAll(event);
      });
      if (selctedOrderTypeValue == "Delivery") {
        productsFuture = fireStoreUtils.getAllDelevryProducts();
      } else {
        productsFuture = fireStoreUtils.getAllTakeAWayProducts();
      }

      productsFuture.then((value) {
        // Create a map of vendor ID to vendor for quick lookup
        Map<String, VendorModel> vendorMap = {};
        for (var vendor in vendors) {
          vendorMap[vendor.id] = vendor;
        }

        // Filter products to only include those from open restaurants
        for (var product in value) {
          VendorModel? vendor = vendorMap[product.vendorID];

          if (vendor != null) {
            bool isOpen = isRestaurantOpen(vendor);

            // Only add products from open restaurants
            if (isOpen) {
              lstNearByFood.add(product);
            }
          }
        }

        if (mounted) {
          setState(() => showLoader = false);
        }
      });
    });
  }

  @override
  void dispose() {
    _storeSubscription?.cancel();
    super.dispose();
  }

  getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    setState(() {
      selctedOrderTypeValue =
          sp.getString("foodType") == "" || sp.getString("foodType") == null
              ? "Delivery"
              : sp.getString("foodType");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppGlobal.buildAppBar(context, "Top Selling"),
      body: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
        child: showLoader
            ? Center(
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                ),
              )
            : lstNearByFood.isEmpty
                ? showEmptyState('No top selling found', context)
                : ListView.builder(
                    shrinkWrap: true,
                    scrollDirection: Axis.vertical,
                    physics: const BouncingScrollPhysics(),
                    itemCount: lstNearByFood.length,
                    itemBuilder: (context, index) {
                      if (vendors.isNotEmpty) {
                        // For each product, find its vendor
                        popularNearFoodVendorModel = null;
                        for (int a = 0; a < vendors.length; a++) {
                          if (vendors[a].id == lstNearByFood[index].vendorID) {
                            popularNearFoodVendorModel = vendors[a];
                          }
                        }
                      }

                      return popularNearFoodVendorModel == null
                          ? (totItem == 0 &&
                                  index == (lstNearByFood.length - 1))
                              ? showEmptyState(
                                  'No top selling found', context)
                              : Container()
                          : buildVendorItemData(
                              context, index, popularNearFoodVendorModel!);
                    }),
      ),
    );
  }

  Widget buildVendorItemData(
      BuildContext context, int index, VendorModel popularNearFoodVendorModel) {
    totItem++;
    return GestureDetector(
      onTap: () {
        push(
          context,
          NewVendorProductsScreen(vendorModel: popularNearFoodVendorModel),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        width: MediaQuery.of(context).size.width * 0.8,
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: getImageVAlidUrl(lstNearByFood[index].photo),
                height: 100,
                width: 100,
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(
                        image: imageProvider, fit: BoxFit.cover),
                  ),
                ),
                placeholder: (context, url) => Center(
                    child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                )),
                errorWidget: (context, url, error) => ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: CachedNetworkImage(
                      imageUrl: AppGlobal.placeHolderImage!,
                      memCacheWidth: 200,
                      memCacheHeight: 200,
                      fit: BoxFit.cover,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                    )),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lstNearByFood[index].name,
                    style: const TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 18,
                      color: Color(0xff000000),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    lstNearByFood[index].description,
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 16,
                      color: Color(0xff9091A4),
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  lstNearByFood[index].disPrice == "" ||
                          lstNearByFood[index].disPrice == "0"
                      ? Text(
                          amountShow(amount: lstNearByFood[index].price),
                          style: TextStyle(
                              fontSize: 16,
                              fontFamily: "Poppinsm",
                              letterSpacing: 0.5,
                              color: Color(COLOR_PRIMARY)),
                        )
                      : Row(
                          children: [
                            Text(
                              "${amountShow(amount: lstNearByFood[index].disPrice)}",
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Text(
                              '${amountShow(amount: lstNearByFood[index].price)}',
                              style: const TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough),
                            ),
                          ],
                        ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  bool isRestaurantOpen(VendorModel vendorModel) {
    final now = DateTime.now();
    var day = DateFormat('EEEE', 'en_US').format(now);
    var date = DateFormat('dd-MM-yyyy').format(now);

    bool isOpen = false;

    for (var workingHour in vendorModel.workingHours) {
      if (day == workingHour.day.toString()) {
        if (workingHour.timeslot != null && workingHour.timeslot!.isNotEmpty) {
          for (var timeSlot in workingHour.timeslot!) {
            var start = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.from.toString());
            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.to.toString());

            if (isCurrentDateInRange(start, end)) {
              isOpen = true;
              break;
            }
          }
        }
        if (isOpen) break;
      }
    }

    return isOpen && vendorModel.reststatus;
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }
}
