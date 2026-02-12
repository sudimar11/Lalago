import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
// import 'package:provider/provider.dart';
// import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';

class FoodVarietiesRow extends StatelessWidget {
  const FoodVarietiesRow({Key? key}) : super(key: key);

  final List<String> varieties = const [
    'Chicken',
    'BBQ',
    'Pizza',
    'Cake',
    'Milk Tea',
    'Burger',
    'Coffee',
    'Shawarma',
    'Donut',
    'Takoyaki',
    'Fries',
    'Ice Cream',
    'Sisig',
    'Sushi',
  ];

  static const Map<String, String> _varietyToAsset = {
    'Chicken': 'assets/Varieties/chicken.jpg',
    'BBQ': 'assets/Varieties/BBQ.jpg',
    'Pizza': 'assets/Varieties/pizza.jpg',
    'Cake': 'assets/Varieties/cakes.jpg',
    'Milk Tea': 'assets/Varieties/milk_tea.jpg',
    'Burger': 'assets/Varieties/burgers.jpg',
    'Coffee': 'assets/Varieties/coffee.jpg',
    'Shawarma': 'assets/Varieties/shawarma.jpg',
    'Donut': 'assets/Varieties/donut.jpg',
    'Takoyaki': 'assets/Varieties/takoyaki.jpg',
    'Fries': 'assets/Varieties/fries.jpg',
    'Ice Cream': 'assets/Varieties/ice_cream.jpg',
    'Sisig': 'assets/Varieties/sisig.jpg',
    'Sushi': 'assets/Varieties/sushi.jpg',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDarkMode(context)
          ? const Color(DARK_COLOR)
          : const Color(0xffFFFFFF),
      height: 120,
      child: RepaintBoundary(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          scrollDirection: Axis.horizontal,
          cacheExtent: 200.0,
          itemCount: varieties.length,
          itemBuilder: (context, index) {
          final String label = varieties[index];
          return _VarietyCard(
            label: label,
            imagePath: _varietyToAsset[label] ??
                'assets/Varieties/${label.toLowerCase().replaceAll(' ', '_')}.jpg',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FoodVarietyPage(variety: label),
                ),
              );
            },
          );
        },
        ),
      ),
    );
  }
}

class _VarietyCard extends StatelessWidget {
  final String label;
  final String imagePath;
  final VoidCallback onTap;

  const _VarietyCard(
      {Key? key,
      required this.label,
      required this.imagePath,
      required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 70,
              width: MediaQuery.of(context).size.width * 0.18,
              decoration: BoxDecoration(
                border: Border.all(width: 6, color: Color(COLOR_PRIMARY)),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: dark
                        ? const Color(DarkContainerBorderColor)
                        : Colors.grey.shade100,
                    width: 1,
                  ),
                  color: dark ? const Color(DarkContainerColor) : Colors.white,
                  boxShadow: [
                    dark
                        ? const BoxShadow()
                        : BoxShadow(
                            color: Colors.grey.withOpacity(0.5), blurRadius: 5),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(
                      image: AssetImage(imagePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.18,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dark ? Colors.white : const Color(0xFF000000),
                  fontFamily: "Poppinsr",
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FoodVarietyPage extends StatefulWidget {
  final String variety;

  const FoodVarietyPage({Key? key, required this.variety}) : super(key: key);

  @override
  State<FoodVarietyPage> createState() => _FoodVarietyPageState();
}

class _FoodVarietyPageState extends State<FoodVarietyPage> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();

  late Future<List<ProductModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ProductModel>> _load() async {
    final List<ProductModel> all = await _fireStoreUtils.getAllProducts();
    final String query = widget.variety.toLowerCase();
    return all
        .where((p) => (p.name).toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context)
          ? const Color(DARK_BG_COLOR)
          : const Color(0xffFFFFFF),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDarkMode(context) ? Colors.white : Color(COLOR_PRIMARY),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.variety,
          style: TextStyle(
            fontFamily: "Poppinsm",
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDarkMode(context)
            ? const Color(DARK_COLOR)
            : const Color(0xffFFFFFF),
        elevation: 0,
      ),
      body: FutureBuilder<List<ProductModel>>(
        future: _future,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return showEmptyState('No items found', context);
          }
          final items = snapshot.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.68,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];
              return _ProductTile(product: p);
            },
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductModel product;

  const _ProductTile({Key? key, required this.product}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    final double rating = (product.reviewsCount != 0)
        ? (product.reviewsSum / product.reviewsCount)
        : 0.0;
    return GestureDetector(
      onTap: () async {
        final vendor =
            await FireStoreUtils().getVendorByVendorID(product.vendorID);
        // ignore: use_build_context_synchronously
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(
              productModel: product,
              vendorModel: vendor,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            child: Image.network(
              getImageVAlidUrl(product.photo),
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 120,
                color: Colors.grey.shade200,
                child: const Icon(Icons.image_not_supported),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : const Color(0xff000000),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.star, size: 16, color: Color(COLOR_PRIMARY)),
                const SizedBox(width: 4),
                Text(
                  '${rating.toStringAsFixed(1)} (${product.reviewsCount.toStringAsFixed(0)})',
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    color: dark ? Colors.white70 : const Color(0xff555353),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  color: Color(COLOR_PRIMARY),
                  tooltip: 'View details',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 20,
                  onPressed: () async {
                    final vendor = await FireStoreUtils()
                        .getVendorByVendorID(product.vendorID);
                    // ignore: use_build_context_synchronously
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailsScreen(
                          productModel: product,
                          vendorModel: vendor,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FutureBuilder(
              future: FireStoreUtils().getVendorByVendorID(product.vendorID),
              builder: (context, snapshot) {
                final vendorName = (snapshot.hasData)
                    ? (snapshot.data as dynamic).title.toString()
                    : '...';
                return Text(
                  vendorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    color: dark ? Colors.white70 : const Color(0xff555353),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              amountShow(
                  amount: product.disPrice == null ||
                          product.disPrice == '0' ||
                          product.disPrice!.isEmpty
                      ? product.price
                      : product.disPrice!),
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontWeight: FontWeight.bold,
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
