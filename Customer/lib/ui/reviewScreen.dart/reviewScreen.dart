import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/Ratingmodel.dart';
import 'package:foodie_customer/model/ReviewAttributeModel.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/fullScreenImageViewer/fullscreenimage.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:image_picker/image_picker.dart';

class ReviewScreen extends StatefulWidget {
  final CartProduct product;
  final String? orderId;

  const ReviewScreen({Key? key, required this.product, this.orderId})
      : super(key: key);

  @override
  _ReviewScreenState createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with TickerProviderStateMixin {
  RatingModel? ratingModel;
  final ImagePicker _imagePicker = ImagePicker();
  final List<dynamic> _mediaFiles = [];
  final _formKey = GlobalKey<FormState>();
  FireStoreUtils fireStoreUtils = FireStoreUtils();
  final comment = TextEditingController();
  var ratings = 0.0;
  var reviewCount, reviewSum;
  var vendorReviewCount, vendoReviewSum;

  ProductModel? productModel;
  VendorCategoryModel? vendorCategoryModel;

  List<ReviewAttributeModel> reviewAttributeList = [];

  // RatingModel? rating;
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Widget _buildShortcutChip(String phrase) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        onTap: () {
          // Append phrase to comment field without any side effects
          final currentText = comment.text;
          final newText = currentText.isEmpty ? phrase : '$currentText $phrase';
          comment.text = newText;
          // Move cursor to end
          comment.selection = TextSelection.fromPosition(
            TextPosition(offset: newText.length),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDarkMode(context)
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode(context)
                  ? Colors.grey.shade600
                  : Colors.grey.shade400,
              width: 1,
            ),
          ),
          child: Text(
            phrase,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Poppinsr',
              color: isDarkMode(context)
                  ? Colors.grey.shade300
                  : Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    getCategoryAttributes();
  }

  Map<String, dynamic> reviewAttribute = {};
  Map<String, dynamic> reviewProductAttributes = {};
  VendorModel? vendorModel;

  getCategoryAttributes() async {
    await fireStoreUtils
        .getOrderReviewsbyID(widget.orderId.toString(), widget.product.id)
        .then((value) {
      if (value != null) {
        setState(() {
          ratingModel = value;
          _mediaFiles.addAll(value.photos ?? []);
          ratings = value.rating ?? 0.0;
          comment.text = value.comment.toString();
          reviewAttribute = value.reviewAttributes!;
        });
      }
    });
    await fireStoreUtils.getProductByProductID(widget.product.id).then((value) {
      setState(() {
        productModel = value;

        if (ratingModel != null) {
          reviewCount = value.reviewsCount - 1;
          reviewSum =
              value.reviewsSum - num.parse(ratingModel!.rating.toString());

          if (value.reviewAttributes != null) {
            value.reviewAttributes!.forEach((key, value) {
              ReviewsAttribute reviewsAttributeModel =
                  ReviewsAttribute.fromJson(value);
              reviewsAttributeModel.reviewsCount =
                  reviewsAttributeModel.reviewsCount! - 1;
              reviewsAttributeModel.reviewsSum =
                  reviewsAttributeModel.reviewsSum! - reviewAttribute[key];
              reviewProductAttributes
                  .addEntries([MapEntry(key, reviewsAttributeModel.toJson())]);
            });
          }
        } else {
          reviewCount = value.reviewsCount;
          reviewSum = value.reviewsSum;
          reviewProductAttributes = value.reviewAttributes!;
        }
      });
    });

    vendorModel = await FireStoreUtils.getVendor(productModel!.vendorID);
    if (ratingModel != null) {
      vendorReviewCount = vendorModel!.reviewsCount - 1;
      vendoReviewSum =
          vendorModel!.reviewsSum - num.parse(ratingModel!.rating.toString());
    } else {
      vendorReviewCount = vendorModel!.reviewsCount;
      vendoReviewSum = vendorModel!.reviewsSum;
    }

    await fireStoreUtils
        .getVendorCategoryByCategoryId(widget.product.category_id.toString())
        .then((value) {
      setState(() {
        vendorCategoryModel = value;
      });
    });
    for (var element in vendorCategoryModel!.reviewAttributes!) {
      await fireStoreUtils.getVendorReviewAttribute(element).then((value) {
        reviewAttributeList.add(value!);
      });
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
          backgroundColor: isDarkMode(context)
              ? const Color(DARK_COLOR)
              : const Color(0XFFFDFEFE),
          appBar: AppGlobal.buildSimpleAppBar(
              context, ratingModel != null ? "Update Review" : "Add Review"),
          body: SingleChildScrollView(
              child: Container(
                  padding: const EdgeInsets.only(top: 20, left: 20),
                  child: Form(
                    key: _formKey,
                    child: ratingModel != null
                        ? Column(
                            children: [
                              Card(
                                  color: isDarkMode(context)
                                      ? const Color(0xff35363A)
                                      : const Color(0XFFFDFEFE),
                                  elevation: 1,
                                  margin: const EdgeInsets.only(right: 15),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: SizedBox(
                                      height: 150,
                                      child: Column(children: [
                                        Container(
                                            alignment: Alignment.center,
                                            padding:
                                                const EdgeInsets.only(top: 15),
                                            child: Text(
                                              "Rate For",
                                              style: const TextStyle(
                                                  color: Color(0XFF7C848E),
                                                  fontFamily: 'Poppinsr',
                                                  fontSize: 17),
                                            )),
                                        Container(
                                            alignment: Alignment.center,
                                            child: Text(widget.product.name,
                                                style: TextStyle(
                                                    color: isDarkMode(context)
                                                        ? const Color(
                                                            0XFFFDFEFE)
                                                        : const Color(
                                                            0XFF000003),
                                                    fontFamily: 'Poppinsm',
                                                    fontSize: 20))),
                                        const SizedBox(
                                          height: 15,
                                        ),
                                        RatingBar.builder(
                                          initialRating: ratings,
                                          minRating: 1,
                                          direction: Axis.horizontal,
                                          allowHalfRating: true,
                                          itemCount: 5,
                                          itemPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6.0),
                                          itemBuilder: (context, _) => Icon(
                                            Icons.star,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                          onRatingUpdate: (double rate) {
                                            ratings = rate;
                                            // print(ratings);
                                          },
                                        ),
                                      ]))),
                              const SizedBox(
                                height: 20,
                              ),
                              Card(
                                color: isDarkMode(context)
                                    ? const Color(0xff35363A)
                                    : const Color(0XFFFDFEFE),
                                elevation: 1,
                                margin: const EdgeInsets.only(right: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: ListView.builder(
                                    itemCount: reviewAttributeList.length,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 5),
                                        child: Row(
                                          children: [
                                            Expanded(
                                                child: Text(
                                                    reviewAttributeList[index]
                                                        .title
                                                        .toString())),
                                            RatingBar.builder(
                                              initialRating: reviewAttribute[
                                                      reviewAttributeList[index]
                                                          .id] ??
                                                  0.0,
                                              minRating: 1,
                                              direction: Axis.horizontal,
                                              allowHalfRating: true,
                                              itemCount: 5,
                                              itemSize: 25,
                                              itemPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 2.0),
                                              itemBuilder: (context, _) => Icon(
                                                Icons.star,
                                                color: Color(COLOR_PRIMARY),
                                              ),
                                              onRatingUpdate: (double rate) {
                                                setState(() {
                                                  reviewAttribute.addEntries([
                                                    MapEntry(
                                                        reviewAttributeList[
                                                                index]
                                                            .id
                                                            .toString(),
                                                        rate)
                                                  ]);
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  _pickImage();
                                },
                                child: Card(
                                    color: isDarkMode(context)
                                        ? const Color(0xff35363A)
                                        : const Color(0XFFFDFEFE),
                                    elevation: 1,
                                    margin: const EdgeInsets.only(
                                        right: 15, top: 25),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: SizedBox(
                                        height: 160,
                                        width:
                                            MediaQuery.of(context).size.width *
                                                1,
                                        child: Column(children: [
                                          Container(
                                              padding: const EdgeInsets.only(
                                                  top: 20),
                                              width: 100,
                                              child: const Image(
                                                  image: AssetImage(
                                                      'assets/images/add_img.png'))),
                                          const SizedBox(
                                            height: 10,
                                          ),
                                          Text("Add Images",
                                              style: const TextStyle(
                                                  color: Color(0XFF666666),
                                                  fontFamily: 'Poppinsr',
                                                  fontSize: 16))
                                        ]))),
                              ),
                              _mediaFiles.isEmpty
                                  ? Container()
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                          top: 35, bottom: 20),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: 100,
                                              child: ListView.builder(
                                                itemCount: _mediaFiles.length,
                                                itemBuilder: (context, index) =>
                                                    SizedBox(
                                                        width: 150,
                                                        child: _imageBuilder(
                                                            _mediaFiles[
                                                                index])),
                                                shrinkWrap: true,
                                                scrollDirection:
                                                    Axis.horizontal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              Card(
                                  color: isDarkMode(context)
                                      ? const Color(0xff35363A)
                                      : const Color(0XFFFDFEFE),
                                  elevation: 1,
                                  margin:
                                      const EdgeInsets.only(top: 10, right: 15),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 15,
                                          bottom: 15,
                                          right: 20,
                                          left: 20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                  width: 0.5,
                                                  color:
                                                      const Color(0XFFD1D1E4),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(5)),
                                            constraints: const BoxConstraints(
                                                minHeight: 180, maxHeight: 180),
                                            child: SingleChildScrollView(
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 10),
                                                  child: TextFormField(
                                                    validator:
                                                        validateEmptyField,
                                                    controller: comment,
                                                    textInputAction:
                                                        TextInputAction.next,
                                                    decoration: InputDecoration(
                                                        hintText:
                                                            'Type comment....',
                                                        hintStyle:
                                                            const TextStyle(
                                                                color: Color(
                                                                    0XFF8A8989),
                                                                fontFamily:
                                                                    'Poppinsr'),
                                                        border:
                                                            InputBorder.none),
                                                    maxLines: null,
                                                  )),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            children: [
                                              _buildShortcutChip('Great food!'),
                                              _buildShortcutChip(
                                                  'Fast delivery'),
                                              _buildShortcutChip(
                                                  'Nice presentation'),
                                              _buildShortcutChip(
                                                  'Would order again'),
                                              _buildShortcutChip(
                                                  'Highly recommended'),
                                              _buildShortcutChip('Delicious!'),
                                            ],
                                          ),
                                        ],
                                      ))),
                            ],
                          )
                        : Column(
                            children: [
                              Card(
                                  color: isDarkMode(context)
                                      ? const Color(0xff35363A)
                                      : const Color(0XFFFDFEFE),
                                  elevation: 1,
                                  margin: const EdgeInsets.only(right: 15),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: SizedBox(
                                      height: 150,
                                      child: Column(children: [
                                        Container(
                                            alignment: Alignment.center,
                                            padding:
                                                const EdgeInsets.only(top: 15),
                                            child: Text(
                                              "Rate For",
                                              style: const TextStyle(
                                                  color: Color(0XFF7C848E),
                                                  fontFamily: 'Poppinsr',
                                                  fontSize: 17),
                                            )),
                                        Container(
                                            alignment: Alignment.center,
                                            child: Text(widget.product.name,
                                                style: TextStyle(
                                                    color: isDarkMode(context)
                                                        ? const Color(
                                                            0XFFFDFEFE)
                                                        : const Color(
                                                            0XFF000003),
                                                    fontFamily: 'Poppinsm',
                                                    fontSize: 20))),
                                        const SizedBox(
                                          height: 15,
                                        ),
                                        RatingBar.builder(
                                          initialRating: 0,
                                          minRating: 1,
                                          direction: Axis.horizontal,
                                          allowHalfRating: true,
                                          itemCount: 5,
                                          itemPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6.0),
                                          itemBuilder: (context, _) => Icon(
                                            Icons.star,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                          onRatingUpdate: (double rate) {
                                            ratings = rate;
                                          },
                                        ),
                                      ]))),

                              // SizedBox(height: 20,),

                              Card(
                                color: isDarkMode(context)
                                    ? const Color(0xff35363A)
                                    : const Color(0XFFFDFEFE),
                                elevation: 1,
                                margin: const EdgeInsets.only(right: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                child: ListView.builder(
                                  itemCount: reviewAttributeList.length,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      child: Row(
                                        children: [
                                          Expanded(
                                              child: Text(
                                                  reviewAttributeList[index]
                                                      .title
                                                      .toString())),
                                          RatingBar.builder(
                                            initialRating: reviewAttribute[
                                                    reviewAttributeList[index]
                                                        .id] ??
                                                0.0,
                                            minRating: 1,
                                            direction: Axis.horizontal,
                                            allowHalfRating: true,
                                            itemCount: 5,
                                            itemSize: 25,
                                            itemPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 2.0),
                                            itemBuilder: (context, _) => Icon(
                                              Icons.star,
                                              color: Color(COLOR_PRIMARY),
                                            ),
                                            onRatingUpdate: (double rate) {
                                              setState(() {
                                                reviewAttribute.addEntries([
                                                  MapEntry(
                                                      reviewAttributeList[index]
                                                          .id
                                                          .toString(),
                                                      rate)
                                                ]);
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),

                              Card(
                                  color: isDarkMode(context)
                                      ? const Color(0xff35363A)
                                      : const Color(0XFFFDFEFE),
                                  elevation: 1,
                                  margin:
                                      const EdgeInsets.only(right: 15, top: 25),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: InkWell(
                                    onTap: () {
                                      _pickImage();
                                    },
                                    child: SizedBox(
                                        height: 160,
                                        width:
                                            MediaQuery.of(context).size.width *
                                                1,
                                        child: Column(children: [
                                          Container(
                                              padding: const EdgeInsets.only(
                                                  top: 20),
                                              width: 100,
                                              child: const Image(
                                                  image: AssetImage(
                                                      'assets/images/add_img.png'))),
                                          const SizedBox(
                                            height: 10,
                                          ),
                                          Text("Add Images",
                                              style: const TextStyle(
                                                  color: Color(0XFF666666),
                                                  fontFamily: 'Poppinsr',
                                                  fontSize: 16))
                                        ])),
                                  )),
                              _mediaFiles.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(
                                          top: 35, bottom: 20),
                                      child: Container(
                                        height: 120.0,
                                        width:
                                            MediaQuery.of(context).size.width,
                                        child: ListView.builder(
                                          itemCount: _mediaFiles.length,
                                          itemBuilder: (context, index) =>
                                              _imageBuilder(_mediaFiles[index]),
                                          shrinkWrap: true,
                                          scrollDirection: Axis.horizontal,
                                        ),
                                      ),
                                    )
                                  : const Center(),
                              Card(
                                  color: isDarkMode(context)
                                      ? const Color(0xff35363A)
                                      : const Color(0XFFFDFEFE),
                                  elevation: 1,
                                  margin:
                                      const EdgeInsets.only(top: 10, right: 15),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 15,
                                          bottom: 15,
                                          right: 20,
                                          left: 20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                  width: 0.5,
                                                  color:
                                                      const Color(0XFFD1D1E4),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(5)),
                                            constraints: const BoxConstraints(
                                                minHeight: 180, maxHeight: 180),
                                            child: SingleChildScrollView(
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 10),
                                                  child: TextField(
                                                    controller: comment,
                                                    textInputAction:
                                                        TextInputAction.send,
                                                    decoration: InputDecoration(
                                                        hintText:
                                                            'Type comment....',
                                                        hintStyle:
                                                            const TextStyle(
                                                                color: Color(
                                                                    0XFF8A8989),
                                                                fontFamily:
                                                                    'Poppinsr'),
                                                        border:
                                                            InputBorder.none),
                                                    maxLines: null,
                                                  )),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            children: [
                                              _buildShortcutChip('Great food!'),
                                              _buildShortcutChip(
                                                  'Fast delivery'),
                                              _buildShortcutChip(
                                                  'Nice presentation'),
                                              _buildShortcutChip(
                                                  'Would order again'),
                                              _buildShortcutChip(
                                                  'Highly recommended'),
                                              _buildShortcutChip('Delicious!'),
                                            ],
                                          ),
                                        ],
                                      ))),
                            ],
                          ),
                  ))),
          bottomNavigationBar: ratingModel != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20.0, horizontal: 25),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      backgroundColor: Color(COLOR_PRIMARY),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await showProgress(
                          context, 'Updating data to database...', false);
                      //  if(_mediaFiles is File){
                      List<String> mediaFilesURLs = _mediaFiles
                          .whereType<String>()
                          .toList()
                          .cast<String>();
                      List<File> imagesToUpload =
                          _mediaFiles.whereType<File>().toList().cast<File>();
                      if (imagesToUpload.isNotEmpty) {
                        for (int i = 0; i < imagesToUpload.length; i++) {
                          String url = await fireStoreUtils.uploadProductImage(
                            imagesToUpload[i],
                            'Uploading Review Images ${i + 1} of ${imagesToUpload.length}',
                          );
                          mediaFilesURLs.add(url);
                        }
                      }

                      if (reviewProductAttributes.isEmpty) {
                        reviewAttribute.forEach((key, value) {
                          ReviewsAttribute reviewsAttributeModel =
                              ReviewsAttribute(
                                  reviewsCount: 1, reviewsSum: value);
                          reviewProductAttributes.addEntries(
                              [MapEntry(key, reviewsAttributeModel.toJson())]);
                        });
                      } else {
                        reviewProductAttributes.forEach((key, value) {
                          ReviewsAttribute reviewsAttributeModel =
                              ReviewsAttribute.fromJson(value);
                          reviewsAttributeModel.reviewsCount =
                              reviewsAttributeModel.reviewsCount! + 1;
                          reviewsAttributeModel.reviewsSum =
                              reviewsAttributeModel.reviewsSum! +
                                  reviewAttribute[key];
                          reviewProductAttributes.addEntries(
                              [MapEntry(key, reviewsAttributeModel.toJson())]);
                        });
                      }

                      productModel!.reviewsCount = reviewCount + 1;
                      productModel!.reviewsSum = reviewSum + ratings;
                      productModel!.reviewAttributes = reviewProductAttributes;

                      vendorModel!.reviewsCount = vendorReviewCount + 1;
                      vendorModel!.reviewsSum = vendoReviewSum + ratings;
                      RatingModel ratingproduct = RatingModel(
                          productId: ratingModel!.productId,
                          comment: comment.text,
                          photos: mediaFilesURLs,
                          rating: ratings,
                          customerId: ratingModel!.customerId,
                          id: ratingModel!.id,
                          orderId: ratingModel!.orderId,
                          vendorId: ratingModel!.vendorId,
                          createdAt: Timestamp.now(),
                          uname: MyAppState.currentUser!.firstName +
                              MyAppState.currentUser!.lastName,
                          profile: MyAppState.currentUser!.profilePictureURL,
                          reviewAttributes: reviewAttribute);
                      await FireStoreUtils.updateReviewbyId(ratingproduct);
                      String? errorMessage =
                          await FireStoreUtils.firebaseCreateNewReview(
                              ratingproduct);
                      await FireStoreUtils.updateVendor(vendorModel!);
                      var error =
                          await FireStoreUtils.updateProduct(productModel!);
                      if (errorMessage == null && error != null) {
                        await hideProgress();
                        Navigator.pop(context, OrdersScreen());
                      } else {
                        await hideProgress();
                        Navigator.pop(context, OrdersScreen());
                      }
                    },
                    child: Text(
                      'UPDATE REVIEW',
                      style: TextStyle(
                          fontFamily: 'Poppinsm',
                          color:
                              isDarkMode(context) ? Colors.black : Colors.white,
                          fontSize: 17),
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20.0, horizontal: 25),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      backgroundColor: Color(COLOR_PRIMARY),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => savereview(),
                    child: Text(
                      'SUBMIT REVIEW',
                      style: TextStyle(
                          fontFamily: 'Poppinsm',
                          color:
                              isDarkMode(context) ? Colors.black : Colors.white,
                          fontSize: 17),
                    ),
                  ),
                )
          //
          ),
    );
  }

  savereview() async {
    if (comment.text == '' || ratings == 0) {
      showAlertDialog(
          context, 'Please add All Field', 'All Field Reqired ', true);
    } else if (_formKey.currentState?.validate() ?? false) {
      await showProgress(context, 'Saving data to database...', false);
      List<String> mediaFilesURLs =
          _mediaFiles.whereType<String>().toList().cast<String>();
      List<File> imagesToUpload =
          _mediaFiles.whereType<File>().toList().cast<File>();
      if (imagesToUpload.isNotEmpty) {
        for (int i = 0; i < imagesToUpload.length; i++) {
          String url = await fireStoreUtils.uploadProductImage(
            imagesToUpload[i],
            'Uploading Review Images ${i + 1} of ${imagesToUpload.length}',
          );
          mediaFilesURLs.add(url);
        }
      }

      if (reviewProductAttributes.isEmpty) {
        reviewAttribute.forEach((key, value) {
          ReviewsAttribute reviewsAttributeModel =
              ReviewsAttribute(reviewsCount: 1, reviewsSum: value);
          reviewProductAttributes
              .addEntries([MapEntry(key, reviewsAttributeModel.toJson())]);
        });
      } else {
        reviewProductAttributes.forEach((key, value) {
          ReviewsAttribute reviewsAttributeModel =
              ReviewsAttribute.fromJson(value);
          reviewsAttributeModel.reviewsCount =
              reviewsAttributeModel.reviewsCount! + 1;
          reviewsAttributeModel.reviewsSum =
              reviewsAttributeModel.reviewsSum! + reviewAttribute[key];
          reviewProductAttributes
              .addEntries([MapEntry(key, reviewsAttributeModel.toJson())]);
        });
      }

      productModel!.reviewsCount = reviewCount + 1;
      productModel!.reviewsSum = reviewSum + ratings;
      productModel!.reviewAttributes = reviewProductAttributes;
      //  widget.order.products.first.

      vendorModel!.reviewsCount = vendorReviewCount + 1;
      vendorModel!.reviewsSum = vendoReviewSum + ratings;

      DocumentReference documentReference =
          FirebaseFirestore.instance.collection(Order_Rating).doc();
      RatingModel rate = RatingModel(
          id: documentReference.id,
          productId: widget.product.id,
          comment: comment.text,
          photos: mediaFilesURLs,
          rating: ratings,
          orderId: widget.orderId.toString(),
          vendorId: widget.product.vendorID,
          customerId: MyAppState.currentUser!.userID,
          uname: MyAppState.currentUser!.firstName +
              MyAppState.currentUser!.lastName,
          profile: MyAppState.currentUser!.profilePictureURL,
          createdAt: Timestamp.now(),
          reviewAttributes: reviewAttribute);
      String? errorMessage = await FireStoreUtils.firebaseCreateNewReview(rate);
      await FireStoreUtils.updateVendor(vendorModel!);
      var error = await FireStoreUtils.updateProduct(productModel!);
      if (errorMessage == null && error != null) {
        await hideProgress();
        Navigator.pop(context, OrdersScreen());
        return rate;
      } else {
        return errorMessage;
      }
    }
  }

  showAlertDialog(
      BuildContext context, String title, String content, bool addOkButton) {
    // set up the AlertDialog
    Widget? okButton;
    if (addOkButton) {
      okButton = TextButton(
        child: const Text('OK'),
        onPressed: () {
          Navigator.pop(context);
        },
      );
    }

    if (Platform.isIOS) {
      CupertinoAlertDialog alert = CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [if (okButton != null) okButton],
      );
      showCupertinoDialog(
          context: context,
          builder: (context) {
            return alert;
          });
    } else {
      AlertDialog alert = AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [if (okButton != null) okButton]);

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return alert;
        },
      );
    }
  }

  _pickImage() {
    final action = CupertinoActionSheet(
      message: Text(
        'Add Images',
        style: const TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: const Text('Choose image from gallery'),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              // _mediaFiles.removeLast();
              _mediaFiles.add(File(image.path));
              // _mediaFiles.add(null);
              setState(() {});
            }
          },
        ),
        CupertinoActionSheetAction(
          child: const Text('Take a picture'),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.camera);
            if (image != null) {
              // _mediaFiles.removeLast();
              _mediaFiles.add(File(image.path));
              // _mediaFiles.add(null);
              setState(() {});
            }
          },
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        child: const Text('Cancel'),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }

  _imageBuilder(dynamic image) {
    return Container(
      padding: const EdgeInsets.only(right: 16.0),
      child: Stack(
        alignment: Alignment.topRight,
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 120.0,
            width: 90.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3.0),
              color: isDarkMode(context) ? Colors.black : Colors.blue,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: image is File
                  ? Image.file(
                      image,
                      fit: BoxFit.fill,
                    )
                  : displayImage(image),
            ),
          ),
          Positioned(
            top: -5.0,
            right: -10.0,
            child: InkWell(
              onTap: () {
                _viewOrDeleteImage(image);
              },
              child: const Image(
                image: AssetImage('assets/images/img_cancel.png'),
                width: 25.0,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _viewOrDeleteImage(dynamic image) {
    final action = CupertinoActionSheet(
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(context);
            // _mediaFiles.removeLast();
            if (image is File) {
              setState(() {
                _mediaFiles.removeWhere(
                    (value) => value is File && value.path == image.path);
              });
            } else {
              if (_mediaFiles != _mediaFiles.first) {
                setState(() {
                  _mediaFiles.removeWhere(
                      (value) => value is String && value == image);
                });
              }
            }
            if (_mediaFiles != _mediaFiles.single) {
              setState(() {});
            }
            // _mediaFiles.add(null)
          },
          child: const Text('Remove picture'),
          isDestructiveAction: true,
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            push(
                context,
                image is File
                    ? FullScreenImage(imageFile: image)
                    : FullScreenImage(imageUrl: image));
          },
          isDefaultAction: true,
          child: const Text('View picture'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        child: Text('Cancel'),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }
}
