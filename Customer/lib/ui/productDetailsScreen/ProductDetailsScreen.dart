import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_rating_bar/flutter_rating_bar.dart';

// import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/common/common_cachend_network_image.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/common/common_image.dart';

import 'package:foodie_customer/constants.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/AttributesModel.dart';

import 'package:foodie_customer/model/FavouriteItemModel.dart';

import 'package:foodie_customer/model/ItemAttributes.dart';

import 'package:foodie_customer/model/ProductModel.dart';

import 'package:foodie_customer/model/Ratingmodel.dart';

import 'package:foodie_customer/model/ReviewAttributeModel.dart';

import 'package:foodie_customer/model/VendorModel.dart';

import 'package:foodie_customer/model/variant_info.dart';

import 'package:foodie_customer/services/FirebaseHelper.dart';

import 'package:foodie_customer/services/Indicator.dart';

import 'package:foodie_customer/services/helper.dart';

import 'package:foodie_customer/services/localDatabase.dart';

import 'package:foodie_customer/ui/login/LoginScreen.dart';

import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';

import 'package:foodie_customer/ui/container/ContainerScreen.dart';

import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

import 'package:foodie_customer/ui/vendorProductsScreen/review.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../common/common_expandable_text.dart';
import '../../resources/assets.dart';
import '../../resources/colors.dart';
import '../../widget/shimmer_widgets.dart';
import '../../widgets/add_icon_button.dart';
import '../home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/model/addon_promo_model.dart';
import 'package:foodie_customer/services/addon_promo_service.dart';
import 'package:foodie_customer/ui/addon/addon_promo_card.dart';

class ProductDetailsScreen extends StatefulWidget {
  final ProductModel productModel;

  final VendorModel vendorModel;

  const ProductDetailsScreen(
      {Key? key, required this.productModel, required this.vendorModel})
      : super(key: key);

  @override
  _ProductDetailsScreenState createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late CartDatabase cartDatabase;

  String radioItem = '';

  int id = -1;

  List<AddAddonsDemo> lstAddAddonsCustom = [];

  List<AddAddonsDemo> lstTemp = [];

  double priceTemp = 0.0, lastPrice = 0.0;

  int productQnt = 0;

  List<String> productImage = [];

  List<Attributes>? attributes = [];

  List<Variants>? variants = [];

  List<String> selectedVariants = [];

  List<String> selectedIndexVariants = [];

  List<String> selectedIndexArray = [];

  bool isOpen = false;

