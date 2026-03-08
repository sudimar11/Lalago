import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/ProductModel.dart';
import 'package:foodie_restaurant/model/categoryModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/addOrUpdateProduct/AddOrUpdateProductScreen.dart';

enum ProductFilter { all, lowStockOnly, outOfStockOnly, trackedOnly, unpublished }

enum ProductSort {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  stockAsc,
  stockDesc,
}

class ManageProductsScreen extends StatefulWidget {
  final void Function(int)? onLowStockCountChanged;

  const ManageProductsScreen({Key? key, this.onLowStockCountChanged})
      : super(key: key);

  @override
  ManageProductsScreenState createState() => ManageProductsScreenState();
}

class ManageProductsScreenState extends State<ManageProductsScreen> {
  FireStoreUtils fireStoreUtils = FireStoreUtils();
  Stream<List<ProductModel>>? productsStream;
  late ProductModel futureproduct;
  late bool publish;
  var product;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  List<ProductModel>? _currentProducts;
  List<ProductModel>? _filteredProducts;
  ProductFilter _filter = ProductFilter.all;
  ProductSort _sort = ProductSort.nameAsc;
  int _lastReportedLowStockCount = -1;

  @override
  void initState() {
    // product = futureproduct;
    //   product = ProductModel;
    //  publish = product.publish;
    /*  productsStream =
        fireStoreUtils.getProductsStream(MyAppState.currentUser!.vendorID);*/

    super.initState();

    productsStream = fireStoreUtils.getProductsStream(MyAppState.currentUser!.vendorID).asBroadcastStream();
  }

  @override
  void dispose() {
    fireStoreUtils.closeProductsStream();
    super.dispose();
  }

