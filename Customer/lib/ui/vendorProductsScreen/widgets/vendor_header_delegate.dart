import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/utils/extensions/string_extension.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/common/common_image.dart';
import 'package:foodie_customer/resources/assets.dart';
import 'package:foodie_customer/resources/colors.dart';
import 'package:foodie_customer/model/VendorModel.dart';

import '../../../constants.dart';
import '../../../model/WorkingHoursModel.dart';
import '../../../services/helper.dart';
import 'ficon_button.dart';
import '../../../ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'restaurant_performance_section.dart';

class VendorHeaderDelegate extends SliverPersistentHeaderDelegate {
  final BuildContext context;
  final VendorModel vendorModel;
  final double expandedHeight;
  final bool isOpen;
  final VoidCallback onViewPhotos;
  final Function(String)? onSearchChanged;
  final TextEditingController? searchController;
  final bool hideCollapsedAppBar;
  final int viewingNow;
  final int visitorsThisWeek;

  VendorHeaderDelegate({
    required this.context,
    required this.vendorModel,
    required this.expandedHeight,
    required this.isOpen,
    required this.onViewPhotos,
    this.onSearchChanged,
    this.searchController,
    this.hideCollapsedAppBar = false,
    this.viewingNow = 0,
    this.visitorsThisWeek = 0,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double collapseFactor = shrinkOffset / (maxExtent - minExtent);
    final double opacity = (1 - collapseFactor).clamp(0.0, 1.0);

    // double distanceInMeters = Geolocator.distanceBetween(
    //   vendorModel.latitude,
    //   vendorModel.longitude,
    //   MyAppState.selectedPosition.location!.latitude,
    //   MyAppState.selectedPosition.location!.longitude,
    // );

    // double kilometer = distanceInMeters / 1000;

    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!hideCollapsedAppBar)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: progress,
            child: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0.0,
              leading: FIconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                backgroundColor: Colors.white,
                icon: Icon(
                  Icons.arrow_back,
                  color: Color(COLOR_PRIMARY),
                ),
              ),
              centerTitle: false,
              title: Text(
                vendorModel.title,
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        if (progress <= 0.84)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: 1 - progress,
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Stack(
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 240,
                            width: double.infinity,
                            child: CachedNetworkImage(
                              imageUrl: getImageVAlidUrl(vendorModel.photo),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: CircularProgressIndicator.adaptive(
                                  valueColor: AlwaysStoppedAnimation(
                                      Color(COLOR_PRIMARY)),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  Image.network(placeholderImage,
                                      fit: BoxFit.cover),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        bottom: 8,
                        right: 12,
                        child: IconButton(
                          icon: const Image(
                            image: AssetImage("assets/images/img.png"),
                            height: 50,
                          ),
                          onPressed: onViewPhotos,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: AnimatedOpacity(
                      opacity: opacity,
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 4.0,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        vendorModel.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: "Poppinsm",
                                          fontSize: 20.0,
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode(context)
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildTiming(isOpen),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Stats row: rating + visitor chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (vendorModel.serviceRating != null)
                                Text(
                                  'Food: ${vendorModel.foodRating.toStringAsFixed(1)} | '
                                  'Service: ${vendorModel.serviceRating!.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'Poppinsm',
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xff2A2A2A),
                                  ),
                                )
                              else if (vendorModel.reviewsCount != 0)
                                _StatChip(
                                  icon: Icons.star_rounded,
                                  iconColor: Colors.amber,
                                  label: double.parse((vendorModel.reviewsSum /
                                          vendorModel.reviewsCount)
                                      .toStringAsFixed(1)),
                                  isDark: isDarkMode(context),
                                ),
                              if (viewingNow > 0)
                                _VisitorChip(
                                  icon: Icons.visibility_outlined,
                                  label: '$viewingNow viewing now',
                                  isDark: isDarkMode(context),
                                ),
                              if (visitorsThisWeek > 0)
                                _VisitorChip(
                                  icon: Icons.people_outline,
                                  label: '$visitorsThisWeek this week',
                                  isDark: isDarkMode(context),
                                ),
                            ],
                          ),
                          RestaurantPerformanceSection(vendorModel: vendorModel),
                          RestaurantEtaFeeRow(
                            vendorModel: vendorModel,
                            currencyModel: null,
                          ),
                          const SizedBox(height: 6),
                          // Location
                          Row(
                            spacing: 6,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: isDarkMode(context)
                                    ? Colors.white60
                                    : CustomColors.gray,
                              ),
                              Expanded(
                                child: Text(
                                  vendorModel.location.removeNullWord(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDarkMode(context)
                                        ? Colors.white70
                                        : CustomColors.gray,
                                    fontSize: 13.0,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: "Poppinsr",
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // View Schedule
                          InkWell(
                            onTap: () {
                              showModalBottomSheet(
                                isScrollControlled: true,
                                isDismissible: true,
                                context: context,
                                backgroundColor: Colors.transparent,
                                enableDrag: true,
                                builder: (context) => showTiming(context),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_outlined,
                                    size: 16,
                                    color: Color(COLOR_PRIMARY),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "View Schedule",
                                    style: TextStyle(
                                      fontFamily: "Poppinsm",
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (searchController != null &&
                              onSearchChanged != null)
                            StatefulBuilder(
                              builder: (context, setState) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4.0),
                                  decoration: BoxDecoration(
                                    color: isDarkMode(context)
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: TextField(
                                    controller: searchController,
                                    onChanged: (value) {
                                      setState(() {});
                                      onSearchChanged?.call(value);
                                    },
                                    decoration: InputDecoration(
                                      hintText: "Search menu items...",
                                      hintStyle: TextStyle(
                                        color: isDarkMode(context)
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        fontSize: 14.0,
                                        fontFamily: "Poppinsr",
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: isDarkMode(context)
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        size: 20.0,
                                      ),
                                      suffixIcon: searchController != null &&
                                              searchController!.text.isNotEmpty
                                          ? IconButton(
                                              icon: Icon(
                                                Icons.clear,
                                                color: isDarkMode(context)
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                                size: 20.0,
                                              ),
                                              onPressed: () {
                                                searchController!.clear();
                                                setState(() {});
                                                onSearchChanged?.call("");
                                              },
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 12.0,
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: isDarkMode(context)
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 14.0,
                                      fontFamily: "Poppinsr",
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTiming(bool isOpen) {
    if (isOpen) {
      return Container(
        padding: const EdgeInsets.all(4.0),
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        decoration: BoxDecoration(
          color: const Color(0XFFF1F4F7),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: const Row(
          spacing: 4.0,
          children: [
            Icon(Icons.circle, color: Color(0XFF3dae7d), size: 13),
            Text(
              "Open",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontSize: 12,
                color: Color(0XFF3dae7d),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        height: 35,
        decoration: const BoxDecoration(
          color: Color(0XFFF1F4F7),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomLeft: Radius.circular(10),
          ),
        ),
        padding: const EdgeInsets.only(right: 40, left: 10),
        child: const Row(
          children: [
            Icon(Icons.circle, color: Colors.redAccent, size: 13),
            SizedBox(width: 10),
            Text(
              "Close",
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontSize: 16,
                letterSpacing: 0.5,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      );
    }
  }

  showTiming(BuildContext context) {
    List<WorkingHoursModel> workingHours = vendorModel.workingHours;

    return Container(
        decoration: BoxDecoration(
            color:
                isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        child: Stack(children: [
          SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                      Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.only(top: 15),
                          child: Text(
                            'Restaurant Schedules',
                            style: TextStyle(
                                fontSize: 18,
                                fontFamily: "Poppinsm",
                                color: isDarkMode(context)
                                    ? const Color(0XFFdadada)
                                    : const Color(0XFF252525)),
                          )),
                    ])),
                const SizedBox(
                  height: 10,
                ),
                ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: workingHours.length,
                    itemBuilder: (context, dayIndex) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        child: Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            color: isDarkMode(context)
                                ? const Color(0XFFdadada).withOpacity(0.1)
                                : Colors.grey.shade100,
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        child: Text(
                                          workingHours[dayIndex].day.toString(),
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontFamily: "Poppinsm",
                                              color: isDarkMode(context)
                                                  ? const Color(0XFFdadada)
                                                  : const Color(0XFF252525)),
                                        ),
                                      ),
                                      Visibility(
                                        visible: workingHours[dayIndex]
                                            .timeslot!
                                            .isEmpty,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 15),
                                          child: Container(
                                              height: 35,
                                              decoration: BoxDecoration(
                                                  border: Border.all(
                                                      color:
                                                          Colors.grey.shade400,
                                                      width: 1.5),
                                                  color: isDarkMode(context)
                                                      ? Colors.white
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              padding: const EdgeInsets.only(
                                                  right: 15, left: 10),
                                              child: Row(children: [
                                                const Icon(
                                                  Icons.circle,
                                                  color: Colors.redAccent,
                                                  size: 11,
                                                ),
                                                const SizedBox(
                                                  width: 5,
                                                ),
                                                Text("Closed",
                                                    style: const TextStyle(
                                                        fontFamily: "Poppinsm",
                                                        color:
                                                            Colors.redAccent))
                                              ])),
                                        ),
                                      )
                                    ],
                                  ),
                                  Visibility(
                                    visible: workingHours[dayIndex]
                                        .timeslot!
                                        .isNotEmpty,
                                    child: ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        shrinkWrap: true,
                                        itemCount: workingHours[dayIndex]
                                            .timeslot!
                                            .length,
                                        itemBuilder: (context, slotIndex) {
                                          return buildTimeCard(
                                              timeslot: workingHours[dayIndex]
                                                  .timeslot![slotIndex]);
                                        }),
                                  ),
                                ],
                              ),
                            )),
                      );
                    }),
                const SizedBox(
                  height: 10,
                ),
              ],
            ),
          ),
          Positioned(
              right: 10,
              top: 5,
              child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child:

                      // Padding(padding: EdgeInsets.only(right: 5,top: 5,left: 15,bottom: 20),

                      // child:

                      const CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(0XFFF1F4F7),
                          child: Image(
                            image: AssetImage("assets/images/cancel.png"),
                            height: 35,
                          ))))
        ]));
  }

  buildTimeCard({required Timeslot timeslot}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: isDarkMode(context)
                  ? const Color(0XFF3c3a2e)
                  : const Color(0XFFC3C5D1),
              width: 1,
            ),
          ),
          child: Padding(
              padding:
                  const EdgeInsets.only(top: 7, bottom: 7, left: 20, right: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text("From",
                      style: TextStyle(
                          fontFamily: "Poppinsr",
                          color: isDarkMode(context)
                              ? const Color(0XFFa5a292)
                              : const Color(0xff5A5D6D))),

                  //  SizedBox(height: 5,),

                  Text(" " + timeslot.from.toString(),
                      style: TextStyle(
                          fontFamily: "Poppinsm",
                          color: isDarkMode(context)
                              ? const Color(0XFFa5a292)
                              : const Color(0XFF5A5D6D)))
                ],
              )),
        ),
        const SizedBox(
          width: 20,
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: isDarkMode(context)
                  ? const Color(0XFF3c3a2e)
                  : const Color(0XFFC3C5D1),
              width: 1,
            ),
          ),
          child: Padding(
              padding:
                  const EdgeInsets.only(top: 7, bottom: 7, left: 20, right: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text("To",
                      style: TextStyle(
                          fontFamily: "Poppinsr",
                          color: isDarkMode(context)
                              ? const Color(0XFFa5a292)
                              : const Color(0xff5A5D6D))),

                  //  SizedBox(height: 5,),

                  Text(" " + timeslot.to.toString(),
                      style: TextStyle(
                          fontFamily: "Poppinsm",
                          color: isDarkMode(context)
                              ? const Color(0XFFa5a292)
                              : const Color(0XFF5A5D6D)))
                ],
              )),
        ),
      ],
    );
  }

  @override
  double get maxExtent => 440;

  @override
  double get minExtent => kToolbarHeight + 20;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final num label;
  final bool isDark;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.shade200,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label.toString(),
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xff2A2A2A),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitorChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _VisitorChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color(COLOR_PRIMARY).withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Color(COLOR_PRIMARY)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