  statusCheck() {
    final now = DateTime.now();

    var day = DateFormat('EEEE', 'en_US').format(now);

    var date = DateFormat('dd-MM-yyyy').format(now);

    for (var element in widget.vendorModel.workingHours) {
      if (day == element.day.toString()) {
        if (element.timeslot!.isNotEmpty) {
          for (var element in element.timeslot!) {
            var start = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + element.from.toString());

            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + element.to.toString());

            if (isCurrentDateInRange(start, end)) {
              setState(() {
                isOpen = true;
              });
            }
          }
        }
      }
    }
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();

    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  @override
  void initState() {
    super.initState();

    print("product Id ---->${widget.productModel.id}");

    // productQnt = widget.productModel.quantity;

    getAddOnsData();

    statusCheck();

    if (widget.productModel.itemAttributes != null) {
      attributes = widget.productModel.itemAttributes!.attributes;

      variants = widget.productModel.itemAttributes!.variants;

      if (attributes!.isNotEmpty) {
        for (var element in attributes!) {
          if (element.attributeOptions!.isNotEmpty) {
            selectedVariants.add(attributes![attributes!.indexOf(element)]
                .attributeOptions![0]
                .toString());

            selectedIndexVariants.add(
                '${attributes!.indexOf(element)} _${attributes![0].attributeOptions![0].toString()}');

            selectedIndexArray.add('${attributes!.indexOf(element)}_0');
          }
        }
      }

      if (variants!
          .where((element) => element.variantSku == selectedVariants.join('-'))
          .isNotEmpty) {
        widget.productModel.price = variants!
                .where((element) =>
                    element.variantSku == selectedVariants.join('-'))
                .first
                .variantPrice ??
            '0';

        widget.productModel.disPrice = '0';
        // Note: variantInfo will be set after attributesList is loaded in getData()
      }
    }

    getData();
  }

  List<ReviewAttributeModel> reviewAttributeList = [];

  List<ProductModel> productList = [];

  List<ProductModel> storeProductList = [];

  bool showLoader = true;

  List<FavouriteItemModel> lstFav = [];

  List<AttributesModel> attributesList = [];

  List<RatingModel> reviewList = [];

  getData() async {
    if (MyAppState.currentUser != null) {
      await FireStoreUtils()
          .getFavouritesProductList(MyAppState.currentUser!.userID)
          .then((value) {
        setState(() {
          lstFav = value;
        });
      });
    }

    if (widget.productModel.photos.isEmpty) {
      productImage.add(widget.productModel.photo);
    }

    for (var element in widget.productModel.photos) {
      productImage.add(element);
    }

    for (var element in variants!) {
      productImage.add(element.variantImage.toString());
    }

    await FireStoreUtils.getAttributes().then((value) {
      setState(() {
        attributesList = value;
        // Set variantInfo after attributesList is loaded
        if (attributes!.isNotEmpty &&
            variants!
                .where((element) =>
                    element.variantSku == selectedVariants.join('-'))
                .isNotEmpty) {
          Map<String, String> mapData = Map();
          for (var element in attributes!) {
            mapData.addEntries([
              MapEntry(
                  attributesList
                      .where((element1) => element.attributesId == element1.id)
                      .first
                      .title
                      .toString(),
                  selectedVariants[attributes!.indexOf(element)])
            ]);
          }

          widget.productModel.variantInfo = VariantInfo(
              variantPrice: variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .first
                      .variantPrice ??
                  '0',
              variantSku: selectedVariants.join('-'),
              variantOptions: mapData,
              variantImage: variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .first
                      .variantImage ??
                  '',
              variantId: variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .first
                      .variantId ??
                  '0');
        }
      });
    });

    await FireStoreUtils.getAllReviewAttributes().then((value) {
      reviewAttributeList = value;
    });

    await FireStoreUtils().getReviewList(widget.productModel.id).then((value) {
      setState(() {
        reviewList = value;
      });
    });

    SharedPreferences sp = await SharedPreferences.getInstance();

    String? foodType = sp.getString("foodType") ?? "Delivery";

    await FireStoreUtils.getStoreProduct(
            widget.productModel.vendorID.toString())
        .then((value) {
      if (foodType == "Delivery") {
        for (var element in value) {
          if (element.id != widget.productModel.id &&
              element.takeaway == false) {
            storeProductList.add(element);
          }
        }
      } else {
        for (var element in value) {
          if (element.id != widget.productModel.id) {
            storeProductList.add(element);
          }
        }
      }

      setState(() {});
    });

    await FireStoreUtils.getProductListByCategoryId(
            widget.productModel.categoryID.toString())
        .then((value) {
      if (foodType == "Delivery") {
        for (var element in value) {
          if (element.id != widget.productModel.id &&
              element.takeaway == false) {
            productList.add(element);
          }
        }
      } else {
        for (var element in value) {
          if (element.id != widget.productModel.id) {
            productList.add(element);
          }
        }
      }

      setState(() {});
    });

    setState(() {
      showLoader = false;
    });
  }

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: true);

    cartDatabase.allCartProducts.then((value) {
      final bool _productIsInList = value.any((product) =>
          product.id ==
          widget.productModel.id +
              "~" +
              (variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .isNotEmpty
                  ? variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .first
                      .variantId
                      .toString()
                  : ""));

      if (_productIsInList) {
        CartProduct element = value.firstWhere((product) =>
            product.id ==
            widget.productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .first
                        .variantId
                        .toString()
                    : ""));

        setState(() {
          productQnt = element.quantity;
        });
      } else {
        setState(() {
          productQnt = 0;
        });
      }
    });

    super.didChangeDependencies();
  }

  final PageController _controller =
      PageController(viewportFraction: 1, keepPage: true);

  @override
  Widget build(BuildContext context) {
    if (showLoader) {
      return ShimmerWidgets.productDetailsScreenShimmer();
    }

    // Cache expensive computations
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isDark = isDarkMode(context);
    final isFavorite =
        lstFav.any((element) => element.productId == widget.productModel.id);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(COLOR_PRIMARY)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite
                  ? Color(COLOR_PRIMARY)
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
            onPressed: () {
              if (MyAppState.currentUser == null) {
                push(context, LoginScreen());
              } else {
                setState(() {
                  var contain = lstFav
                      .where((e) => e.productId == widget.productModel.id);

                  if (contain.isNotEmpty) {
                    final favouriteModel = FavouriteItemModel(
                      productId: widget.productModel.id,
                      storeId: widget.vendorModel.id,
                      userId: MyAppState.currentUser!.userID,
                    );
                    lstFav.removeWhere(
                      (item) => item.productId == widget.productModel.id,
                    );
                    FireStoreUtils().removeFavouriteItem(favouriteModel);
                  } else {
                    final favouriteModel = FavouriteItemModel(
                      productId: widget.productModel.id,
                      storeId: widget.vendorModel.id,
                      userId: MyAppState.currentUser!.userID,
                    );
                    FireStoreUtils().setFavouriteStoreItem(favouriteModel);
                    lstFav.add(favouriteModel);
                  }
                });
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          Column(
            children: [
              SizedBox(
                height: 250.0,
                child: PageView.builder(
                  itemCount: productImage.length,
                  scrollDirection: Axis.horizontal,
                  controller: _controller,
                  onPageChanged: (value) => setState(() {}),
                  allowImplicitScrolling: true,
                  itemBuilder: (context, index) {
                    return CommonNetworkImage(
                      imageUrl: getImageVAlidUrl(productImage[index]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Indicator(
                  controller: _controller,
                  itemCount: productImage.length,
                ),
              ),
            ],
          ),
          Container(
            color: isDark ? Colors.black : const Color(0xFFFFFFFF),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.productModel.name,
                                style: TextStyle(
                                    color: Colors.black,
                                    fontFamily: "Poppinsm",
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            widget.productModel.disPrice == "" ||
                                    widget.productModel.disPrice == "0"
                                ? Text(
                                    "${amountShow(amount: widget.productModel.price)}",
                                    style: TextStyle(
                                        color: CustomColors.primary,
                                        fontSize: 18.0,
                                        fontWeight: FontWeight.w600),
                                  )
                                : Row(
                                    children: [
                                      Text(
                                        "${amountShow(amount: widget.productModel.disPrice)}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(COLOR_PRIMARY),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 2,
                                      ),
                                      Text(
                                        '${amountShow(amount: widget.productModel.price)}',
                                        style: const TextStyle(
                                            fontFamily: "Poppinsm",
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey,
                                            decoration:
                                                TextDecoration.lineThrough),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  if (widget.productModel.reviewsCount != 0)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(10),
                                            topRight: Radius.circular(10),
                                            bottomLeft: Radius.circular(10),
                                            bottomRight: Radius.circular(10)),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        child: Row(
                                          children: [
                                            Text(
                                              widget.productModel
                                                          .reviewsCount !=
                                                      0
                                                  ? (widget.productModel
                                                              .reviewsSum /
                                                          widget.productModel
                                                              .reviewsCount)
                                                      .toStringAsFixed(1)
                                                  : 0.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: 8,
                                            ),
                                            const Icon(
                                              Icons.star,
                                              size: 18,
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (widget.productModel.reviewsCount != 0)
                                    const SizedBox(width: 10),
                                  widget.productModel.reviewsCount == 0
                                      ? Text(
                                          "No reviews yet",
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12.0,
                                            fontWeight: FontWeight.w400,
                                            fontFamily: "Poppinsm",
                                          ),
                                        )
                                      : Text(
                                          "${widget.productModel.reviewsCount} " +
                                              "Review",
                                          style: TextStyle(
                                              color: Colors.black54,
                                              fontSize: 14.0,
                                              fontWeight: FontWeight.w400,
                                              fontFamily: "Poppinsm"),
                                        ),
                                ],
                              ),
                            ),
                            if (isOpen == false)
                              const Center()
                            else
                              Align(
                                alignment: Alignment.centerRight,
                                child: AddIconButton(
                                  productModel: widget.productModel,
                                  size: 30.0,
                                  onCartUpdated: updatePrice,
                                  isRestaurantOpen: isOpen,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        // ETA and Delivery Fee indicators
                        RestaurantEtaFeeRow(
                          vendorModel: widget.vendorModel,
                          currencyModel: null,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: CachedNetworkImage(
                                      height: 40,
                                      width: 40,
                                      imageUrl: getImageVAlidUrl(
                                          widget.vendorModel.photo),
                                      imageBuilder: (context, imageProvider) =>
                                          Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          image: DecorationImage(
                                              image: imageProvider,
                                              fit: BoxFit.cover),
                                        ),
                                      ),
                                      placeholder: (context, url) => Center(
                                          child: CircularProgressIndicator
                                              .adaptive(
                                        valueColor: AlwaysStoppedAnimation(
                                            Color(COLOR_PRIMARY)),
                                      )),
                                      errorWidget: (context, url, error) =>
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              child: CachedNetworkImage(
                                                imageUrl: placeholderImage,
                                                memCacheWidth: 200,
                                                memCacheHeight: 200,
                                                fit: BoxFit.cover,
                                              )),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ),
                                  InkWell(
                                      onTap: () async {
                                        push(
                                          context,
                                          NewVendorProductsScreen(
                                              vendorModel: widget.vendorModel),
                                        );
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(widget.vendorModel.title,
                                              style: TextStyle(
                                                  color: Color(COLOR_PRIMARY))),
                                          Text(
                                              isOpen == true ? "Open" : "Close",
                                              style: TextStyle(
                                                  color: isOpen == true
                                                      ? Colors.green
                                                      : Colors.red)),
                                        ],
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          "Details",
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4.0),
                        CommonExpandableText(
                          text: widget.productModel.description,
                          trimLines: 5,
                          textStyle: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14.0,
                            fontWeight: FontWeight.w400,
                            fontFamily: "Poppinsl",
                          ),
                          toggleTextStyle: const TextStyle(
                            color: CustomColors.primary,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            fontFamily: "Poppinsm",
                          ),
                        ),
                      ],
                    ),
                  ),
                  attributes!.isEmpty
                      ? Container()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListView.builder(
                              itemCount: attributes!.length,
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                String title = "";

                                for (var element in attributesList) {
                                  if (attributes![index].attributesId ==
                                      element.id) {
                                    title = element.title.toString();
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 5),
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 15),
                                      child: Wrap(
                                        spacing: 6.0,
                                        runSpacing: 6.0,
                                        children: List.generate(
                                          attributes![index]
                                              .attributeOptions!
                                              .length,
                                          (i) {
                                            return InkWell(
                                                onTap: () async {
                                                  setState(() {
                                                    if (selectedIndexVariants
                                                        .where((element) =>
                                                            element.contains(
                                                                '$index _'))
                                                        .isEmpty) {
                                                      selectedVariants.insert(
                                                          index,
                                                          attributes![index]
                                                              .attributeOptions![
                                                                  i]
                                                              .toString());

                                                      selectedIndexVariants.add(
                                                          '$index _${attributes![index].attributeOptions![i].toString()}');

                                                      selectedIndexArray
                                                          .add('${index}_$i');
                                                    } else {
                                                      selectedIndexArray.remove(
                                                          '${index}_${attributes![index].attributeOptions?.indexOf(selectedIndexVariants.where((element) => element.contains('$index _')).first.replaceAll('$index _', ''))}');

                                                      selectedVariants
                                                          .removeAt(index);

                                                      selectedIndexVariants.remove(
                                                          selectedIndexVariants
                                                              .where((element) =>
                                                                  element.contains(
                                                                      '$index _'))
                                                              .first);

                                                      selectedVariants.insert(
                                                          index,
                                                          attributes![index]
                                                              .attributeOptions![
                                                                  i]
                                                              .toString());

                                                      selectedIndexVariants.add(
                                                          '$index _${attributes![index].attributeOptions![i].toString()}');

                                                      selectedIndexArray
                                                          .add('${index}_$i');
                                                    }
                                                  });

                                                  await cartDatabase
                                                      .allCartProducts
                                                      .then((value) {
                                                    final bool _productIsInList = value.any((product) =>
                                                        product.id ==
                                                        widget.productModel.id +
                                                            "~" +
                                                            (variants!
                                                                    .where((element) =>
                                                                        element
                                                                            .variantSku ==
                                                                        selectedVariants.join(
                                                                            '-'))
                                                                    .isNotEmpty
                                                                ? variants!
                                                                    .where((element) =>
                                                                        element
                                                                            .variantSku ==
                                                                        selectedVariants
                                                                            .join('-'))
                                                                    .first
                                                                    .variantId
                                                                    .toString()
                                                                : ""));

                                                    if (_productIsInList) {
                                                      CartProduct element = value.firstWhere((product) =>
                                                          product.id ==
                                                          widget.productModel
                                                                  .id +
                                                              "~" +
                                                              (variants!
                                                                      .where((element) =>
                                                                          element
                                                                              .variantSku ==
                                                                          selectedVariants.join(
                                                                              '-'))
                                                                      .isNotEmpty
                                                                  ? variants!
                                                                      .where((element) =>
                                                                          element
                                                                              .variantSku ==
                                                                          selectedVariants
                                                                              .join('-'))
                                                                      .first
                                                                      .variantId
                                                                      .toString()
                                                                  : ""));

                                                      setState(() {
                                                        productQnt =
                                                            element.quantity;
                                                      });
                                                    } else {
                                                      setState(() {
                                                        productQnt = 0;
                                                      });
                                                    }
                                                  });

                                                  if (variants!
                                                      .where((element) =>
                                                          element.variantSku ==
                                                          selectedVariants
                                                              .join('-'))
                                                      .isNotEmpty) {
                                                    widget.productModel
                                                        .price = variants!
                                                            .where((element) =>
                                                                element
                                                                    .variantSku ==
                                                                selectedVariants
                                                                    .join('-'))
                                                            .first
                                                            .variantPrice ??
                                                        '0';

                                                    widget.productModel
                                                        .disPrice = '0';

                                                    // Set variantInfo for AddIconButton
                                                    Map<String, String>
                                                        mapData = Map();
                                                    for (var element
                                                        in attributes!) {
                                                      mapData.addEntries([
                                                        MapEntry(
                                                            attributesList
                                                                .where((element1) =>
                                                                    element
                                                                        .attributesId ==
                                                                    element1.id)
                                                                .first
                                                                .title
                                                                .toString(),
                                                            selectedVariants[
                                                                attributes!
                                                                    .indexOf(
                                                                        element)])
                                                      ]);
                                                    }

                                                    widget.productModel.variantInfo = VariantInfo(
                                                        variantPrice: variants!
                                                                .where((element) =>
                                                                    element.variantSku ==
                                                                    selectedVariants.join(
                                                                        '-'))
                                                                .first
                                                                .variantPrice ??
                                                            '0',
                                                        variantSku: selectedVariants
                                                            .join('-'),
                                                        variantOptions: mapData,
                                                        variantImage: variants!
                                                                .where((element) =>
                                                                    element.variantSku ==
                                                                    selectedVariants.join('-'))
                                                                .first
                                                                .variantImage ??
                                                            '',
                                                        variantId: variants!.where((element) => element.variantSku == selectedVariants.join('-')).first.variantId ?? '0');
                                                  }
                                                },
                                                child: _buildChip(
                                                    attributes![index]
                                                        .attributeOptions![i]
                                                        .toString(),
                                                    i,
                                                    selectedVariants.contains(
                                                            attributes![index]
                                                                .attributeOptions![
                                                                    i]
                                                                .toString())
                                                        ? true
                                                        : false));
                                          },
                                        ).toList(),
                                      ),
                                    )
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                  _CompleteYourMealSection(
                    productId: widget.productModel.id,
                    vendorId: widget.vendorModel.id,
                    cartDatabase: cartDatabase,
                    onAdded: updatePrice,
                  ),
                  if (widget.productModel.calories != 0 &&
                      widget.productModel.grams != 0 &&
                      widget.productModel.proteins != 0 &&
                      widget.productModel.fats != 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Card(
                          color: isDark
                              ? const Color(DARK_COLOR)
                              : const Color(0xffF2F4F6),

                          // Color(0XFFF9FAFE),

                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 10, right: 20, left: 20, bottom: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  if (widget.productModel.calories != 0)
                                    Column(
                                      children: [
                                        Text(
                                          widget.productModel.calories
                                              .toString(),
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                        const SizedBox(
                                          height: 8,
                                        ),
                                        Text("kcal",
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontFamily: "Poppinsl"))
                                      ],
                                    ),
                                  if (widget.productModel.grams != 0)
                                    Column(
                                      children: [
                                        Text(
                                            widget.productModel.grams
                                                .toString(),
                                            style:
                                                const TextStyle(fontSize: 20)),
                                        const SizedBox(
                                          height: 8,
                                        ),
                                        Text("grams",
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontFamily: "Poppinsl"))
                                      ],
                                    ),
                                  if (widget.productModel.proteins != 0)
                                    Column(
                                      children: [
                                        Text(
                                            widget.productModel.proteins
                                                .toString(),
                                            style:
                                                const TextStyle(fontSize: 20)),
                                        const SizedBox(
                                          height: 8,
                                        ),
                                        Text("proteins",
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontFamily: "Poppinsl"))
                                      ],
                                    ),
                                  if (widget.productModel.fats != 0)
                                    Column(
                                      children: [
                                        Text(
                                            widget.productModel.fats.toString(),
                                            style:
                                                const TextStyle(fontSize: 20)),
                                        const SizedBox(
                                          height: 8,
                                        ),
                                        Text("fats",
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontFamily: "Poppinsl"))
                                      ],
                                    )
                                ],
                              ))),
                    ),
                  lstAddAddonsCustom.isEmpty
                      ? Container()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              child: Text(
                                "Add Ons (Optional)",
                                style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 16,
                                    color: isDark
                                        ? const Color(0xffffffff)
                                        : const Color(0xff000000)),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              child: ListView.builder(
                                  itemCount: lstAddAddonsCustom.length,
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      margin: const EdgeInsets.only(
                                          top: 15, bottom: 15),
                                      child: Row(
                                        children: [
                                          Text(
                                            lstAddAddonsCustom[index].name!,
                                            style: TextStyle(
                                                fontFamily: "Poppinsl",
                                                color: isDark
                                                    ? const Color(0xffC6C4C4)
                                                    : const Color(0xff5E5C5C)),
                                          ),
                                          const Expanded(child: SizedBox()),
                                          Text(
                                            amountShow(
                                                amount:
                                                    lstAddAddonsCustom[index]
                                                        .price!),
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontFamily: "Poppinsm",
                                                color: Color(COLOR_PRIMARY)),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                lstAddAddonsCustom[index]
                                                        .isCheck =
                                                    !lstAddAddonsCustom[index]
                                                        .isCheck;

                                                if (variants!
                                                    .where((element) =>
                                                        element.variantSku ==
                                                        selectedVariants
                                                            .join('-'))
                                                    .isNotEmpty) {
                                                  VariantInfo? variantInfo =
                                                      VariantInfo();

                                                  Map<String, String> mapData =
                                                      Map();

                                                  for (var element
                                                      in attributes!) {
                                                    mapData.addEntries([
                                                      MapEntry(
                                                          attributesList
                                                              .where((element1) =>
                                                                  element
                                                                      .attributesId ==
                                                                  element1.id)
                                                              .first
                                                              .title
                                                              .toString(),
                                                          selectedVariants[
                                                              attributes!
                                                                  .indexOf(
                                                                      element)])
                                                    ]);

                                                    setState(() {});
                                                  }

                                                  variantInfo = VariantInfo(
                                                      variantPrice: variants!
                                                              .where((element) =>
                                                                  element.variantSku ==
                                                                  selectedVariants.join(
                                                                      '-'))
                                                              .first
                                                              .variantPrice ??
                                                          '0',
                                                      variantSku:
                                                          selectedVariants
                                                              .join('-'),
                                                      variantOptions: mapData,
                                                      variantImage: variants!
                                                              .where((element) =>
                                                                  element.variantSku ==
                                                                  selectedVariants
                                                                      .join(
                                                                          '-'))
                                                              .first
                                                              .variantImage ??
                                                          '',
                                                      variantId: variants!
                                                              .where((element) => element.variantSku == selectedVariants.join('-'))
                                                              .first
                                                              .variantId ??
                                                          '0');

                                                  widget.productModel
                                                          .variantInfo =
                                                      variantInfo;
                                                }

                                                if (lstAddAddonsCustom[index]
                                                        .isCheck ==
                                                    true) {
                                                  AddAddonsDemo addAddonsDemo =
                                                      AddAddonsDemo(
                                                          name: widget
                                                                  .productModel
                                                                  .addOnsTitle[
                                                              index],
                                                          index: index,
                                                          isCheck: true,
                                                          categoryID: widget
                                                              .productModel.id,
                                                          price:
                                                              lstAddAddonsCustom[
                                                                      index]
                                                                  .price);

                                                  lstTemp.add(addAddonsDemo);

                                                  saveAddOns(lstTemp);

                                                  addtocard(widget.productModel,
                                                      false);
                                                } else {
                                                  var removeIndex = -1;

                                                  for (int a = 0;
                                                      a < lstTemp.length;
                                                      a++) {
                                                    if (lstTemp[a].index ==
                                                            index &&
                                                        lstTemp[a].categoryID ==
                                                            lstAddAddonsCustom[
                                                                    index]
                                                                .categoryID) {
                                                      removeIndex = a;

                                                      break;
                                                    }
                                                  }

                                                  lstTemp.removeAt(removeIndex);

                                                  saveAddOns(lstTemp);

                                                  //widget.productModel.price = widget.productModel.disPrice==""||widget.productModel.disPrice=="0"? (widget.productModel.price) :(widget.productModel.disPrice!);

                                                  addtocard(widget.productModel,
                                                      false);
                                                }
                                              });
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                  left: 10, right: 10),
                                              child: Icon(
                                                !lstAddAddonsCustom[index]
                                                        .isCheck
                                                    ? Icons
                                                        .check_box_outline_blank
                                                    : Icons.check_box,
                                                color:
                                                    isDark ? null : Colors.grey,
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                    );
                                  }),
                            ),
                          ],
                        ),
                  Visibility(
                    visible: widget.productModel.specification.isNotEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Specification",
                            style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 20,
                                color: isDark
                                    ? const Color(0xffffffff)
                                    : const Color(0xff000000)),
                          ),
                        ),
                        widget.productModel.specification.isNotEmpty
                            ? ListView.builder(
                                itemCount:
                                    widget.productModel.specification.length,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Text(
                                            widget.productModel.specification
                                                    .keys
                                                    .elementAt(index) +
                                                " : ",
                                            style: TextStyle(
                                                color: Colors.black
                                                    .withOpacity(0.60),
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.5,
                                                fontSize: 14)),
                                        Text(
                                            widget.productModel.specification
                                                .values
                                                .elementAt(index),
                                            style: TextStyle(
                                                color: Colors.black
                                                    .withOpacity(0.90),
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.5,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : Container(),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: widget.productModel.reviewAttributes!.isNotEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "By feature",
                            style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 20,
                                color: isDark
                                    ? const Color(0xffffffff)
                                    : const Color(0xff000000)),
                          ),
                        ),
                        widget.productModel.reviewAttributes != null
                            ? Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ListView.builder(
                                  itemCount: widget
                                      .productModel.reviewAttributes!.length,
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder: (context, index) {
                                    ReviewAttributeModel reviewAttribute =
                                        ReviewAttributeModel();

                                    for (var element in reviewAttributeList) {
                                      if (element.id ==
                                          widget.productModel.reviewAttributes!
                                              .keys
                                              .elementAt(index)) {
                                        reviewAttribute = element;
                                      }
                                    }

                                    ReviewsAttribute reviewsAttributeModel =
                                        ReviewsAttribute.fromJson(widget
                                            .productModel
                                            .reviewAttributes!
                                            .values
                                            .elementAt(index));

                                    return Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Expanded(
                                              child: Text(
                                                  reviewAttribute.title
                                                      .toString(),
                                                  style: TextStyle(
                                                      color: Colors.black
                                                          .withOpacity(0.60),
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      letterSpacing: 0.5,
                                                      fontSize: 14))),
                                          RatingBar.builder(
                                            ignoreGestures: true,
                                            initialRating:
                                                (reviewsAttributeModel
                                                        .reviewsSum!
                                                        .toDouble() /
                                                    reviewsAttributeModel
                                                        .reviewsCount!
                                                        .toDouble()),
                                            minRating: 1,
                                            itemSize: 20,
                                            direction: Axis.horizontal,
                                            allowHalfRating: true,
                                            itemCount: 5,
                                            itemBuilder: (context, _) => Icon(
                                              Icons.star,
                                              color: Color(COLOR_PRIMARY),
                                            ),
                                            onRatingUpdate: (double rate) {
                                              // ratings = rate;

                                              // print(ratings);
                                            },
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          Text(
                                            (reviewsAttributeModel.reviewsSum!
                                                        .toDouble() /
                                                    reviewsAttributeModel
                                                        .reviewsCount!
                                                        .toDouble())
                                                .toStringAsFixed(1),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w400),
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: reviewList.isNotEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: ListView.builder(
                            itemCount:
                                reviewList.length > 10 ? 10 : reviewList.length,
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      width: 1.0,
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CachedNetworkImage(
                                              height: 45,
                                              width: 45,
                                              imageUrl: getImageVAlidUrl(
                                                  reviewList[index]
                                                      .profile
                                                      .toString()),
                                              imageBuilder:
                                                  (context, imageProvider) =>
                                                      Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(35),
                                                  image: DecorationImage(
                                                      image: imageProvider,
                                                      fit: BoxFit.cover),
                                                ),
                                              ),
                                              placeholder: (context, url) =>
                                                  Center(
                                                      child:
                                                          CircularProgressIndicator
                                                              .adaptive(
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                        Color(COLOR_PRIMARY)),
                                              )),
                                              errorWidget: (context, url,
                                                      error) =>
                                                  ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              35),
                                                      child: CachedNetworkImage(
                                                        imageUrl: placeholderImage,
                                                        memCacheWidth: 200,
                                                        memCacheHeight: 200,
                                                        fit: BoxFit.cover,
                                                      )),
                                              fit: BoxFit.cover,
                                            ),
                                            const SizedBox(
                                              width: 10,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    reviewList[index]
                                                        .uname
                                                        .toString(),
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: 1,
                                                        fontSize: 16),
                                                  ),
                                                  RatingBar.builder(
                                                    ignoreGestures: true,
                                                    initialRating:
                                                        reviewList[index]
                                                                .rating ??
                                                            0.0,
                                                    minRating: 1,
                                                    itemSize: 22,
                                                    direction: Axis.horizontal,
                                                    allowHalfRating: true,
                                                    itemCount: 5,
                                                    itemPadding:
                                                        const EdgeInsets.only(
                                                            top: 5.0),
                                                    itemBuilder: (context, _) =>
                                                        Icon(
                                                      Icons.star,
                                                      color:
                                                          Color(COLOR_PRIMARY),
                                                    ),
                                                    onRatingUpdate:
                                                        (double rate) {
                                                      // ratings = rate;

                                                      // print(ratings);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                                orderDate(reviewList[index]
                                                    .createdAt),
                                                style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey.shade200
                                                        : const Color(
                                                            0XFF555353),
                                                    fontFamily: "Poppinsr")),
                                          ],
                                        ),
                                        Text(
                                            reviewList[index]
                                                .comment
                                                .toString(),
                                            style: TextStyle(
                                                color: Colors.black
                                                    .withOpacity(0.70),
                                                fontWeight: FontWeight.w400,
                                                letterSpacing: 1,
                                                fontSize: 14)),
                                        const SizedBox(
                                          height: 10,
                                        ),
                                        reviewList[index].photos!.isNotEmpty
                                            ? SizedBox(
                                                height: 75,
                                                child: ListView.builder(
                                                  itemCount: reviewList[index]
                                                      .photos!
                                                      .length,
                                                  shrinkWrap: true,
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  itemBuilder:
                                                      (context, index1) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              6.0),
                                                      child: CachedNetworkImage(
                                                        height: 65,
                                                        width: 65,
                                                        imageUrl:
                                                            getImageVAlidUrl(
                                                                reviewList[index]
                                                                        .photos![
                                                                    index1]),
                                                        imageBuilder: (context,
                                                                imageProvider) =>
                                                            Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            image: DecorationImage(
                                                                image:
                                                                    imageProvider,
                                                                fit: BoxFit
                                                                    .cover),
                                                          ),
                                                        ),
                                                        placeholder: (context,
                                                                url) =>
                                                            Center(
                                                                child:
                                                                    CircularProgressIndicator
                                                                        .adaptive(
                                                          valueColor:
                                                              AlwaysStoppedAnimation(
                                                                  Color(
                                                                      COLOR_PRIMARY)),
                                                        )),
                                                        errorWidget: (context,
                                                                url, error) =>
                                                            ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            10),
                                                                child: Image
                                                                    .network(
                                                                  placeholderImage,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                )),
                                                        fit: BoxFit.cover,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              )
                                            : Container()
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: () {
                                push(
                                  context,
                                  Review(
                                    productModel: widget.productModel,
                                  ),
                                );
                              },
                              child: Text(
                                'See All Reviews',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(COLOR_PRIMARY),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Visibility(
                      visible: storeProductList.isNotEmpty,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            height: 10,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              spacing: 8.0,
                              children: [
                                Expanded(
                                  child: Text("More from the Restaurant",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: "Poppinsm",
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500)),
                                ),
                                InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "See All",
                                    style: TextStyle(
                                        color: CustomColors.primary,
                                        fontFamily: "Poppinsm",
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                              width: screenSize.width,
                              height: screenSize.height * 0.28,
                              child: ListView.builder(
                                shrinkWrap: true,
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: storeProductList.length > 6
                                    ? 6
                                    : storeProductList.length,
                                itemBuilder: (context, index) {
                                  ProductModel productModel =
                                      storeProductList[index];
                                  return Container(
                                      margin:
                                          EdgeInsets.symmetric(horizontal: 8.0),
                                      child: CommonElevatedButton(
                                        onButtonPressed: () async {
                                          VendorModel? vendorModel =
                                              await FireStoreUtils.getVendor(
                                                  storeProductList[index]
                                                      .vendorID);

                                          if (vendorModel != null) {
                                            push(
                                              context,
                                              ProductDetailsScreen(
                                                vendorModel: vendorModel,
                                                productModel: productModel,
                                              ),
                                            );
                                          }
                                        },
                                        overlayColor: Colors.transparent,
                                        backgroundColor: Colors.transparent,
                                        padding: EdgeInsets.zero,
                                        custom: SizedBox(
                                          width: context.screenWidth * 0.38,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Stack(
                                                alignment:
                                                    Alignment.bottomRight,
                                                clipBehavior: Clip.none,
                                                children: [
                                                  CommonNetworkImage(
                                                    imageUrl: getImageVAlidUrl(
                                                        productModel.photo),
                                                    height: 120.0,
                                                    width: context.screenWidth,
                                                  ),
                                                  AddIconButton(
                                                    productModel: productModel,
                                                    size: 30.0,
                                                    margin: EdgeInsets.all(4.0),
                                                    onCartUpdated: updatePrice,
                                                    isRestaurantOpen: isOpen,
                                                  )
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Flexible(
                                                child: Text(productModel.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontFamily: "Poppinsm",
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  if (productModel
                                                          .reviewsCount !=
                                                      0)
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 5,
                                                                vertical: 2),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                                productModel.reviewsCount !=
                                                                        0
                                                                    ? (productModel.reviewsSum /
                                                                            productModel
                                                                                .reviewsCount)
                                                                        .toStringAsFixed(
                                                                            1)
                                                                    : 0
                                                                        .toString(),
                                                                style:
                                                                    const TextStyle(
                                                                  fontFamily:
                                                                      "Poppinsm",
                                                                  letterSpacing:
                                                                      0.5,
                                                                  color: Colors
                                                                      .white,
                                                                )),
                                                            const SizedBox(
                                                                width: 3),
                                                            const Icon(
                                                              Icons.star,
                                                              size: 16,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  productModel.disPrice == "" ||
                                                          productModel
                                                                  .disPrice ==
                                                              "0"
                                                      ? Text(
                                                          "${amountShow(amount: productModel.price)}",
                                                          style: TextStyle(
                                                              color:
                                                                  CustomColors
                                                                      .primary,
                                                              fontSize: 14.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400),
                                                        )
                                                      : Column(
                                                          children: [
                                                            Text(
                                                              "${amountShow(amount: productModel.disPrice)}",
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    "Poppinsm",
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                                color: Color(
                                                                    COLOR_PRIMARY),
                                                              ),
                                                            ),
                                                            Text(
                                                              '${amountShow(amount: productModel.price)}',
                                                              style: const TextStyle(
                                                                  fontFamily:
                                                                      "Poppinsm",
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .grey,
                                                                  decoration:
                                                                      TextDecoration
                                                                          .lineThrough),
                                                            ),
                                                          ],
                                                        ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ));
                                },
                              ))
                        ],
                      )),
                  Visibility(
                      visible: productList.isNotEmpty,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Related Foods",
                              style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontSize: 16,
                                  color: Colors.black),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                              width: screenSize.width,
                              height: screenSize.height * 0.28,
                              child: ListView.builder(
                                shrinkWrap: true,
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: productList.length > 6
                                    ? 6
                                    : productList.length,
                                itemBuilder: (context, index) {
                                  ProductModel productModel =
                                      productList[index];

                                  return Container(
                                      margin:
                                          EdgeInsets.symmetric(horizontal: 8.0),
                                      child: CommonElevatedButton(
                                        onButtonPressed: () async {
                                          VendorModel? vendorModel =
                                              await FireStoreUtils.getVendor(
                                                  storeProductList[index]
                                                      .vendorID);

                                          if (vendorModel != null) {
                                            push(
                                              context,
                                              ProductDetailsScreen(
                                                vendorModel: vendorModel,
                                                productModel: productModel,
                                              ),
                                            );
                                          }
                                        },
                                        overlayColor: Colors.transparent,
                                        backgroundColor: Colors.transparent,
                                        padding: EdgeInsets.zero,
                                        custom: SizedBox(
                                          width: context.screenWidth * 0.38,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Stack(
                                                alignment:
                                                    Alignment.bottomRight,
                                                clipBehavior: Clip.none,
                                                children: [
                                                  CommonNetworkImage(
                                                    imageUrl: getImageVAlidUrl(
                                                        productModel.photo),
                                                    height: 120.0,
                                                    width: context.screenWidth,
                                                  ),
                                                  AddIconButton(
                                                    productModel: productModel,
                                                    size: 30.0,
                                                    margin: EdgeInsets.all(4.0),
                                                    onCartUpdated: updatePrice,
                                                    isRestaurantOpen: isOpen,
                                                  )
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Flexible(
                                                child: Text(productModel.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontFamily: "Poppinsm",
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  if (productModel
                                                          .reviewsCount !=
                                                      0)
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 5,
                                                                vertical: 2),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                                productModel.reviewsCount !=
                                                                        0
                                                                    ? (productModel.reviewsSum /
                                                                            productModel
                                                                                .reviewsCount)
                                                                        .toStringAsFixed(
                                                                            1)
                                                                    : 0
                                                                        .toString(),
                                                                style:
                                                                    const TextStyle(
                                                                  fontFamily:
                                                                      "Poppinsm",
                                                                  letterSpacing:
                                                                      0.5,
                                                                  color: Colors
                                                                      .white,
                                                                )),
                                                            const SizedBox(
                                                                width: 3),
                                                            const Icon(
                                                              Icons.star,
                                                              size: 16,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  productModel.disPrice == "" ||
                                                          productModel
                                                                  .disPrice ==
                                                              "0"
                                                      ? Text(
                                                          "${amountShow(amount: productModel.price)}",
                                                          style: TextStyle(
                                                              color:
                                                                  CustomColors
                                                                      .primary,
                                                              fontSize: 14.0,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400),
                                                        )
                                                      : Column(
                                                          children: [
                                                            Text(
                                                              "${amountShow(amount: productModel.disPrice)}",
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    "Poppinsm",
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                                color: Color(
                                                                    COLOR_PRIMARY),
                                                              ),
                                                            ),
                                                            Text(
                                                              '${amountShow(amount: productModel.price)}',
                                                              style: const TextStyle(
                                                                  fontFamily:
                                                                      "Poppinsm",
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .grey,
                                                                  decoration:
                                                                      TextDecoration
                                                                          .lineThrough),
                                                            ),
                                                          ],
                                                        ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ));
                                },
                              ))
                        ],
                      )),
                ],
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: isOpen
          ? Container(
              padding: const EdgeInsets.only(
                  left: 20, right: 20, bottom: 20, top: 20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade400))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Item Total:" +
                          " " +
                          amountShow(amount: priceTemp.toString()),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  SizedBox(
                    height: 40.0,
                    child: CommonElevatedButton(
                      onButtonPressed: () {
                        // Allow guests to view cart (login will be required at checkout)
                        pushAndRemoveUntil(
                            context,
                            ContainerScreen(
                              user: MyAppState.currentUser,
                              currentWidget: CartScreen(),
                              appBarTitle: 'Your Cart',
                            ),
                            false);
                      },
                      custom: Row(
                        spacing: 4.0,
                        children: [
                          CommonImage(
                            path: Assets.icShoppingCart,
                            height: 18.0,
                            width: 18.0,
                          ),
                          Text(
                            "View Cart",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w600,
                              fontFamily: "Poppinsm",
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  addtocard(ProductModel productModel, bool isIncerementQuantity) async {
    bool isAddOnApplied = false;

    double addOnVal = 0;

    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];

      if (addAddonsDemo.categoryID == widget.productModel.id) {
        isAddOnApplied = true;

        addOnVal = addOnVal + double.parse(addAddonsDemo.price!);
      }
    }

    List<CartProduct> cartProducts = await cartDatabase.allCartProducts;

    if (productQnt > 1) {
      var joinTitleString = "";

      String mainPrice = "";

      List<AddAddonsDemo> lstAddOns = [];

      List<String> lstAddOnsTemp = [];

      double extrasPrice = 0.0;

      SharedPreferences sp = await SharedPreferences.getInstance();

      String addOns =
          sp.getString("musics_key") != null ? sp.getString('musics_key')! : "";

      bool isAddSame = false;

      if (!isAddSame) {
        if (productModel.disPrice != null &&
            productModel.disPrice!.isNotEmpty &&
            double.parse(productModel.disPrice!) != 0) {
          mainPrice = productModel.disPrice!;
        } else {
          mainPrice = productModel.price;
        }
      }

      if (addOns.isNotEmpty) {
        lstAddOns = AddAddonsDemo.decode(addOns);

        for (int a = 0; a < lstAddOns.length; a++) {
          AddAddonsDemo newAddonsObject = lstAddOns[a];

          if (newAddonsObject.categoryID == widget.productModel.id) {
            if (newAddonsObject.isCheck == true) {
              lstAddOnsTemp.add(newAddonsObject.name!);

              extrasPrice += (double.parse(newAddonsObject.price!));
            }
          }
        }

        joinTitleString = lstAddOnsTemp.join(",");
      }

      final bool _productIsInList = cartProducts.any((product) =>
          product.id ==
          productModel.id +
              "~" +
              (productModel.variantInfo != null
                  ? productModel.variantInfo!.variantId.toString()
                  : ""));

      if (_productIsInList) {
        CartProduct element = cartProducts.firstWhere((product) =>
            product.id ==
            productModel.id +
                "~" +
                (productModel.variantInfo != null
                    ? productModel.variantInfo!.variantId.toString()
                    : ""));

        await cartDatabase.updateProduct(CartProduct(
            id: element.id,
            name: element.name,
            photo: element.photo,
            price: element.price,
            vendorID: element.vendorID,
            quantity:
                isIncerementQuantity ? element.quantity + 1 : element.quantity,
            category_id: element.category_id,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            discountPrice: element.discountPrice ?? ""));
      } else {
        await cartDatabase.updateProduct(CartProduct(
            id: productModel.id +
                "~" +
                (productModel.variantInfo != null
                    ? productModel.variantInfo!.variantId.toString()
                    : ""),
            name: productModel.name,
            photo: productModel.photo,
            price: mainPrice,
            discountPrice: productModel.disPrice,
            vendorID: productModel.vendorID,
            quantity: productQnt,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            category_id: productModel.categoryID,
            variant_info: productModel.variantInfo));
      }

      //  });

      setState(() {});
    } else {
      if (cartProducts.isEmpty) {
        cartDatabase.addProduct(
            productModel, cartDatabase, isIncerementQuantity);
      } else {
        if (cartProducts[0].vendorID == widget.vendorModel.id) {
          cartDatabase.addProduct(
              productModel, cartDatabase, isIncerementQuantity);
        } else {
          cartDatabase.deleteAllProducts();

          cartDatabase.addProduct(
              productModel, cartDatabase, isIncerementQuantity);

          if (isAddOnApplied && addOnVal > 0) {
            priceTemp += (addOnVal * productQnt);
          }
        }
      }
    }

    updatePrice();
  }

  removetocard(ProductModel productModel, bool isIncerementQuantity) async {
    double addOnVal = 0;

    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];

      addOnVal = addOnVal + double.parse(addAddonsDemo.price!);
    }

    List<CartProduct> cartProducts = await cartDatabase.allCartProducts;

    debugPrint("---->$productQnt");

    if (productQnt >= 1) {
      //setState(() async {

      var joinTitleString = "";

      String mainPrice = "";

      List<AddAddonsDemo> lstAddOns = [];

      List<String> lstAddOnsTemp = [];

      double extrasPrice = 0.0;

      SharedPreferences sp = await SharedPreferences.getInstance();

      String addOns =
          sp.getString("musics_key") != null ? sp.getString('musics_key')! : "";

      bool isAddSame = false;

      if (!isAddSame) {
        if (productModel.disPrice != null &&
            productModel.disPrice!.isNotEmpty &&
            double.parse(productModel.disPrice!) != 0) {
          mainPrice = productModel.disPrice!;
        } else {
          mainPrice = productModel.price;
        }
      }

      if (addOns.isNotEmpty) {
        lstAddOns = AddAddonsDemo.decode(addOns);

        for (int a = 0; a < lstAddOns.length; a++) {
          AddAddonsDemo newAddonsObject = lstAddOns[a];

          if (newAddonsObject.categoryID == widget.productModel.id) {
            if (newAddonsObject.isCheck == true) {
              lstAddOnsTemp.add(newAddonsObject.name!);

              extrasPrice += (double.parse(newAddonsObject.price!));
            }
          }
        }

        joinTitleString = lstAddOnsTemp.join(",");
      }

      final bool _productIsInList = cartProducts.any((product) =>
          product.id ==
          productModel.id +
              "~" +
              (variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .isNotEmpty
                  ? variants!
                      .where((element) =>
                          element.variantSku == selectedVariants.join('-'))
                      .first
                      .variantId
                      .toString()
                  : ""));

      if (_productIsInList) {
        CartProduct element = cartProducts.firstWhere((product) =>
            product.id ==
            productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .first
                        .variantId
                        .toString()
                    : ""));

        await cartDatabase.updateProduct(CartProduct(
            id: element.id,
            name: element.name,
            photo: element.photo,
            price: element.price,
            vendorID: element.vendorID,
            quantity:
                isIncerementQuantity ? element.quantity - 1 : element.quantity,
            category_id: element.category_id,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            discountPrice: element.discountPrice ?? ""));
      } else {
        await cartDatabase.updateProduct(CartProduct(
            id: productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variantSku == selectedVariants.join('-'))
                        .first
                        .variantId
                        .toString()
                    : ""),
            name: productModel.name,
            photo: productModel.photo,
            price: mainPrice,
            discountPrice: productModel.disPrice,
            vendorID: productModel.vendorID,
            quantity: productQnt,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            category_id: productModel.categoryID,
            variant_info: productModel.variantInfo));
      }
    } else {
      cartDatabase.removeProduct(productModel.id +
          "~" +
          (variants!
                  .where((element) =>
                      element.variantSku == selectedVariants.join('-'))
                  .isNotEmpty
              ? variants!
                  .where((element) =>
                      element.variantSku == selectedVariants.join('-'))
                  .first
                  .variantId
                  .toString()
              : ""));

      setState(() {
        productQnt = 0;
      });
    }

    updatePrice();
  }

  void getAddOnsData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    final String musicsString = prefs.getString('musics_key') != null
        ? prefs.getString('musics_key')!
        : "";

    if (musicsString.isNotEmpty) {
      setState(() {
        lstTemp = AddAddonsDemo.decode(musicsString);
      });
    }

    if (productQnt > 0) {
      lastPrice = widget.productModel.disPrice == "" ||
              widget.productModel.disPrice == "0"
          ? double.parse(widget.productModel.price)
          : double.parse(widget.productModel.disPrice!) * productQnt;
    }

    if (lstTemp.isEmpty) {
      setState(() {
        if (widget.productModel.addOnsTitle.isNotEmpty) {
          for (int a = 0; a < widget.productModel.addOnsTitle.length; a++) {
            AddAddonsDemo addAddonsDemo = AddAddonsDemo(
                name: widget.productModel.addOnsTitle[a],
                index: a,
                isCheck: false,
                categoryID: widget.productModel.id,
                price: widget.productModel.addOnsPrice[a]);

            lstAddAddonsCustom.add(addAddonsDemo);

            //saveAddonData(lstAddAddonsCustom);
          }
        }
      });
    } else {
      var tempArray = [];

      for (int d = 0; d < lstTemp.length; d++) {
        if (lstTemp[d].categoryID == widget.productModel.id) {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: lstTemp[d].name,
              index: lstTemp[d].index,
              isCheck: true,
              categoryID: lstTemp[d].categoryID,
              price: lstTemp[d].price);

          tempArray.add(addAddonsDemo);
        }
      }

      for (int a = 0; a < widget.productModel.addOnsTitle.length; a++) {
        var isAddonSelected = false;

        for (int temp = 0; temp < tempArray.length; temp++) {
          if (tempArray[temp].name == widget.productModel.addOnsTitle[a]) {
            isAddonSelected = true;
          }
        }

        if (isAddonSelected) {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: widget.productModel.addOnsTitle[a],
              index: a,
              isCheck: true,
              categoryID: widget.productModel.id,
              price: widget.productModel.addOnsPrice[a]);

          lstAddAddonsCustom.add(addAddonsDemo);
        } else {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: widget.productModel.addOnsTitle[a],
              index: a,
              isCheck: false,
              categoryID: widget.productModel.id,
              price: widget.productModel.addOnsPrice[a]);

          lstAddAddonsCustom.add(addAddonsDemo);
        }
      }
    }

    updatePrice();
  }

  void saveAddOns(List<AddAddonsDemo> lstTempDemo) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    final String encodedData = AddAddonsDemo.encode(lstTempDemo);

    await prefs.setString('musics_key', encodedData);
  }

  void clearAddOnData() {
    bool isAddOnApplied = false;

    double addOnVal = 0;

    for (int i = 0; i < lstTemp.length; i++) {
      if (lstTemp[i].categoryID == widget.productModel.id) {
        AddAddonsDemo addAddonsDemo = lstTemp[i];

        isAddOnApplied = true;

        addOnVal = addOnVal + double.parse(addAddonsDemo.price!);
      }
    }

    if (isAddOnApplied && addOnVal > 0 && productQnt > 0) {
      priceTemp -= (addOnVal * productQnt);
    }
  }

  void updatePrice() {
    double addOnVal = 0;

    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];

      if (addAddonsDemo.categoryID == widget.productModel.id) {
        addOnVal = addOnVal + double.parse(addAddonsDemo.price!);
      }
    }

    List<CartProduct> cartProducts = [];

    Future.delayed(const Duration(milliseconds: 500), () {
      cartProducts.clear();

      cartDatabase.allCartProducts.then((value) {
        priceTemp = 0;

        cartProducts.addAll(value);

        for (int i = 0; i < cartProducts.length; i++) {
          CartProduct e = cartProducts[i];

          if (e.extras_price != null &&
              e.extras_price != "" &&
              double.parse(e.extras_price!) != 0) {
            priceTemp += double.parse(e.extras_price!) * e.quantity;
          }

          priceTemp += double.parse(e.price) * e.quantity;
        }

        setState(() {});
      });
    });
  }

  Widget _buildChip(String label, int attributesOptionIndex, bool isSelected) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
      backgroundColor: isSelected ? Color(COLOR_PRIMARY) : Colors.white,
      elevation: 6.0,
      shadowColor: Colors.grey[60],
      padding: const EdgeInsets.all(8.0),
    );

    // Container(

    //   decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0xffABBCC8), width: 0.5)),

    //   child: Padding(

    //     padding: const EdgeInsets.all(2.0),

    //     child: Container(

    //       decoration: BoxDecoration(

    //         color: isSelected ? Color(COLOR_PRIMARY) : Colors.white,

    //         borderRadius: BorderRadius.circular(30),

    //       ),

    //       child: Center(

    //         child: Text(

    //           label,

    //           style: TextStyle(

    //             color: isSelected ? Colors.white : Colors.black,

    //           ),

    //         ),

    //       ),

    //       // child: Chip(

    //       //   label: Text(

    //       //     label,

    //       //     style: const TextStyle(

    //       //       color: Colors.white,

    //       //     ),

    //       //   ),

    //       //   backgroundColor: colors,

    //       //   elevation: 6.0,

    //       //   shadowColor: Colors.grey[60],

    //       //   padding: const EdgeInsets.all(8.0),

    //       // ),

    //     ),

    //   ),

    // );
  }
}