  void toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<ProductModel> products) {
    setState(() {
      for (final p in products) _selectedIds.add(p.id);
    });
  }

  List<ProductModel> _applyFilterAndSort(List<ProductModel> products) {
    var list = products.where((p) {
      switch (_filter) {
        case ProductFilter.lowStockOnly:
          return p.isLowStock;
        case ProductFilter.outOfStockOnly:
          return p.trackInventory && p.quantity <= 0;
        case ProductFilter.trackedOnly:
          return p.trackInventory;
        case ProductFilter.unpublished:
          return !p.publish;
        case ProductFilter.all:
          return true;
      }
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case ProductSort.nameAsc:
          return (a.name).toLowerCase().compareTo((b.name).toLowerCase());
        case ProductSort.nameDesc:
          return (b.name).toLowerCase().compareTo((a.name).toLowerCase());
        case ProductSort.priceAsc:
          return (double.tryParse(a.price) ?? 0)
              .compareTo(double.tryParse(b.price) ?? 0);
        case ProductSort.priceDesc:
          return (double.tryParse(b.price) ?? 0)
              .compareTo(double.tryParse(a.price) ?? 0);
        case ProductSort.stockAsc:
          return a.quantity.compareTo(b.quantity);
        case ProductSort.stockDesc:
          return b.quantity.compareTo(a.quantity);
      }
    });
    return list;
  }

  String _sortLabel(ProductSort s) {
    switch (s) {
      case ProductSort.nameAsc:
        return 'Name A-Z';
      case ProductSort.nameDesc:
        return 'Name Z-A';
      case ProductSort.priceAsc:
        return 'Price Low';
      case ProductSort.priceDesc:
        return 'Price High';
      case ProductSort.stockAsc:
        return 'Stock Low';
      case ProductSort.stockDesc:
        return 'Stock High';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context) ? Color(COLOR_DARK) : null,
        floatingActionButton: _isSelectionMode ? null : Padding(
          padding: const EdgeInsets.all(8.0),
          child: FloatingActionButton(
            elevation: 10,
            onPressed: () {
              if (MyAppState.currentUser!.vendorID.isEmpty) {
                final snackBar = SnackBar(
                  content: const Text('Please add a restaurant first'),
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              } else {
                push(
                  context,
                  AddOrUpdateProductScreen(product: null),
                );
              }
            },
            child: Image(
              image: AssetImage('assets/images/plus.png'),
              width: 55,
            ),
          ),
        ),
        body: Column(
          children: [
            if (_isSelectionMode)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: isDarkMode(context)
                    ? Color(DARK_VIEWBG_COLOR)
                    : Colors.grey.shade200,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        final data = _filteredProducts ?? _currentProducts;
                        if (data != null) _selectAll(data);
                      },
                      child: Text('Select All'),
                    ),
                    Spacer(),
                    Text('${_selectedIds.length} selected'),
                    SizedBox(width: 8),
                    TextButton(
                      onPressed: toggleSelectionMode,
                      child: Text('Done'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width * 1,
                  height: MediaQuery.of(context).size.height * 0.9,
                  child: Stack(children: [
                    StreamBuilder<List<ProductModel>>(
                      stream: productsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            fireStoreUtils.isShowLoader != true) {
                          return Container(
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (!snapshot.hasData ||
                            (snapshot.data?.isEmpty ?? true)) {
                          return Container(
                            height: MediaQuery.of(context).size.height * 0.9,
                            alignment: Alignment.center,
                            child: showEmptyState(
                                'No Products',
                                'All your products will show up here'),
                          );
                        }
                        final products = snapshot.data!;
                        _currentProducts = products;
                        final lowStockCount =
                            products.where((p) => p.isLowStock).length;
                        if (lowStockCount != _lastReportedLowStockCount) {
                          _lastReportedLowStockCount = lowStockCount;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            widget.onLowStockCountChanged?.call(lowStockCount);
                          });
                        }
                        final filtered = _applyFilterAndSort(products);
                        _filteredProducts = filtered;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Wrap(
                                spacing: 6,
                                children: [
                                  ChoiceChip(
                                    label: Text('All'),
                                    selected: _filter == ProductFilter.all,
                                    onSelected: (_) =>
                                        setState(() => _filter = ProductFilter.all),
                                  ),
                                  ChoiceChip(
                                    label: Text('Low Stock'),
                                    selected:
                                        _filter == ProductFilter.lowStockOnly,
                                    onSelected: (_) => setState(
                                        () => _filter = ProductFilter.lowStockOnly),
                                  ),
                                  ChoiceChip(
                                    label: Text('Out of Stock'),
                                    selected: _filter ==
                                        ProductFilter.outOfStockOnly,
                                    onSelected: (_) => setState(() =>
                                        _filter = ProductFilter.outOfStockOnly),
                                  ),
                                  ChoiceChip(
                                    label: Text('Tracked'),
                                    selected:
                                        _filter == ProductFilter.trackedOnly,
                                    onSelected: (_) => setState(
                                        () => _filter = ProductFilter.trackedOnly),
                                  ),
                                  ChoiceChip(
                                    label: Text('Unpublished'),
                                    selected:
                                        _filter == ProductFilter.unpublished,
                                    onSelected: (_) => setState(
                                        () => _filter = ProductFilter.unpublished),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: DropdownButton<ProductSort>(
                                value: _sort,
                                isExpanded: false,
                                underline: SizedBox(),
                                items: ProductSort.values
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(_sortLabel(s)),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _sort = v);
                                },
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                padding: const EdgeInsets.all(12),
                                itemBuilder: (context, index) =>
                                    buildRow(filtered[index]),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ),
            if (_isSelectionMode && _selectedIds.isNotEmpty)
              _buildBulkActionsBar(),
          ],
        ));
  }

  Widget buildRow(ProductModel productModel) {
    final isSelected = _selectedIds.contains(productModel.id);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(productModel.id);
        } else {
          push(context, AddOrUpdateProductScreen(product: productModel));
        }
      },
      onLongPress: () => _showQuickInventorySheet(productModel),
      child: Container(
        margin: EdgeInsets.fromLTRB(7, 7, 7, 7),
        child: Card(
          color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10), // if you need this
            side: BorderSide(
              color: Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Container(
            height: 185,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8.0,
                ),
                child: SingleChildScrollView(
                  child: Column(children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (_isSelectionMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, right: 8),
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(productModel.id),
                              activeColor: Color(COLOR_PRIMARY),
                            ),
                          ),
                        Container(
                            width: MediaQuery.of(context).size.width * 0.25,
                            height: MediaQuery.of(context).size.height * 0.1,
                            margin: EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(productModel.photo), fit: BoxFit.cover))),
                        SizedBox(
                          width: 20,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  productModel.name,
                                  style: TextStyle(fontSize: 17, fontFamily: "Poppins", color: isDarkMode(context) ? Colors.white : Color.fromRGBO(0, 0, 0, 100)),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  productModel.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontFamily: "Poppins", color: isDarkMode(context) ? Colors.white : Color(0xff5E5C5C)),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Visibility(
                                            visible: productModel.disPrice.toString() != "0",
                                            child: Row(
                                              children: [
                                                Text(
                                                  amountShow(amount: productModel.disPrice.toString()),
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontFamily: "Poppinssm",
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(COLOR_PRIMARY),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 7,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            amountShow(amount: productModel.price.toString()),
                                            style: TextStyle(
                                                fontSize: 18,
                                                decoration: productModel.disPrice.toString() != "0" ? TextDecoration.lineThrough : null,
                                                fontFamily: "Poppinssm",
                                                color: productModel.disPrice.toString() == "0" ? Color(COLOR_PRIMARY) : Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(productModel.reviewsCount != 0 ? (productModel.reviewsSum / productModel.reviewsCount).toStringAsFixed(1) : 0.toString(),
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
                                    if (productModel.trackInventory)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: productModel.isLowStock
                                                ? Colors.orange
                                                : Color(COLOR_PRIMARY),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.inventory_2,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                'Qty: ${productModel.quantity}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Visibility(
                                  visible: productModel.addOnsTitle.length != 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      showModalBottomSheet(
                                          context: context,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10.0),
                                          ),
                                          backgroundColor: Colors.white,
                                          enableDrag: true,
                                          isScrollControlled: true,
                                          builder: (context) {
                                            return bottomSheetViewAll(context, productModel);
                                          });
                                    },
                                    child: Column(
                                      children: [
                                        SizedBox(height: 8),
                                        Text(
                                          "Addons",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontFamily: "Poppins",
                                            fontWeight: FontWeight.w400,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                        )
                                        // Text("("+productModel.size.join(",")+")"),
                                      ],
                                    ),
                                  ),
                                ),
                                /* Visibility(
                                  visible: productModel.addOnsTitle.length!=0,
                                  child: Column(
                                    children: [
                                      SizedBox(height: 8),
                                      Text("("+productModel.addOnsTitle.join(",")+")")

                                    ],
                                  ),
                                ),*/
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Padding(padding: EdgeInsets.fromLTRB(0, 5, 0,0)),
                    Divider(color: Color(0xFFC8D2DF), height: 0.1),
                    Padding(
                        padding: EdgeInsets.only(top: 0, left: 0),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                          Expanded(
                            child: Row(
                              children: [
                                IconButton(
                                    onPressed: () => showProductOptionsSheet(productModel),
                                    icon: Image(
                                      image: AssetImage('assets/images/delete.png'),
                                      width: 20,
                                    )),
                                Text(
                                  "Delete",
                                  style: TextStyle(fontSize: 15, color: isDarkMode(context) ? Colors.white : Color(0XFF768296), fontFamily: "Poppins"),
                                )
                              ],
                            ),
                          ),

                          Container(
                            margin: EdgeInsets.only(right: 0),
                            child: Image(
                              image: AssetImage("assets/images/verti_divider.png"),
                              height: 30,
                            ),
                          ),
                          // SizedBox(width: 0,),
                          /*VerticalDivider(
                                  color: Colors.amber, thickness: 2, width: 10),*/
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: Color(COLOR_ACCENT),
                                  title: Text('Publish',
                                      textAlign: TextAlign.end, style: TextStyle(fontSize: 15, color: isDarkMode(context) ? Colors.white : Color(0XFF768296), fontFamily: "Poppins")),
                                  value: productModel.publish,
                                  onChanged: (bool newValue) async {
                                    productModel.publish = newValue;
                                    await fireStoreUtils.addOrUpdateProduct(productModel);

                                    setState(() {});
                                  })
                            ],
                          ))
                        ]))
                  ]),
                )),
          ),
        ),
      ),
    );
  }

  Widget bottomSheetViewAll(BuildContext context, ProductModel productModel) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 7,
            margin: EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: new BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              child: Stack(children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 15,
                      ),
                      Text(
                        productModel.name,
                        style: TextStyle(fontFamily: "Poppinsb", fontSize: 17, color: Color(0xff000000)),
                      ),
                      SizedBox(
                        height: 15,
                      ),
                      Row(
                        children: [
                          Visibility(
                            visible: productModel.disPrice.toString() != "0",
                            child: Row(
                              children: [
                                Text(
                                  amountShow(amount: productModel.disPrice.toString()),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontFamily: "Poppinssm",
                                    fontWeight: FontWeight.bold,
                                    color: Color(COLOR_PRIMARY),
                                  ),
                                ),
                                SizedBox(
                                  width: 7,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            amountShow(amount: productModel.price.toString()),
                            style: TextStyle(
                                fontSize: 18,
                                decoration: productModel.disPrice.toString() != "0" ? TextDecoration.lineThrough : null,
                                fontFamily: "Poppinssm",
                                color: productModel.disPrice.toString() == "0" ? Color(COLOR_PRIMARY) : Colors.grey),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 15,
                      ),
                      Text(
                        productModel.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontFamily: "Poppinsm", color: isDarkMode(context) ? Colors.white : Color(0xff5E5C5C)),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Visibility(
                        visible: productModel.addOnsTitle.isNotEmpty,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Addons",
                              style: TextStyle(fontFamily: "Poppinsb", fontSize: 15, color: Color(0xff000000)),
                            ),
                            SizedBox(
                              height: 15,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: productModel.addOnsTitle
                                      .map((data) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            child: Text(data, style: TextStyle(fontSize: 18, fontFamily: "Poppins", fontWeight: FontWeight.normal, color: Colors.grey)),
                                          ))
                                      .toList(),
                                ),
                                Expanded(child: SizedBox()),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: productModel.addOnsPrice
                                      .map((data) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            child: Text(amountShow(amount: data.toString()),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontFamily: "Poppinssm",
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(COLOR_PRIMARY),
                                                )),
                                          ))
                                      .toList(),
                                )
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ]),
            ),
          ),
          Align(
            alignment: Alignment(0, -1.35),
            child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height * 0.3,
                margin: EdgeInsets.only(right: 10, left: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(productModel.photo), fit: BoxFit.cover))),
          ),
        ],
      ),
    );
  }

  void _showQuickInventorySheet(ProductModel product) {
    final qtyController = TextEditingController(text: product.quantity.toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDarkMode(ctx) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(ctx) ? Colors.white : Colors.black,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          final n = int.tryParse(qtyController.text) ?? 0;
                          qtyController.text = (n - 1).toString();
                          setModalState(() {});
                        },
                        icon: Icon(Icons.remove_circle, color: Color(COLOR_PRIMARY)),
                      ),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.numberWithOptions(signed: true),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final n = int.tryParse(qtyController.text) ?? 0;
                          qtyController.text = (n + 1).toString();
                          setModalState(() {});
                        },
                        icon: Icon(Icons.add_circle, color: Color(COLOR_PRIMARY)),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final text = qtyController.text;
                      final qty = int.tryParse(text);
                      if (qty == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Enter a valid number')),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        await fireStoreUtils.updateProductStock(product.id, qty);
                        if (mounted) EasyLoading.showSuccess('Stock updated');
                      } catch (e) {
                        if (mounted) EasyLoading.showError('Failed: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(COLOR_PRIMARY),
                    ),
                    child: Text('Save'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBulkActionsBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _showBulkCategoryDialog,
              icon: Icon(Icons.category, size: 18),
              label: Text('Category'),
            ),
            TextButton.icon(
              onPressed: _showBulkPublishDialog,
              icon: Icon(Icons.publish, size: 18),
              label: Text('Publish'),
            ),
            TextButton.icon(
              onPressed: _showBulkDeleteDialog,
              icon: Icon(Icons.delete, size: 18),
              label: Text('Delete'),
            ),
            TextButton.icon(
              onPressed: _showBulkStockDialog,
              icon: Icon(Icons.inventory, size: 18),
              label: Text('Stock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBulkCategoryDialog() async {
    final categories = await FireStoreUtils.getVendorCategoryById();
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No categories available')),
      );
      return;
    }
    VendorCategoryModel selected = categories.first;
    final cat = await showDialog<VendorCategoryModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Bulk Edit Category'),
          content: DropdownButtonFormField<VendorCategoryModel>(
            value: selected,
            items: categories
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.title ?? ''),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setModalState(() => selected = v);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (cat == null) return;
    if (cat.id == null || cat.id!.isEmpty) return;
    try {
      await fireStoreUtils.bulkUpdateProductsCategory(
          _selectedIds.toList(), cat.id!);
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) EasyLoading.showSuccess('Category updated');
    } catch (e) {
      if (mounted) EasyLoading.showError('Failed: $e');
    }
  }

  Future<void> _showBulkPublishDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bulk Publish Toggle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Publish Selected'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              title: Text('Unpublish Selected'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await fireStoreUtils.bulkUpdateProductsPublishStatus(
          _selectedIds.toList(), result);
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) EasyLoading.showSuccess(result ? 'Published' : 'Unpublished');
    } catch (e) {
      if (mounted) EasyLoading.showError('Failed: $e');
    }
  }

  Future<void> _showBulkDeleteDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bulk Delete'),
        content: Text(
          'Delete ${_selectedIds.length} products? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await fireStoreUtils.bulkDeleteProducts(_selectedIds.toList());
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) EasyLoading.showSuccess('Products deleted');
    } catch (e) {
      if (mounted) EasyLoading.showError('Failed: $e');
    }
  }

  Future<void> _showBulkStockDialog() async {
    final ctrl = TextEditingController(text: '0');
    String op = 'set';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Bulk Stock Update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.numberWithOptions(signed: false),
                decoration: InputDecoration(labelText: 'Value'),
              ),
              SizedBox(height: 12),
              Wrap(
                children: [
                  ChoiceChip(
                    label: Text('Set to value'),
                    selected: op == 'set',
                    onSelected: (_) => setModalState(() => op = 'set'),
                  ),
                  SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Increase by'),
                    selected: op == 'increment',
                    onSelected: (_) => setModalState(() => op = 'increment'),
                  ),
                  SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Decrease by'),
                    selected: op == 'decrement',
                    onSelected: (_) => setModalState(() => op = 'decrement'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text);
                if (v != null) Navigator.pop(ctx, {'value': v, 'op': op});
              },
              child: Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final v = result['value'] as int?;
    final operation = result['op'] as String? ?? 'set';
    if (v == null) return;
    try {
      await fireStoreUtils.bulkUpdateProductsStock(
          _selectedIds.toList(), v,
          operation: operation);
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) EasyLoading.showSuccess('Stock updated');
    } catch (e) {
      if (mounted) EasyLoading.showError('Failed: $e');
    }
  }

  showProductOptionsSheet(ProductModel productModel) {
    final action = CupertinoActionSheet(
      message: Text(
        'Are you sure you want to delete this product?',
        style: TextStyle(fontSize: 15.0),
      ),
      title: Text(
        '${productModel.name}',
        style: TextStyle(fontSize: 17.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text("YesSureToDelete"),
          isDestructiveAction: true,
          onPressed: () async {
            Navigator.pop(context);
            fireStoreUtils.deleteProduct(productModel.id);
          },
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
