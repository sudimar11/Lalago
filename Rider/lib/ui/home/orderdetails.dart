import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foodie_driver/widgets/replacement_search_dialog.dart';
import 'package:foodie_driver/ui/chat_screen/admin_driver_chat_screen.dart';

class OrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order; // Pass the selected order data

  const OrderDetailsPage({Key? key, required this.order}) : super(key: key);

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  GoogleMapController? _mapController;
  LatLng? _driverLocation;
  LatLng? _restaurantLocation;
  double _distance = 0.0; // Variable to store the distance in km
  final Map<String, Map<String, dynamic>> _availabilityByProductId = {};
  bool _isAvailabilityLoading = false;
  final Map<String, Map<String, dynamic>> _replacementsByProductId = {};

  @override
  void initState() {
    super.initState();

    // Initialize restaurant location
    final vendor = widget.order['vendor'] ?? {};
    _restaurantLocation = LatLng(
      vendor['latitude'] ?? 0.0,
      vendor['longitude'] ?? 0.0,
    );

    // Fetch current location and calculate the distance
    _getCurrentLocationAndCalculateDistance();
    _loadAvailability();
  }

  @override
  void dispose() {
    // Properly dispose map controller
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  void _getCurrentLocationAndCalculateDistance() async {
    try {
      // Fetch current location
      Position currentPosition = await Geolocator.getCurrentPosition();

      // Set the driver location
      _driverLocation = LatLng(
        currentPosition.latitude,
        currentPosition.longitude,
      );

      // Calculate the distance
      if (_restaurantLocation != null && _driverLocation != null) {
        double distanceInMeters = Geolocator.distanceBetween(
          _restaurantLocation!.latitude,
          _restaurantLocation!.longitude,
          _driverLocation!.latitude,
          _driverLocation!.longitude,
        );

        if (mounted) {
          setState(() {
            _distance = distanceInMeters / 1000; // Convert meters to kilometers
          });
        }
      }

      log("Driver Location1111111111: ${_driverLocation?.latitude}, ${_driverLocation?.longitude}");
      log("Restaurant Location: ${_restaurantLocation?.latitude}, ${_restaurantLocation?.longitude}");
      log("Calculated Distance: $_distance km");
    } catch (e) {
      // Handle errors
      log("Error fetching location or calculating distance: $e");
    }
  }

  void _onMapCreated(GoogleMapController controller) async {
    if (!mounted) return;

    _mapController = controller;

    // Add delay to ensure map is ready
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted || _mapController == null) return;

    if (_driverLocation != null && _restaurantLocation != null) {
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                _restaurantLocation!.latitude < _driverLocation!.latitude
                    ? _restaurantLocation!.latitude
                    : _driverLocation!.latitude,
                _restaurantLocation!.longitude < _driverLocation!.longitude
                    ? _restaurantLocation!.longitude
                    : _driverLocation!.longitude,
              ),
              northeast: LatLng(
                _restaurantLocation!.latitude > _driverLocation!.latitude
                    ? _restaurantLocation!.latitude
                    : _driverLocation!.latitude,
                _restaurantLocation!.longitude > _driverLocation!.longitude
                    ? _restaurantLocation!.longitude
                    : _driverLocation!.longitude,
              ),
            ),
            100.0,
          ),
        );
      } catch (e) {
        log("Error animating camera: $e");
      }
    }
  }

  Future<void> _loadAvailability() async {
    final orderedItems = widget.order['products'] as List<dynamic>? ?? [];
    final ids = orderedItems
        .map((item) => item is Map ? item['id']?.toString() ?? '' : '')
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

  String _getOrderId() {
    return widget.order['id']?.toString() ??
        widget.order['orderId']?.toString() ??
        '';
  }

  String _readOrderVendorId() {
    final vendorId = widget.order['vendorID']?.toString() ?? '';
    if (vendorId.isNotEmpty) return vendorId;
    final vendor = widget.order['vendor'] as Map<String, dynamic>? ?? {};
    return (vendor['id'] ??
            vendor['vendorId'] ??
            vendor['vendorID'] ??
            '')
        .toString();
  }

  Future<void> _persistProducts() async {
    final orderId = _getOrderId();
    if (orderId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order ID missing')),
        );
      }
      return;
    }
    final raw = widget.order['products'] as List<dynamic>? ?? [];
    final list = raw
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
        .toList();
    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'products': list,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
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

  String _readFoodPrice(Map<String, dynamic> data) {
    final value = (data['price'] ??
            data['salePrice'] ??
            data['regularPrice'] ??
            '0')
        .toString();
    return value.isEmpty ? '0' : value;
  }

  String _readFoodDiscountPrice(Map<String, dynamic> data) {
    final value = (data['discount_price'] ??
            data['discountPrice'] ??
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
          'price': _readFoodPrice(data),
          'discount_price': _readFoodDiscountPrice(data),
        };
      }
    }

    return foodsById.values.toList();
  }

  Future<void> _handleReplace(Map<String, dynamic> product) async {
    final vendorId = _readOrderVendorId();
    final foods = await _loadVendorAvailableFoods(vendorId);
    if (foods.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No replacement available')),
      );
      return;
    }
    final vendor = widget.order['vendor'] as Map<String, dynamic>? ?? {};
    final restaurantName = vendor['title']?.toString();
    final selection = await ReplacementSearchDialog.show(
      context,
      candidates: foods,
      restaurantName: restaurantName,
    );
    if (selection == null) return;

    final originalId = product['id']?.toString() ?? '';
    setState(() {
      product['id'] = selection['id']?.toString() ?? product['id'];
      product['name'] = selection['name']?.toString() ?? product['name'];
      final newCategoryId =
          selection['categoryId']?.toString() ?? product['categoryId'];
      if (newCategoryId.isNotEmpty) {
        product['categoryId'] = newCategoryId;
        product['category_id'] = newCategoryId;
      }
      final newPhoto = selection['photo']?.toString() ?? '';
      if (newPhoto.isNotEmpty) {
        product['photo'] = newPhoto;
      }
      final newPrice = selection['price']?.toString();
      if (newPrice != null && newPrice.isNotEmpty) {
        product['price'] = newPrice;
      }
      final newDiscountPrice =
          selection['discount_price']?.toString();
      if (newDiscountPrice != null && newDiscountPrice.isNotEmpty) {
        product['discount_price'] = newDiscountPrice;
      }
      if (originalId.isNotEmpty) {
        _replacementsByProductId[originalId] = {
          'replacementId': selection['id'],
          'replacementName': selection['name'],
          'vendorId': vendorId,
          'replacedAt': DateTime.now().toIso8601String(),
        };
      }
    });

    await _persistProducts();
    await _loadAvailability();
  }

  Future<void> _handleRemove(Map<String, dynamic> product) async {
    final orderedItems =
        widget.order['products'] as List<dynamic>? ?? [];
    if (orderedItems.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot remove the last item')),
        );
      }
      return;
    }
    final itemName = product['name']?.toString() ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove item?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Is "$itemName" really not available?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              'Once removed, it cannot be added back to this order.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    orderedItems.remove(product);
    await _persistProducts();
    if (mounted) setState(() {});
  }

  /// Get discount breakdown from order data (matching customer app display)
  /// Returns a map with subtotal, deliveryFee, discounts list, totalDiscount, and customerTotal
  Map<String, dynamic> _getDiscountBreakdown(
    Map<String, dynamic> orderData,
    double itemsTotal,
    double deliveryCharge,
  ) {
    final List<Map<String, dynamic>> discounts = [];
    double totalDiscount = 0.0;

    // Manual Coupon Discount
    if (orderData['manualCouponDiscountAmount'] != null) {
      final manualCoupon = orderData['manualCouponDiscountAmount'];
      if (manualCoupon is num) {
        final amount = manualCoupon.toDouble();
        if (amount > 0) {
          final couponCode = orderData['manualCouponCode'] ?? '';
          discounts.add({
            'type': 'Manual Coupon',
            'label': couponCode.isNotEmpty
                ? 'Coupon Discount ($couponCode)'
                : 'Coupon Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(manualCoupon.toString()) ?? 0.0;
        if (amount > 0) {
          final couponCode = orderData['manualCouponCode'] ?? '';
          discounts.add({
            'type': 'Manual Coupon',
            'label': couponCode.isNotEmpty
                ? 'Coupon Discount ($couponCode)'
                : 'Coupon Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      }
    }

    // Referral Wallet
    if (orderData['referralWalletAmountUsed'] != null) {
      final referralWallet = orderData['referralWalletAmountUsed'];
      if (referralWallet is num) {
        final amount = referralWallet.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'Referral Wallet',
            'label': 'Referral Wallet',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(referralWallet.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Referral Wallet',
            'label': 'Referral Wallet',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      }
    }

    // First-Order Discount (only if not manual coupon and couponId is FIRST_ORDER_AUTO)
    final manualCouponId = orderData['manualCouponId'];
    final couponId = orderData['couponId'];
    if (manualCouponId == null &&
        couponId == "FIRST_ORDER_AUTO" &&
        orderData['couponDiscountAmount'] != null) {
      final couponDiscount = orderData['couponDiscountAmount'];
      if (couponDiscount is num) {
        final amount = couponDiscount.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'First-Order',
            'label': 'First-Order Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(couponDiscount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'First-Order',
            'label': 'First-Order Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      }
    }

    // Check if there's a Happy Hour discount
    bool hasHappyHourDiscount = false;
    if (orderData['specialDiscount'] != null) {
      final specialDiscount = orderData['specialDiscount'];
      if (specialDiscount is Map<String, dynamic>) {
        if (specialDiscount['happy_hour_discount'] != null) {
          final happyHourDiscount = specialDiscount['happy_hour_discount'];
          if (happyHourDiscount is num) {
            final amount = happyHourDiscount.toDouble();
            if (amount > 0) {
              hasHappyHourDiscount = true;
              discounts.add({
                'type': 'Happy Hour',
                'label': 'Happy Hour Discount',
                'amount': amount,
              });
              totalDiscount += amount;
            }
          } else {
            final amount = double.tryParse(happyHourDiscount.toString()) ?? 0.0;
            if (amount > 0) {
              hasHappyHourDiscount = true;
              discounts.add({
                'type': 'Happy Hour',
                'label': 'Happy Hour Discount',
                'amount': amount,
              });
              totalDiscount += amount;
            }
          }
        }
      }
    }

    // Other Discount (regular coupon - only if not manual coupon, not first-order, and no happy hour discount)
    // The discount field should only be shown if there's no happy hour discount to avoid double counting
    if (manualCouponId == null &&
        couponId != "FIRST_ORDER_AUTO" &&
        !hasHappyHourDiscount &&
        orderData['discount'] != null) {
      final discount = orderData['discount'];
      if (discount is num) {
        final amount = discount.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'Other',
            'label': 'Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(discount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Other',
            'label': 'Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      }
    }

    // Calculate subtotal (items + delivery) and customer total
    final double subtotal = itemsTotal + deliveryCharge;
    final double customerTotal = subtotal - totalDiscount;

    return {
      'subtotal': subtotal,
      'deliveryFee': deliveryCharge,
      'discounts': discounts,
      'totalDiscount': totalDiscount,
      'customerTotal': customerTotal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final vendor = widget.order['vendor'] ?? {};
    final List<dynamic> orderedItems = widget.order['products'] ?? [];
    final double itemsTotal = orderedItems.fold<double>(0.0, (sum, item) {
      final double price =
          double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final int qty = (item['quantity'] ?? 0) as int;
      return sum + price * qty;
    });
    final double deliveryCharge =
        double.tryParse((widget.order['deliveryCharge'] ?? '0').toString()) ??
            0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        actions: [
          IconButton(
            tooltip: 'Admin Messages',
            icon: const Icon(Icons.support_agent),
            onPressed: () {
              final orderId = _getOrderId();
              if (orderId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Order ID missing')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminDriverChatScreen(orderId: orderId),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map displaying restaurant and driver location
            SizedBox(
              height: 400,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _restaurantLocation ?? LatLng(0.0, 0.0),
                  zoom: 14.0,
                ),
                onMapCreated: _onMapCreated,
                markers: {
                  if (_restaurantLocation != null)
                    Marker(
                      markerId: const MarkerId('restaurant'),
                      position: _restaurantLocation!,
                      infoWindow: InfoWindow(
                        title: vendor['title'] ?? 'Restaurant',
                      ),
                    ),
                  if (_driverLocation != null)
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: _driverLocation!,
                      infoWindow: const InfoWindow(title: 'Driver'),
                    ),
                },
              ),
            ),
            const SizedBox(height: 10),
            // Restaurant Information
            _buildSectionTitle('Restaurant Information'),
            _buildInfoRow('Name', vendor['title'] ?? 'N/A'),
            _buildInfoRow(
              'Location',
              '${vendor['location'] ?? 'N/A'}, Lat: ${vendor['latitude'] ?? 'N/A'}, Long: ${vendor['longitude'] ?? 'N/A'}',
            ),
            const SizedBox(height: 10),
            // Driver's Current Location
            _buildSectionTitle('Driver Location'),
            _buildInfoRow(
              'Coordinates',
              _driverLocation != null
                  ? 'Lat: ${_driverLocation!.latitude}, Long: ${_driverLocation!.longitude}'
                  : 'Fetching location...',
            ),
            const SizedBox(height: 10),
            // Distance Information
            _buildSectionTitle('Distance'),
            _buildInfoRow(
              'Distance to Restaurant',
              '${_distance.toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 10),
            // Items Availability
            _buildSectionTitle('Items'),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orderedItems.length,
                itemBuilder: (context, index) {
                final item = orderedItems[index];
                if (item is! Map) return const SizedBox.shrink();
                final productId = item['id']?.toString() ?? '';
                final name = item['name']?.toString() ?? 'Unknown Item';
                final qty = item['quantity']?.toString() ?? '0';
                final availability = _availabilityByProductId[productId];
                final status =
                    availability?['availabilityStatus']?.toString() ?? '';
                final reason =
                    availability?['unavailableReason']?.toString() ?? '';
                final isUnavailable = status == 'unavailable';

                final canRemove = orderedItems.length > 1;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$qty × $name',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isUnavailable)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            reason.isNotEmpty
                                ? 'Unavailable - $reason'
                                : 'Unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Actions:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: canRemove
                                ? () => _handleRemove(
                                    item as Map<String, dynamic>)
                                : null,
                            icon: const Icon(
                                Icons.remove_circle_outline, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () => _handleReplace(
                                item as Map<String, dynamic>),
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: const Text('Replace'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              ),
            ),
            const SizedBox(height: 10),
            // Payment Summary
            _buildSectionTitle('Payment Summary'),
            Builder(
              builder: (context) {
                // Get discount breakdown
                final discountBreakdown = _getDiscountBreakdown(
                    widget.order, itemsTotal, deliveryCharge);
                final List<Map<String, dynamic>> discounts =
                    discountBreakdown['discounts']
                        as List<Map<String, dynamic>>;
                final double customerTotal =
                    discountBreakdown['customerTotal'] as double;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Individual Discount Lines
                      ...discounts.map((discount) {
                        final String label = discount['label'] as String;
                        final double amount = discount['amount'] as double;
                        final String type = discount['type'] as String;
                        // Use green color for promotional discounts, red for others
                        final Color discountColor = (type == 'Manual Coupon' ||
                                type == 'Referral Wallet' ||
                                type == 'First-Order' ||
                                type == 'Happy Hour')
                            ? Colors.green
                            : Colors.red;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    color: discountColor),
                              ),
                              Text(
                                '(-₱${amount.toStringAsFixed(2)})',
                                style: TextStyle(
                                    fontSize: 16, color: discountColor),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 1),
                      // Final Total
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Customer Payment',
                              style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                            Text(
                              '₱${customerTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
