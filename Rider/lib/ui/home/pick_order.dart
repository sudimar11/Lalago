import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/OrderProductModel.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/order_location_service.dart';

class PickOrder extends StatefulWidget {
  final OrderModel? currentOrder;

  PickOrder({
    Key? key,
    required this.currentOrder,
  }) : super(key: key);

  @override
  _PickOrderState createState() => _PickOrderState();
}

class _PickOrderState extends State<PickOrder> {
  bool _value = false;
  int val = -1;
  bool _isNearRestaurant = false;
  StreamSubscription<bool>? _proximitySubscription;
  final Map<String, Map<String, dynamic>> _availabilityByProductId = {};
  bool _isAvailabilityLoading = false;
  final Map<String, Map<String, dynamic>> _replacementsByProductId = {};

  @override
  void initState() {
    super.initState();
    _checkProximity();
    _loadAvailability();
    _proximitySubscription = OrderLocationService.proximityStream.listen(
      (isNear) {
        if (mounted) {
          setState(() {
            _isNearRestaurant = isNear;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _proximitySubscription?.cancel();
    super.dispose();
  }

  void _checkProximity() async {
    final driverLocation = MyAppState.currentUser?.location;
    if (driverLocation != null && widget.currentOrder != null) {
      _isNearRestaurant = OrderLocationService.isNearRestaurant(
          widget.currentOrder!, driverLocation);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadAvailability() async {
    if (widget.currentOrder == null) return;
    final ids = widget.currentOrder!.products
        .map((product) => product.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    setState(() {
      _isAvailabilityLoading = true;
    });

    final Map<String, Map<String, dynamic>> next = {};
    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('vendor_products')
            .doc(id)
            .get();
        if (doc.exists) {
          final data = doc.data();
          next[id] = {
            'availabilityStatus': data?['availabilityStatus'],
            'unavailableReason': data?['unavailableReason'],
          };
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _availabilityByProductId
        ..clear()
        ..addAll(next);
      _isAvailabilityLoading = false;
    });
  }

  String _readOrderVendorId() {
    final order = widget.currentOrder;
    if (order == null) return '';
    if (order.vendorID.isNotEmpty) return order.vendorID;
    final vendorId = order.vendor.id;
    return vendorId;
  }

  String _readFoodName(Map<String, dynamic> data) {
    final value = (data['name'] ??
            data['title'] ??
            data['product_name'] ??
            data['productName'] ??
            'Food')
        .toString();
    return value.isEmpty ? 'Food' : value;
  }

  String _readFoodCategoryId(Map<String, dynamic> data) {
    final value = (data['categoryId'] ?? data['category_id'] ?? '').toString();
    return value;
  }

  String _readFoodPhoto(Map<String, dynamic> data) {
    final value = (data['photo'] ??
            data['image'] ??
            data['imageUrl'] ??
            data['thumbnail'] ??
            data['picture'] ??
            '')
        .toString();
    return value;
  }

  Future<List<Map<String, dynamic>>> _loadVendorAvailableFoods(
    String vendorId,
  ) async {
    if (vendorId.isEmpty) return [];
    final collection =
        FirebaseFirestore.instance.collection('vendor_products');

    final queries = [
      collection
          .where('publish', isEqualTo: true)
          .where('vendorId', isEqualTo: vendorId)
          .get(),
      collection
          .where('publish', isEqualTo: true)
          .where('vendorID', isEqualTo: vendorId)
          .get(),
      collection
          .where('publish', isEqualTo: true)
          .where('vendor_id', isEqualTo: vendorId)
          .get(),
    ];

    final results = await Future.wait(queries);
    final Map<String, Map<String, dynamic>> foodsById = {};

    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        foodsById[doc.id] = {
          'id': doc.id,
          'name': _readFoodName(data),
          'categoryId': _readFoodCategoryId(data),
          'photo': _readFoodPhoto(data),
        };
      }
    }

    return foodsById.values.toList();
  }

  List<Map<String, dynamic>> _buildReplacementCandidates(
    OrderProductModel product,
    List<Map<String, dynamic>> foods,
  ) {
    final categoryId = product.categoryId;
    if (categoryId.isEmpty) {
      return foods;
    }

    final sameCategory = foods
        .where((food) => food['categoryId']?.toString() == categoryId)
        .toList();
    final sameCategoryIds = sameCategory
        .map((food) => food['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final otherFoods = foods
        .where((food) => !sameCategoryIds.contains(food['id']?.toString()))
        .toList();

    return [...sameCategory, ...otherFoods];
  }

  Future<Map<String, dynamic>?> _showReplacementPicker({
    required String title,
    required List<Map<String, dynamic>> candidates,
  }) async {
    if (candidates.isEmpty) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final food = candidates[index];
              return ListTile(
                title: Text(food['name']?.toString() ?? 'Food'),
                onTap: () => Navigator.of(context).pop(food),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _handleReplace(
    OrderProductModel product,
  ) async {
    final vendorId = _readOrderVendorId();
    final foods = await _loadVendorAvailableFoods(vendorId);
    final candidates = _buildReplacementCandidates(product, foods);
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No replacement available')),
      );
      return;
    }

    final selection = await _showReplacementPicker(
      title: product.name,
      candidates: candidates,
    );
    if (selection == null) return;

    final originalId = product.id;
    setState(() {
      product.id = selection['id']?.toString() ?? product.id;
      product.name = selection['name']?.toString() ?? product.name;
      final newCategoryId =
          selection['categoryId']?.toString() ?? product.categoryId;
      product.categoryId = newCategoryId;
      final newPhoto = selection['photo']?.toString() ?? '';
      if (newPhoto.isNotEmpty) {
        product.photo = newPhoto;
      }
      _replacementsByProductId[originalId] = {
        'replacementId': selection['id'],
        'replacementName': selection['name'],
        'vendorId': vendorId,
        'replacedAt': DateTime.now().toIso8601String(),
      };
    });

    await _loadAvailability();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnavailableItems = widget.currentOrder!.products.any((product) {
      final status =
          _availabilityByProductId[product.id]?['availabilityStatus']?.toString();
      return status == 'unavailable';
    });
    final canConfirmItems = !hasUnavailableItems;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.chevron_left),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: -8,
        title: Text(
          "Pick: ${widget.currentOrder!.id}",
          style: TextStyle(
            color: isDarkMode(context) ? Color(0xffFFFFFF) : Color(0xff000000),
            fontFamily: "Poppinsr",
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.grey.shade100, width: 0.1),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 2.0, spreadRadius: 0.4, offset: Offset(0.2, 0.2)),
                  ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Image.asset(
                    'assets/images/order3x.png',
                    height: 25,
                    width: 25,
                    color: Color(COLOR_PRIMARY),
                  ),
                  Text(
                    "Order ready, Pick now !",
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontFamily: "Poppinsm",
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: 28),
            Text(
              "ITEMS",
              style: TextStyle(
                color: Color(0xff9091A4),
                fontFamily: "Poppinsm",
              ),
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isAvailabilityLoading ? null : _loadAvailability,
                icon: _isAvailabilityLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh Menu'),
              ),
            ),
            SizedBox(height: 24),
            ListView.builder(
                shrinkWrap: true,
                itemCount: widget.currentOrder!.products.length,
                itemBuilder: (context, index) {
                  final product = widget.currentOrder!.products[index];
                  final availability = _availabilityByProductId[product.id];
                  final status =
                      availability?['availabilityStatus']?.toString() ?? '';
                  final reason =
                      availability?['unavailableReason']?.toString() ?? '';
                  final isUnavailable = status == 'unavailable';
                  return Container(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CachedNetworkImage(
                                height: 55,
                                // width: 50,
                                imageUrl: '${widget.currentOrder!.products[index].photo}',
                                imageBuilder: (context, imageProvider) => Container(
                                      decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          )),
                                    )),
                          ),
                          Expanded(
                            flex: 10,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${product.name}',
                                    style: TextStyle(
                                        fontFamily: 'Poppinsr',
                                        letterSpacing: 0.5,
                                        color: isDarkMode(context) ? Color(0xffFFFFFF) : Color(0xff333333)),
                                  ),
                                  if (isUnavailable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reason.isNotEmpty
                                                ? 'Unavailable - $reason'
                                                : 'Unavailable',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade600,
                                              fontFamily: 'Poppinsr',
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextButton(
                                            onPressed: () =>
                                                _handleReplace(product),
                                            child: const Text('Quick Replace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.close,
                                        size: 15,
                                        color: Color(COLOR_PRIMARY),
                                      ),
                                      Text('${product.quantity}',
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            fontSize: 17,
                                            color: Color(COLOR_PRIMARY),
                                          )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ));
                  // Card(
                  //   child: Text(widget.currentOrder!.products[index].name),
                  // );
                }),
            SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey, width: 0.1),
                  // boxShadow: [
                  //   BoxShadow(
                  //       color: Colors.grey.shade200,
                  //       blurRadius: 8.0,
                  //       spreadRadius: 1.2,
                  //       offset: Offset(0.2, 0.2)),
                  // ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: ListTile(
                onTap: canConfirmItems
                    ? () {
                  setState(() {
                    _value = !_value;
                  });
                  }
                    : null,
                selected: _value,
                leading: _value
                    ? Image.asset(
                        'assets/images/mark_selected3x.png',
                        height: 21,
                        width: 21,
                      )
                    : Image.asset(
                        'assets/images/mark_unselected3x.png',
                        height: 21,
                        width: 21,
                      ),
                title: Text(
                  "Confirm Items",
                  style: TextStyle(
                    color: !canConfirmItems
                        ? Colors.grey
                        : _value
                            ? Color(0xff3DAE7D)
                            : Colors.black,
                    fontFamily: 'Poppinsm',
                  ),
                ),
              ),
            ),
            SizedBox(height: 26),
            Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey, width: 0.1),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 2.0, spreadRadius: 0.4, offset: Offset(0.2, 0.2)),
                  ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, top: 12),
                    child: Text(
                      "DELIVER",
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff9091A4),
                        fontFamily: "Poppinsr",
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      '${widget.currentOrder!.author.fullName()}',
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff333333),
                        fontFamily: "Poppinsm",
                      ),
                    ),
                    subtitle: Text(
                      "${widget.currentOrder!.address.getFullAddress()}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff9091A4),
                        fontFamily: "Poppinsr",
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 26),
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(8),
                ),
              ),
              backgroundColor: (_value == true &&
                      _isNearRestaurant &&
                      canConfirmItems)
                  ? Color(COLOR_PRIMARY)
                  : Color(COLOR_PRIMARY).withValues(alpha: 0.5),
            ),
            child: Text(
              _isNearRestaurant
                  ? "PICKED ORDER"
                  : "Move closer to restaurant (within 50m)",
              style: TextStyle(letterSpacing: 0.5),
            ),
            onPressed: (_value == true && _isNearRestaurant && canConfirmItems)
                ? () async {
                    print('HomeScreenState.completePickUp');
                    showProgress(context, 'Updating order...', false);
                    widget.currentOrder!.status = ORDER_STATUS_IN_TRANSIT;
                    await FireStoreUtils.updateOrder(widget.currentOrder!);
                    hideProgress();
                    setState(() {});
                    Navigator.pop(context);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
