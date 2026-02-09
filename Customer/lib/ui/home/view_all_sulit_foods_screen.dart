import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';

class ViewAllSulitFoodsScreen extends StatefulWidget {
  final List<ProductModel> sulitProducts;
  final List<VendorModel> vendors;

  const ViewAllSulitFoodsScreen({
    Key? key,
    required this.sulitProducts,
    required this.vendors,
  }) : super(key: key);

  @override
  State<ViewAllSulitFoodsScreen> createState() =>
      _ViewAllSulitFoodsScreenState();
}

class _ViewAllSulitFoodsScreenState extends State<ViewAllSulitFoodsScreen> {
  List<ProductModel> filteredProducts = [];
  TextEditingController searchController = TextEditingController();
  static const double sulitCap = 150.0;

  @override
  void initState() {
    super.initState();
    // Always enforce sulit cap (<= sulitCap) and no artificial limit
    filteredProducts = widget.sulitProducts.where((product) {
      final double price = double.tryParse(product.price) ?? 0.0;
      return price > 0 && price <= sulitCap;
    }).toList();

    // Shuffle to show variety each time
    filteredProducts.shuffle();
  }

  void filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredProducts = widget.sulitProducts.where((product) {
          final double price = double.tryParse(product.price) ?? 0.0;
          return price > 0 && price <= sulitCap;
        }).toList();
      } else {
        filteredProducts = widget.sulitProducts.where((product) {
          final bool matchesQuery = product.name
                  .toLowerCase()
                  .contains(query.toLowerCase()) ||
              product.description.toLowerCase().contains(query.toLowerCase());
          final double price = double.tryParse(product.price) ?? 0.0;
          final bool withinCap = price > 0 && price <= sulitCap;
          return matchesQuery && withinCap;
        }).toList();
      }
    });
  }

  VendorModel? getVendorForProduct(String vendorId) {
    try {
      return widget.vendors.firstWhere((vendor) => vendor.id == vendorId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? Color(DARK_COLOR) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDarkMode(context) ? Color(DARK_COLOR) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Meal for One • Sulit Prices",
          style: TextStyle(
            fontFamily: 'Poppinssb',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDarkMode(context) ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(COLOR_PRIMARY).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(COLOR_PRIMARY).withOpacity(0.3)),
            ),
            child: Text(
              "₱${sulitCap.toStringAsFixed(0)} & below",
              style: TextStyle(
                fontFamily: 'Poppinssb',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: searchController,
              onChanged: filterProducts,
              decoration: InputDecoration(
                hintText: "Search sulit foods...",
                hintStyle: TextStyle(
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade600,
                  fontFamily: 'Poppinsr',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade600,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black87,
                fontFamily: 'Poppinsr',
              ),
            ),
          ),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  "${filteredProducts.length} sulit foods found",
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode(context)
                        ? Colors.white70
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Products Grid
          Expanded(
            child: filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: isDarkMode(context)
                              ? Colors.white54
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchController.text.isEmpty
                              ? "No sulit foods available"
                              : "No foods found for '${searchController.text}'",
                          style: TextStyle(
                            fontFamily: 'Poppinsr',
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      ProductModel product = filteredProducts[index];
                      VendorModel? vendor =
                          getVendorForProduct(product.vendorID);
                      final bool isRestaurantOpen = vendor != null
                          ? checkRestaurantOpen(vendor.toJson())
                          : true;

                      return GestureDetector(
                        onTap: () {
                          if (vendor != null) {
                            push(
                              context,
                              ProductDetailsScreen(
                                productModel: product,
                                vendorModel: vendor,
                              ),
                            );
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Color(DARK_CARD_BG_COLOR)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isDarkMode(context)
                                  ? Color(DarkContainerBorderColor)
                                  : Colors.grey.shade100,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Product Image with vendor badge
                              Expanded(
                                flex: 3,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl:
                                              getImageVAlidUrl(product.photo),
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                topRight: Radius.circular(16),
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.restaurant,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                topRight: Radius.circular(16),
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.error,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Vendor logo badge
                                    if (vendor != null)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: CachedNetworkImage(
                                              imageUrl: getImageVAlidUrl(
                                                  vendor.photo),
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  const Center(
                                                child: Icon(
                                                  Icons.restaurant,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Center(
                                                child: Icon(
                                                  Icons.restaurant,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Sulit badge
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(COLOR_PRIMARY),
                                              Color(COLOR_PRIMARY)
                                                  .withOpacity(0.8),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(COLOR_PRIMARY)
                                                  .withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          'SULIT',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!isRestaurantOpen)
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                            ),
                                            color:
                                                Colors.black.withOpacity(0.6),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'Restaurant is closed',
                                              style: TextStyle(
                                                fontFamily: 'Poppinsm',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Product details
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Product name
                                      Expanded(
                                        child: Text(
                                          product.name,
                                          style: TextStyle(
                                            fontFamily: 'Poppinssb',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDarkMode(context)
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      // Price
                                      Text(
                                        '₱ ${product.price}',
                                        style: TextStyle(
                                          fontFamily: 'Poppinsb',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(COLOR_PRIMARY),
                                        ),
                                      ),

                                      // ETA and Delivery Fee
                                      if (vendor != null)
                                        RestaurantEtaFeeRow(
                                          vendorModel: vendor,
                                          currencyModel: null,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
