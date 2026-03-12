import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/categoryDetailsScreen/CategoryDetailsScreen.dart';
import 'package:foodie_customer/ui/cuisinesScreen/CuisinesScreen.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/AppGlobal.dart';

class HomeCategoriesSection extends StatelessWidget {
  const HomeCategoriesSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Categories",
          onClick: () {
            push(
              context,
              const CuisinesScreen(
                isPageCallFromHomeScreen: true,
              ),
            );
          },
        ),
        Container(
          color: isDarkMode(context)
              ? const Color(DARK_COLOR)
              : const Color(0xffFFFFFF),
          child: FutureBuilder<List<VendorCategoryModel>>(
            future: FireStoreUtils().getCuisines(),
            initialData: const [],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                );
              }

              if ((snapshot.hasData || (snapshot.data?.isNotEmpty ?? false))) {
                return Container(
                  padding: const EdgeInsets.only(left: 10),
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: snapshot.data!.length >= 15
                        ? 15
                        : snapshot.data!.length,
                    itemBuilder: (context, index) {
                      return buildCategoryItem(snapshot.data![index]);
                    },
                  ),
                );
              } else {
                return showEmptyState('No Categories', context);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget buildCategoryItem(VendorCategoryModel model) {
    return Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () {
              push(
                context,
                CategoryDetailsScreen(
                  category: model,
                  isDineIn: false,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(model.photo.toString()),
                  imageBuilder: (context, imageProvider) => Container(
                    height: MediaQuery.of(context).size.height * 0.11,
                    width: MediaQuery.of(context).size.width * 0.23,
                    decoration: BoxDecoration(
                      border: Border.all(width: 6, color: Color(COLOR_PRIMARY)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDarkMode(context)
                              ? const Color(DarkContainerBorderColor)
                              : Colors.grey.shade100,
                          width: 1,
                        ),
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
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          image: DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  memCacheHeight: 280,
                  memCacheWidth: 280,
                  placeholder: (context, url) => ClipOval(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(75 / 1)),
                        border: Border.all(
                          color: Color(COLOR_PRIMARY),
                          style: BorderStyle.solid,
                          width: 2.0,
                        ),
                      ),
                      width: 75,
                      height: 75,
                      child: Icon(
                        Icons.fastfood,
                        color: Color(COLOR_PRIMARY),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: AppGlobal.placeHolderImage!,
                      memCacheWidth: 200,
                      memCacheHeight: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: Text(
                      model.title.toString(),
                      style: TextStyle(
                        color: isDarkMode(context)
                            ? Colors.white
                            : const Color(0xFF000000),
                        fontFamily: "Poppinsr",
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
