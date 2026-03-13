import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widgets/native_ad_restaurant_card.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:intl/intl.dart';

class ViewAllRestaurant extends StatefulWidget {
  const ViewAllRestaurant({Key? key}) : super(key: key);

  @override
  State<ViewAllRestaurant> createState() => _ViewAllRestaurantState();
}

class _ViewAllRestaurantState extends State<ViewAllRestaurant> {
  List<VendorModel> vendors = [];
  StreamSubscription<List<DocumentSnapshot>>? _geoSubscription;
  bool isLoading = true;

  void getProducts() {
    setState(() {
      isLoading = true;
    });
    var collectionReference = FireStoreUtils.firestore.collection(VENDORS);

    GeoFirePoint center = GeoFlutterFire().point(
        latitude: MyAppState.selectedPosition.location!.latitude,
        longitude: MyAppState.selectedPosition.location!.longitude);
    String field = 'g';

    Stream<List<DocumentSnapshot>> stream = GeoFlutterFire()
        .collection(collectionRef: collectionReference)
        .within(
            center: center,
            radius: radiusValue,
            field: field,
            strictMode: true);
    _geoSubscription = stream.listen((List<DocumentSnapshot> documentList) {
      if (mounted) {
        setState(() {
          vendors.clear();
          for (var document in documentList) {
            final data = document.data() as Map<String, dynamic>;
            vendors.add(VendorModel.fromJson(data));
          }
        });
      }
    });
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    // Cancel geo stream subscription to prevent memory leaks
    _geoSubscription?.cancel();
    super.dispose();
  }

  late Future<List<FavouriteModel>> lstFavourites;

  getData() {
    if (MyAppState.currentUser != null) {
      lstFavourites = FireStoreUtils()
          .getFavouriteRestaurant(MyAppState.currentUser!.userID);
      lstFavourites.then((event) {
        lstFav.clear();
        for (int a = 0; a < event.length; a++) {
          lstFav.add(event[a].restaurantId!);
        }
      });
    }
  }

  List<String> lstFav = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppGlobal.buildAppBar(context, "All Restaurant"),
      body: Column(
        children: [
          Expanded(
            child: vendors.isEmpty
                ? Center(
                    child: const Text('No Data...'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    scrollDirection: Axis.vertical,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount:
                        vendors.length + (vendors.length / 5).floor(),
                    itemBuilder: (context, index) {
                      if ((index + 1) % 6 == 0) {
                        return KeyedSubtree(
                          key: ValueKey('ad_$index'),
                          child: const NativeAdRestaurantCard(),
                        );
                      }
                      final restaurantIndex =
                          index - (index + 1) ~/ 6;
                      if (restaurantIndex >= vendors.length) {
                        return KeyedSubtree(
                          key: ValueKey('gap_$index'),
                          child: const SizedBox.shrink(),
                        );
                      }
                      return KeyedSubtree(
                        key: ValueKey(vendors[restaurantIndex].id),
                        child: buildAllRestaurantsData(
                            vendors[restaurantIndex]),
                      );
                    },
                  ),
          ),
          isLoading
              ? Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                )
              : const SizedBox.shrink()
        ],
      ),
    );
  }

  Widget buildAllRestaurantsData(VendorModel vendorModel) {
    bool restaurantIsOpen = isRestaurantOpen(vendorModel);

    return GestureDetector(
      onTap: () => push(
        context,
        NewVendorProductsScreen(vendorModel: vendorModel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
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
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: getImageVAlidUrl(vendorModel.photo),
                          height: 100,
                          width: 100,
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          imageBuilder: (context, imageProvider) => Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              image: DecorationImage(
                                  image: imageProvider, fit: BoxFit.cover),
                            ),
                          ),
                          placeholder: (context, url) => Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Icon(Icons.image,
                                  color: Colors.grey,
                                  size: 30),
                            ),
                          ),
                          errorWidget: (context, url, error) => ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: AppGlobal.placeHolderImage!,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                fit: BoxFit.cover,
                              )),
                          fit: BoxFit.cover,
                        ),
                      ],
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  vendorModel.title,
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (MyAppState.currentUser == null) {
                                    push(context, LoginScreen());
                                  } else {
                                    setState(() {
                                      if (lstFav.contains(vendorModel.id) ==
                                          true) {
                                        FavouriteModel favouriteModel =
                                            FavouriteModel(
                                                restaurantId: vendorModel.id,
                                                userId: MyAppState
                                                    .currentUser!.userID);
                                        lstFav.removeWhere(
                                            (item) => item == vendorModel.id);
                                        FireStoreUtils()
                                            .removeFavouriteRestaurant(
                                                favouriteModel);
                                      } else {
                                        FavouriteModel favouriteModel =
                                            FavouriteModel(
                                                restaurantId: vendorModel.id,
                                                userId: MyAppState
                                                    .currentUser!.userID);
                                        FireStoreUtils().setFavouriteRestaurant(
                                            favouriteModel);
                                        lstFav.add(vendorModel.id);
                                      }
                                    });
                                  }
                                },
                                child: lstFav.contains(vendorModel.id) == true
                                    ? Icon(
                                        Icons.favorite,
                                        color: Color(COLOR_PRIMARY),
                                      )
                                    : Icon(
                                        Icons.favorite_border,
                                        color: isDarkMode(context)
                                            ? Colors.white38
                                            : Colors.black38,
                                      ),
                              )
                            ],
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          // Text("Min" + " ${discountAmountTempList.isNotEmpty ? discountAmountTempList.reduce(min).toStringAsFixed(0) : 0}% " + "off",
                          //     maxLines: 1,
                          //     style: TextStyle(
                          //       fontFamily: "Poppinsm",
                          //       letterSpacing: 0.5,
                          //       color: isDarkMode(context) ? Colors.white60 : const Color(0xff555353),
                          //     )),
                          // const SizedBox(
                          //   height: 10,
                          // ),
                          Row(
                            children: [
                              Icon(
                                Icons.location_pin,
                                size: 20,
                                color: Color(COLOR_PRIMARY),
                              ),
                              Expanded(
                                child: Text(
                                  vendorModel.location,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    color: isDarkMode(context)
                                        ? Colors.white70
                                        : const Color(0xff9091A4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.star,
                                size: 20,
                                color: Color(COLOR_PRIMARY),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                  vendorModel.reviewsCount != 0
                                      ? (vendorModel.reviewsSum /
                                              vendorModel.reviewsCount)
                                          .toStringAsFixed(1)
                                      : 0.toString(),
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    letterSpacing: 0.5,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xff000000),
                                  )),
                              const SizedBox(width: 3),
                              Text(
                                  '(${vendorModel.reviewsCount.toStringAsFixed(1)})',
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    letterSpacing: 0.5,
                                    color: isDarkMode(context)
                                        ? Colors.white60
                                        : const Color(0xff666666),
                                  )),
                              const SizedBox(width: 5),
                            ],
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              // Overlay for closed restaurants
              if (!restaurantIsOpen)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black.withOpacity(0.6),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Temporarily Closed',
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (getNextOpeningTimeText(vendorModel) != null)
                            ...[
                              const SizedBox(height: 4),
                              Text(
                                getNextOpeningTimeText(vendorModel)!,
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontSize: 12,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    getRadius();
    getData();
  }

  getRadius() async {
    await FireStoreUtils().getRestaurantNearBy().then((value) {
      if (value != null) {
        getProducts();
      }
    });
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
