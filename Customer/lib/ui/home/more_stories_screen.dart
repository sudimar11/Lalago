import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/story_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:story_view/story_view.dart';

class MoreStories extends StatefulWidget {
  List<StoryModel> storyList = [];
  int index;

  MoreStories({Key? key, required this.index, required this.storyList})
      : super(key: key);

  @override
  _MoreStoriesState createState() => _MoreStoriesState();
}

class _MoreStoriesState extends State<MoreStories> {
  final storyController = StoryController();

  @override
  void dispose() {
    storyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          StoryView(
            storyItems: List.generate(
              widget.storyList[widget.index].videoUrl.length,
              (i) {
                return StoryItem.pageVideo(
                  widget.storyList[widget.index].videoUrl[i],
                  controller: storyController,
                );
              },
            ).toList(),
            onStoryShow: (story, index) {
            },
            onComplete: () {

              if (widget.storyList.length - 1 != widget.index) {
                if (!mounted) return;
                setState(() {
                  widget.index = widget.index + 1;
                });
              } else {
                Navigator.pop(context);
              }
            },
            progressPosition: ProgressPosition.top,
            repeat: true,
            controller: storyController,
            onVerticalSwipeComplete: (direction) {
              if (direction == Direction.down) {
                Navigator.pop(context);
              }
            },
          ),
          FutureBuilder(
            future: FireStoreUtils().getVendorByVendorID(
                widget.storyList[widget.index].vendorID.toString()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: Container());
              } else {
                if (snapshot.hasError) {
                  return Center(
                      child: Text("Error" + ": ${snapshot.error}"));
                } else {
                  VendorModel? vendorModel = snapshot.data;

                  double distanceInMeters = Geolocator.distanceBetween(
                      vendorModel!.latitude,
                      vendorModel.longitude,
                      MyAppState.selectedPosition.location!.latitude,
                      MyAppState.selectedPosition.location!.longitude);

                  double kilometer = distanceInMeters / 1000;

                  return Positioned(
                    top: 55,
                    child: InkWell(
                      onTap: () {
                        push(
                          context,
                          NewVendorProductsScreen(vendorModel: vendorModel),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: CachedNetworkImage(
                                imageUrl: vendorModel.photo,
                                height: 50,
                                width: 50,
                                imageBuilder: (context, imageProvider) =>
                                    Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    image: DecorationImage(
                                        image: imageProvider,
                                        fit: BoxFit.cover),
                                  ),
                                ),
                                placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator.adaptive(
                                  valueColor: AlwaysStoppedAnimation(
                                      Color(COLOR_PRIMARY)),
                                )),
                                errorWidget: (context, url, error) => ClipRRect(
                                    borderRadius: BorderRadius.circular(30),
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
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vendorModel.title.toString(),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
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
                                                          vendorModel
                                                              .reviewsCount)
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
                                    const SizedBox(width: 5),
                                    Icon(
                                      Icons.location_pin,
                                      size: 16,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      "${kilometer.toDouble().toStringAsFixed(currencyModel!.decimal)} KM",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: "Poppinsr"),
                                    ),
                                    const SizedBox(width: 5),
                                    Container(
                                      height: 15,
                                      child: const VerticalDivider(
                                        color: Colors.white,
                                        thickness: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      DateTime.now()
                                                  .difference(widget
                                                      .storyList[widget.index]
                                                      .createdAt!
                                                      .toDate())
                                                  .inDays ==
                                              0
                                          ? 'Today'
                                          : "${DateTime.now().difference(widget.storyList[widget.index].createdAt!.toDate()).inDays.toString()} d",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: "Poppinsr"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
