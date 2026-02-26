import 'package:flutter/material.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/view_all_category_product_screen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:geolocator/geolocator.dart';

class HomeRestaurantsSection extends StatelessWidget {
  final List<VendorCategoryModel> categoryWiseProductList;
  final FireStoreUtils fireStoreUtils;

  const HomeRestaurantsSection({
    Key? key,
    required this.categoryWiseProductList,
    required this.fireStoreUtils,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: categoryWiseProductList.length,
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        return StreamBuilder<List<VendorModel>>(
          stream: FireStoreUtils()
              .getCategoryRestaurants(
                  categoryWiseProductList[index].id.toString()),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                ),
              );
            }

            if (snapshot.hasData &&
                (snapshot.data?.isNotEmpty ?? false)) {
              return snapshot.data!.isEmpty
                  ? Container()
                  : Column(
                      children: [
                        HomeSectionUtils.buildTitleRow(
                          titleValue: categoryWiseProductList[index]
                              .title
                              .toString(),
                          onClick: () {
                            push(
                              context,
                              ViewAllCategoryProductScreen(
                                vendorCategoryModel:
                                    categoryWiseProductList[index],
                              ),
                            );
                          },
                          isViewAll: false,
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.height * 0.28,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: ListView.builder(
                              shrinkWrap: true,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: snapshot.data!.length,
                              itemBuilder: (context, index) {
                                VendorModel vendorModel = snapshot.data![index];

                                double distanceInMeters = Geolocator.distanceBetween(
                                    vendorModel.latitude,
                                    vendorModel.longitude,
                                    MyAppState.selectedPosition.location!.latitude,
                                    MyAppState.selectedPosition.location!.longitude);

                                double kilometer = distanceInMeters / 1000;
                                double minutes = 1.2;
                                double value = minutes * kilometer;
                                final int hour = value ~/ 60;
                                final double minute = value % 60;

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      ClickTrackingService.logClick(
                                        userId: MyAppState.currentUser
                                                ?.userID ??
                                            'guest',
                                        restaurantId: vendorModel.id,
                                        source: 'home_restaurants',
                                      );
                                      push(
                                        context,
                                        NewVendorProductsScreen(
                                            vendorModel: vendorModel),
                                      );
                                    },
                                    child: SizedBox(
                                      width: MediaQuery.of(context).size.width * 0.65,
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
                                                    color: Colors.grey.withValues(alpha: 0.5),
                                                    blurRadius: 5,
                                                  ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: Stack(
                                              children: [
                                                // Restaurant image with rating overlay
                                                ClipRRect(
                                                  borderRadius: BorderRadius.only(
                                                      topLeft: Radius.circular(20),
                                                      topRight: Radius.circular(20)),
                                                  child: Image.network(
                                                    getImageVAlidUrl(vendorModel.photo),
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) =>
                                                        Image.network(
                                                      AppGlobal.placeHolderImage!,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  bottom: 10,
                                                  right: 10,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.green,
                                                      borderRadius: BorderRadius.circular(5),
                                                    ),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 5, vertical: 2),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            vendorModel.reviewsCount != 0
                                                                ? (vendorModel.reviewsSum /
                                                                        vendorModel.reviewsCount)
                                                                    .toStringAsFixed(1)
                                                                : 0.toString(),
                                                            style: const TextStyle(
                                                              fontFamily: "Poppinsm",
                                                              letterSpacing: 0.5,
                                                              fontSize: 12,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 3),
                                                          const Icon(
                                                            Icons.star,
                                                            size: 16,
                                                            color: Colors.white,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )),
                                            const SizedBox(height: 5),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 5),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    vendorModel.title,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                        fontFamily: "Poppinsm",
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        letterSpacing: 0.2),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.location_pin,
                                                        color: Color(COLOR_PRIMARY),
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          vendorModel.location,
                                                          maxLines: 1,
                                                          style: TextStyle(
                                                              fontFamily: "Poppinsm",
                                                              color: isDarkMode(context)
                                                                  ? Colors.white
                                                                  : Colors.black.withOpacity(0.60)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.timer_sharp,
                                                        color: Color(COLOR_PRIMARY),
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 5),
                                                      Text(
                                                        '${hour.toString().padLeft(2, "0")}h ${minute.toStringAsFixed(0).padLeft(2, "0")}m',
                                                        style: TextStyle(
                                                            fontFamily: "Poppinsm",
                                                            letterSpacing: 0.5,
                                                            color: isDarkMode(context)
                                                                ? Colors.white
                                                                : Colors.black.withOpacity(0.60)),
                                                      ),
                                                      SizedBox(width: 10),
                                                      Icon(
                                                        Icons.my_location_sharp,
                                                        color: Color(COLOR_PRIMARY),
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 10),
                                                      Text(
                                                        "${kilometer.toDouble().toStringAsFixed(currencyModel!.decimal)} km",
                                                        style: TextStyle(
                                                            fontFamily: "Poppinsm",
                                                            letterSpacing: 0.5,
                                                            color: isDarkMode(context)
                                                                ? Colors.white
                                                                : Colors.black.withOpacity(0.60)),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 5),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
            } else {
              return Container();
            }
          },
        );
      },
    );
  }
}


