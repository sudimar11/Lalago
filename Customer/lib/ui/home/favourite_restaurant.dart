import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/model/FavouriteItemModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';

class FavouriteRestaurantScreen extends StatefulWidget {
  const FavouriteRestaurantScreen({Key? key}) : super(key: key);

  @override
  _FavouriteRestaurantScreenState createState() =>
      _FavouriteRestaurantScreenState();
}

class _FavouriteRestaurantScreenState extends State<FavouriteRestaurantScreen>
    with TickerProviderStateMixin {
  late Future<List<VendorModel>> vendorFuture;
  final fireStoreUtils = FireStoreUtils();
  List<VendorModel> storeAllLst = [];
  List<FavouriteModel> lstFavourite = [];
  List<FavouriteItemModel> lstFavouriteItems = [];
  List<ProductModel> favProductList = [];
  var position = const LatLng(23.12, 70.22);
  bool showLoader = true;
  String placeHolderImage = "";
  VendorModel? vendorModel;
  late CartDatabase cartDatabase;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    FireStoreUtils.getplaceholderimage().then((value) {
      placeHolderImage = value ?? "";
    });
    getData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false, // keepr it aligned to the left
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Favorite',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 18,
              color: Colors.black,
            ),
          ),
          actions: [
            StreamBuilder<List<CartProduct>>(
              stream: cartDatabase.watchProducts,
              initialData: const [],
              builder: (context, snapshot) {
                int cartCount = 0;
                if (snapshot.hasData) {
                  cartCount = snapshot.data!
                      .fold(0, (sum, item) => sum + item.quantity);
                }
                return Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shopping_cart, color: Colors.black),
                      onPressed: () {
                        push(context, CartScreen());
                      },
                    ),
                    if (cartCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Color(COLOR_PRIMARY),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            cartCount.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Color(COLOR_PRIMARY),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(COLOR_PRIMARY),
            tabs: [
              Tab(text: 'Restaurants'),
              Tab(text: 'Foods'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Restaurants Tab
            showLoader
                ? Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    ),
                  )
                : lstFavourite.isEmpty
                    ? showEmptyState('No Favourite Restaurant', context)
                    : ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        itemCount: lstFavourite.length,
                        itemBuilder: (context, index) {
                          if (storeAllLst.isNotEmpty) {
                            for (int a = 0; a < storeAllLst.length; a++) {
                              if (storeAllLst[a].id ==
                                  lstFavourite[index].restaurantId) {
                                vendorModel = storeAllLst[a];
                              } else {}
                            }
                          }
                          return vendorModel == null
                              ? Container()
                              : buildAllStoreData(vendorModel!, index);
                        }),
            // Foods Tab
            showLoader
                ? Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    ),
                  )
                : favProductList.isEmpty
                    ? showEmptyState('No Favourite Foods', context)
                    : ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        itemCount: favProductList.length,
                        itemBuilder: (context, index) {
                          ProductModel? productModel = favProductList[index];
                          return buildFoodItem(productModel, index);
                        }),
          ],
        ));
  }

  Widget buildAllStoreData(VendorModel vendorModel, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: GestureDetector(
        onTap: () => push(
          context,
          NewVendorProductsScreen(vendorModel: vendorModel),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade100, width: 1),
            boxShadow: [
              isDarkMode(context)
                  ? const BoxShadow()
                  : BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      blurRadius: 5,
                    ),
            ],
          ),
          width: MediaQuery.of(context).size.width * 0.8,
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(vendorModel.photo),
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
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: placeHolderImage,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vendorModel.title,
                            style: const TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 18,
                              color: Color(0xff000000),
                            ),
                            maxLines: 1,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              FavouriteModel favouriteModel = FavouriteModel(
                                  restaurantId: vendorModel.id,
                                  userId: MyAppState.currentUser!.userID);
                              lstFavourite.removeWhere((item) =>
                                  item.restaurantId == vendorModel.id);
                              fireStoreUtils
                                  .removeFavouriteRestaurant(favouriteModel);
                            });
                          },
                          child: Icon(
                            Icons.favorite,
                            color: Color(COLOR_PRIMARY),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      vendorModel.location,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: "Poppinsm",
                        fontSize: 16,
                        color: Color(0xff9091A4),
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
                            style: const TextStyle(
                              fontFamily: "Poppinsm",
                              letterSpacing: 0.5,
                              color: Color(0xff000000),
                            )),
                        const SizedBox(width: 3),
                        Text('(${vendorModel.reviewsCount.toStringAsFixed(1)})',
                            style: const TextStyle(
                              fontFamily: "Poppinsm",
                              letterSpacing: 0.5,
                              color: Color(0xff666666),
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
      ),
    );
  }

  Widget buildFoodItem(ProductModel productModel, int index) {
    return GestureDetector(
      onTap: () async {
        VendorModel? vendorModel =
            await FireStoreUtils.getVendor(productModel.vendorID);
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
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade100, width: 1),
            boxShadow: [
              isDarkMode(context)
                  ? const BoxShadow()
                  : BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      blurRadius: 5,
                    ),
            ],
          ),
          width: MediaQuery.of(context).size.width * 0.8,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: productModel.photo,
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
                        imageUrl: placeHolderImage,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            productModel.name,
                            style: const TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 18,
                              color: Color(0xff000000),
                            ),
                            maxLines: 1,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              FavouriteItemModel favouriteModel =
                                  FavouriteItemModel(
                                      productId: productModel.id,
                                      storeId: productModel.vendorID,
                                      userId: MyAppState.currentUser!.userID);
                              lstFavouriteItems.removeWhere(
                                  (item) => item.productId == productModel.id);
                              favProductList.removeWhere(
                                  (item) => item.id == productModel.id);
                              FireStoreUtils()
                                  .removeFavouriteItem(favouriteModel);
                            });
                          },
                          child: Icon(
                            Icons.favorite,
                            color: Color(COLOR_PRIMARY),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(
                      height: 5,
                    ),
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
                                productModel.reviewsCount != 0
                                    ? (productModel.reviewsSum /
                                            productModel.reviewsCount)
                                        .toStringAsFixed(1)
                                    : 0.toString(),
                                style: const TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  fontSize: 12,
                                  color: Colors.white,
                                )),
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
                    const SizedBox(
                      height: 5,
                    ),
                    productModel.disPrice == "" || productModel.disPrice == "0"
                        ? Text(
                            amountShow(amount: productModel.price),
                            style: TextStyle(
                                fontSize: 16, color: Color(COLOR_PRIMARY)),
                          )
                        : Row(
                            children: [
                              Text(
                                "${amountShow(amount: productModel.disPrice)}",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(COLOR_PRIMARY),
                                ),
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Text(
                                '${amountShow(amount: productModel.price)}',
                                style: const TextStyle(
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
      ),
    );
  }

  void getData() {
    // Load favorite restaurants
    fireStoreUtils
        .getFavouriteRestaurant(MyAppState.currentUser!.userID)
        .then((value) {
      setState(() {
        lstFavourite.clear();
        lstFavourite.addAll(value);
      });
    });
    vendorFuture = fireStoreUtils.getVendors();

    vendorFuture.then((value) {
      setState(() {
        storeAllLst.clear();
        storeAllLst.addAll(value);
      });
    });

    // Load favorite foods
    fireStoreUtils
        .getFavouritesProductList(MyAppState.currentUser!.userID)
        .then((value) {
      setState(() {
        lstFavouriteItems.clear();
        lstFavouriteItems.addAll(value);
      });
    });

    fireStoreUtils.getAllProducts().then((value) {
      setState(() {
        favProductList.clear();
        lstFavouriteItems.forEach((element) {
          final bool _productIsInList =
              value.any((product) => product.id == element.productId);
          if (_productIsInList) {
            ProductModel productModel =
                value.firstWhere((product) => product.id == element.productId);
            favProductList.add(productModel);
          }
        });
        showLoader = false;
      });
    });
  }
}