class AddAddonsDemo {
  String? name;

  int? index;

  String? price;

  bool isCheck;

  String? categoryID;

  AddAddonsDemo(
      {this.name,
      this.index,
      this.price,
      this.isCheck = false,
      this.categoryID});

  static Map<String, dynamic> toMap(AddAddonsDemo music) => {
        'index': music.index,
        'name': music.name,
        'price': music.price,
        'isCheck': music.isCheck,
        "categoryID": music.categoryID
      };

  factory AddAddonsDemo.fromJson(Map<String, dynamic> jsonData) {
    return AddAddonsDemo(
        index: jsonData['index'],
        name: jsonData['name'],
        price: jsonData['price'],
        isCheck: jsonData['isCheck'],
        categoryID: jsonData["categoryID"]);
  }

  static String encode(List<AddAddonsDemo> item) => json.encode(
        item
            .map<Map<String, dynamic>>((item) => AddAddonsDemo.toMap(item))
            .toList(),
      );

  static List<AddAddonsDemo> decode(String item) =>
      (json.decode(item) as List<dynamic>)
          .map<AddAddonsDemo>((item) => AddAddonsDemo.fromJson(item))
          .toList();

  @override
  String toString() {
    return '{name: $name, index: $index, price: $price, isCheck: $isCheck, categoryID: $categoryID}';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'index': index,
      'price': price,
      'isCheck': isCheck,
      'categoryID': categoryID
    };
  }
}

class _CompleteYourMealSection extends StatelessWidget {
  final String productId;
  final String vendorId;
  final CartDatabase cartDatabase;
  final VoidCallback? onAdded;

  const _CompleteYourMealSection({
    required this.productId,
    required this.vendorId,
    required this.cartDatabase,
    this.onAdded,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AddonPromoModel>>(
      future: AddonPromoService.getPromosByTriggerProduct(
        productId: productId,
        restaurantId: vendorId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final promos = snapshot.data ?? [];
        if (promos.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete your meal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: promos.length,
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AddonPromoCard(
                        promo: promo,
                        onAdd: () async {
                          await cartDatabase.addAddonToCart(
                            addonPromoId: promo.addonPromoId,
                            addonPromoName: promo.addonName,
                            productId: promo.addonProductId,
                            productName: promo.addonProductName,
                            photo: promo.imageUrl ?? '',
                            addonPrice: promo.addonPrice,
                            vendorID: vendorId,
                            quantity: 1,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${promo.addonName} added to cart',
                                ),
                              ),
                            );
                            onAdded?.call();
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SharedData {
  bool? isCheckedValue;

  String? categoryId;

  SharedData({this.categoryId, this.isCheckedValue});
}
