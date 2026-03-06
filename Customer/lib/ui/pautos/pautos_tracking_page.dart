import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';
import 'package:foodie_customer/ui/pautos/pautos_substitutions_screen.dart';
import 'package:foodie_customer/ui/fullScreenImageViewer/FullScreenImageViewer.dart';

class PautosTrackingPage extends StatefulWidget {
  final String orderId;

  const PautosTrackingPage({Key? key, required this.orderId}) : super(key: key);

  @override
  State<PautosTrackingPage> createState() => _PautosTrackingPageState();
}

class _PautosTrackingPageState extends State<PautosTrackingPage> {
  final _firestore = FirebaseFirestore.instance;
  Completer<GoogleMapController> _mapController = Completer();
  LatLng? _deliveryLocation;
  LatLng? _driverLocation;
  String? _driverId;
  String? _authorID;
  String? _driverName;
  String? _status;
  double? _actualItemCost;
  double? _deliveryFee;
  double? _serviceFee;
  double? _totalAmount;
  String? _paymentMethod;
  String? _receiptPhotoUrl;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverSub;
  Set<Marker> _markers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToOrder();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _driverSub?.cancel();
    super.dispose();
  }

  void _subscribeToOrder() {
    _orderSub = _firestore
        .collection('pautos_orders')
        .doc(widget.orderId)
        .snapshots()
        .listen(_onOrderUpdate);
  }

  Future<void> _onOrderUpdate(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!mounted) return;
    final data = doc.data();
    if (data == null) return;

    _status = data['status']?.toString();
    _actualItemCost = data['actualItemCost'] != null
        ? (data['actualItemCost'] as num).toDouble()
        : null;
    _deliveryFee = data['deliveryFee'] != null
        ? (data['deliveryFee'] as num).toDouble()
        : null;
    _serviceFee = data['serviceFee'] != null
        ? (data['serviceFee'] as num).toDouble()
        : null;
    _totalAmount = data['totalAmount'] != null
        ? (data['totalAmount'] as num).toDouble()
        : null;
    _paymentMethod = data['paymentMethod']?.toString();
    _receiptPhotoUrl = data['receiptPhotoUrl']?.toString();

    if (_status == 'Completed' || _status == 'Delivered') {
      _orderSub?.cancel();
      _driverSub?.cancel();
    }

    _authorID = data['authorID']?.toString();
    _driverId = (data['driverID'] ?? data['driverId'])?.toString();
    _driverName = data['driverName']?.toString();

    final address = data['address'];
    if (address is Map<String, dynamic>) {
      final loc = address['location'];
      if (loc is Map<String, dynamic> &&
          loc['latitude'] != null &&
          loc['longitude'] != null) {
        _deliveryLocation = LatLng(
          (loc['latitude'] as num).toDouble(),
          (loc['longitude'] as num).toDouble(),
        );
      }
    }
    if (_deliveryLocation == null) {
      _deliveryLocation = const LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE);
    }

    if (_driverId != null && _driverId!.isNotEmpty) {
      _driverSub?.cancel();
      _driverSub = _firestore
          .collection('users')
          .doc(_driverId)
          .snapshots()
          .listen(_onDriverUpdate);
    } else {
      _driverLocation = null;
    }

    _updateMarkers();
  }

  void _onDriverUpdate(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!mounted) return;
    final data = doc.data();
    if (data == null) return;
    final loc = data['location'];
    if (loc is Map<String, dynamic> &&
        loc['latitude'] != null &&
        loc['longitude'] != null) {
      _driverLocation = LatLng(
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );
      _updateMarkers();
    }
  }

  void _updateMarkers() {
    _markers = {};
    if (_deliveryLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: _deliveryLocation!,
        infoWindow: const InfoWindow(title: 'Delivery Address'),
      ));
    }
    if (_driverLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverLocation!,
        infoWindow: const InfoWindow(title: 'Rider'),
      ));
    }
    if (mounted) {
      setState(() => _loading = _deliveryLocation == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAUTOS Tracking'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
        actions: [
          if (_driverId != null && _authorID != null)
            IconButton(
              icon: const Icon(Icons.chat_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreens(
                      orderId: widget.orderId,
                      customerId: _authorID,
                      customerName:
                          '${MyAppState.currentUser?.firstName ?? ''} '
                          '${MyAppState.currentUser?.lastName ?? ''}'.trim(),
                      restaurantId: _driverId,
                      restaurantName: _driverName ?? 'Rider',
                      chatType: 'Driver',
                      isPautos: true,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deliveryLocation == null
              ? const Center(child: Text('No delivery location'))
              : Column(
                  children: [
                    Expanded(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _deliveryLocation!,
                          zoom: 14,
                        ),
                        markers: _markers,
                        onMapCreated: (c) => _mapController.complete(c),
                      ),
                    ),
                    if (_status != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.grey.shade200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Color(COLOR_PRIMARY)),
                                const SizedBox(width: 8),
                                Text(
                                  _status == 'Shopping'
                                      ? 'Shopping in progress'
                                      : _status == 'Substitution Pending'
                                          ? 'Substitution Pending'
                                          : 'Status: $_status',
                                ),
                              ],
                            ),
                            if (_status == 'Substitution Pending') ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PautosSubstitutionsScreen(
                                        orderId: widget.orderId,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    Icon(Icons.swap_horiz,
                                        color: Color(COLOR_PRIMARY)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Review substitutions',
                                      style: TextStyle(
                                        color: Color(COLOR_PRIMARY),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_actualItemCost != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Item cost: ${currencyModel?.symbol ?? '₱'} '
                                '${_actualItemCost!.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                              ),
                            ],
                            if (_deliveryFee != null && _deliveryFee! > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Delivery: ${currencyModel?.symbol ?? '₱'} '
                                '${_deliveryFee!.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                              ),
                            ],
                            if (_serviceFee != null && _serviceFee! > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Service: ${currencyModel?.symbol ?? '₱'} '
                                '${_serviceFee!.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                              ),
                            ],
                            if (_totalAmount != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Total: ${currencyModel?.symbol ?? '₱'} '
                                '${_totalAmount!.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (_paymentMethod != null &&
                                _paymentMethod!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _paymentMethod == 'Wallet'
                                    ? 'Payment: Wallet'
                                    : 'Payment: Cash on Delivery',
                              ),
                            ],
                            if (_receiptPhotoUrl != null &&
                                _receiptPhotoUrl!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenImageViewer(
                                        imageUrl: _receiptPhotoUrl!,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    const Icon(Icons.receipt_long),
                                    const SizedBox(width: 8),
                                    Text(
                                      'View receipt',
                                      style: TextStyle(
                                        color: Color(COLOR_PRIMARY),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
