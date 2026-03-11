import 'dart:async';
import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/CurrencyModel.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/order_location_service.dart';
import 'package:foodie_driver/services/order_chat_service.dart';
import 'package:foodie_driver/services/proximity_config_service.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/utils/dialog_utils.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:foodie_driver/ui/home/pick_order.dart';
import 'package:foodie_driver/ui/container/ContainerScreen.dart';
import 'package:foodie_driver/ui/home/confirm_delivery_summary_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodie_driver/utils/order_ready_time_helper.dart';
import 'package:foodie_driver/widgets/shrinking_timer_bar.dart';

const String _keyAutoMarkPickedUpAtRestaurant =
    'auto_mark_picked_up_at_restaurant';
const String _keyPickupOverrideSkipFarWarning =
    'pickup_override_skip_far_warning';

// Dark map style JSON (cached to avoid repeated string operations)
const String _darkMapStyle = '[{"featureType": "all","elementType": "geometry","stylers": [{"color": "#242f3e"}]},{"featureType": "all","elementType": "labels.text.stroke","stylers": [{"lightness": -80}]},{"featureType": "administrative","elementType": "labels.text.fill","stylers": [{"color": "#746855"}]},{"featureType": "administrative.locality","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi.park","elementType": "geometry","stylers": [{"color": "#263c3f"}]},{"featureType": "poi.park","elementType": "labels.text.fill","stylers": [{"color": "#6b9a76"}]},{"featureType": "road","elementType": "geometry.fill","stylers": [{"color": "#2b3544"}]},{"featureType": "road","elementType": "labels.text.fill","stylers": [{"color": "#9ca5b3"}]},{"featureType": "road.arterial","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.arterial","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "road.highway","elementType": "geometry.fill","stylers": [{"color": "#746855"}]},{"featureType": "road.highway","elementType": "geometry.stroke","stylers": [{"color": "#1f2835"}]},{"featureType": "road.highway","elementType": "labels.text.fill","stylers": [{"color": "#f3d19c"}]},{"featureType": "road.local","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.local","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "transit","elementType": "geometry","stylers": [{"color": "#2f3948"}]},{"featureType": "transit.station","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "water","elementType": "geometry","stylers": [{"color": "#17263c"}]},{"featureType": "water","elementType": "labels.text.fill","stylers": [{"color": "#515c6d"}]},{"featureType": "water","elementType": "labels.text.stroke","stylers": [{"lightness": -20}]}]';

class HomeScreen extends StatefulWidget {
  final OrderModel? orderModel;

  const HomeScreen({Key? key, required this.orderModel}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final fireStoreUtils = FireStoreUtils();

  GoogleMapController? _mapController;

  BitmapDescriptor? departureIcon;
  BitmapDescriptor? destinationIcon;
  BitmapDescriptor? taxiIcon;

  Map<PolylineId, Polyline> polyLines = {};
  PolylinePoints polylinePoints = PolylinePoints();
  final Map<String, Marker> _markers = {};

  // Route caching variables to prevent excessive API calls
  String? _lastRouteId;
  LatLng? _lastDriverLocation;
  String? _lastOrderStatus;
  List<LatLng>? _cachedPolylineCoordinates;

  // Rate limiting variables
  Timer? _routeRequestDebounceTimer;
  DateTime? _lastApiCallTime;
  bool _isRouteRequestInProgress = false;

  setIcons() async {
    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/location_black3x.png")
        .then((value) {
      departureIcon = value;
    });

    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/location_orange3x.png")
        .then((value) {
      destinationIcon = value;
    });

    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/food_delivery.png")
        .then((value) {
      taxiIcon = value;
    });
  }

  Future<void> requestPermissions() async {
    var locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      var backgroundStatus = await Permission.locationAlways.request();
      if (backgroundStatus.isGranted) {
        print("✅ Background location granted");

        // ✅ Only enable background mode after confirmed permission
        Location location = Location();
        await location.enableBackgroundMode(enable: true);
      } else {
        print("❌ Background location denied.");
        openAppSettings(); // optional
      }
    } else {
      print("❌ Location permission denied.");
      openAppSettings();
    }
  }

  updateDriverOrder() async {
    Timestamp startTimestamp = Timestamp.now();
    DateTime currentDate = startTimestamp.toDate();
    currentDate = currentDate.subtract(Duration(hours: 3));
    startTimestamp = Timestamp.fromDate(currentDate);

    List<OrderModel> orders = [];

    await FirebaseFirestore.instance
        .collection(ORDERS)
        .where('status',
            whereIn: [ORDER_STATUS_ACCEPTED, ORDER_STATUS_DRIVER_REJECTED])
        .where('createdAt', isGreaterThan: startTimestamp)
        .get()
        .then((value) async {
          await Future.forEach(value.docs,
              (QueryDocumentSnapshot<Map<String, dynamic>> element) {
            try {
              orders.add(OrderModel.fromJson(element.data()));
            } catch (e, s) {
              print('watchOrdersStatus parse error ${element.id}$e $s');
            }
          });
        });

    orders.forEach((element) {
      OrderModel orderModel = element;
      orderModel.triggerDelevery = Timestamp.now();
      FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(element.id)
          .set(orderModel.toJson(), SetOptions(merge: true))
          .then((order) {
        print('Done.');
      });
    });
  }

  bool isLoading = true;

  @override
  void initState() {
    setIcons();
    getCurrencyData();
    getDriver();
    updateDriverOrder();
    requestPermissions(); // 👈 call it here
    super.initState();
  }

  getCurrencyData() async {
    await FireStoreUtils().getCurrency().then((value) {
      setState(() {
        if (value != null) {
          currencyModel = value;
        } else {
          currencyModel = CurrencyModel(
              id: "",
              code: "USD",
              decimal: 2,
              isactive: true,
              name: "US Dollar",
              symbol: "\$",
              symbolatright: false);
        }
      });
    });
    await FireStoreUtils.firestore
        .collection(Setting)
        .doc("DriverNearBy")
        .get()
        .then((value) {
      setState(() {
        minimumDepositToRideAccept =
            value.data()!['minimumDepositToRideAccept'];
        driverLocationUpdate = value.data()!['driverLocationUpdate'];
        mapType = value.data()!['mapType'];
      });
    });
    setState(() {
      isLoading = false;
    });
  }

  late Stream<OrderModel?> ordersFuture;
  OrderModel? currentOrder;

  late Stream<User> driverStream;
  User? _driverModel = User();

  bool _isNearRequiredLocation = false;
  StreamSubscription<bool>? _proximitySubscription;
  StreamSubscription<String>? _arrivalDetectionSubscription;
  StreamSubscription<String>? _departureDetectionSubscription;
  StreamSubscription<String>? _customerArrivalDetectionSubscription;
  StreamSubscription<OrderModel?>? _orderSubscription;
  StreamSubscription<User>? _driverSubscription;
  List<String> _lastOrderRequestIds = [];

  getCurrentOrder() async {
    if (singleOrderReceive == true) {
      if (_driverModel!.inProgressOrderID != null &&
          _driverModel!.inProgressOrderID!.isNotEmpty) {
        ordersFuture = FireStoreUtils()
            .getOrderByID(_driverModel!.inProgressOrderID!.first.toString());
        _orderSubscription?.cancel();
        _orderSubscription = ordersFuture.listen((event) {
          final orderChanged = event?.id != currentOrder?.id ||
              event?.status != currentOrder?.status;
          if (orderChanged) {
            setState(() {
              currentOrder = event;
              if (mapType == "inappmap") {
                getDirections();
              } else {
                isShow = true;
              }
            });
          }
          if (event != null && event.id.isNotEmpty) {
            if (event.restaurantArrivalConfirmed == true) {
              OrderLocationService.markArrivalDialogShown(event.id);
            }
            if (event.customerArrivalDetected == true) {
              OrderLocationService.markCustomerArrivalDetected(event.id);
            }
            _startProximityMonitoring(event.id);
          } else {
            _stopProximityMonitoring();
          }
        });
      } else if (_driverModel!.orderRequestData != null &&
          _driverModel!.orderRequestData!.isNotEmpty) {
        ordersFuture = FireStoreUtils()
            .getOrderByID(_driverModel!.orderRequestData!.first.toString());
        _orderSubscription?.cancel();
        _orderSubscription = ordersFuture.listen((event) {
          final orderChanged = event?.id != currentOrder?.id ||
              event?.status != currentOrder?.status;
          if (orderChanged) {
            setState(() {
              currentOrder = event;
              if (mapType == "inappmap") {
                getDirections();
              } else {
                isShow = true;
              }
            });
          }
          if (event != null && event.id.isNotEmpty) {
            if (event.restaurantArrivalConfirmed == true) {
              OrderLocationService.markArrivalDialogShown(event.id);
            }
            if (event.customerArrivalDetected == true) {
              OrderLocationService.markCustomerArrivalDetected(event.id);
            }
            _startProximityMonitoring(event.id);
          } else {
            _stopProximityMonitoring();
          }
        });
      }
    } else {
      ordersFuture = FireStoreUtils().getOrderByID(widget.orderModel!.id);
      _orderSubscription?.cancel();
      _orderSubscription = ordersFuture.listen((event) {
        final orderChanged = event?.id != currentOrder?.id ||
            event?.status != currentOrder?.status;
        if (orderChanged) {
          setState(() {
            currentOrder = event;
            if (mapType == "inappmap") {
              getDirections();
            } else {
              isShow = true;
            }
          });
        }
      });
    }
  }

  getDriver() {
    driverStream = FireStoreUtils().getDriver(MyAppState.currentUser!.userID);
    _driverSubscription?.cancel();
    _driverSubscription = driverStream.listen((event) async {
      final currentIds = (event.orderRequestData ?? [])
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();
      final newIds = currentIds
          .where((id) => !_lastOrderRequestIds.contains(id))
          .toList();
      for (final orderId in newIds) {
        AudioService.instance.playNewOrderSound(orderId: orderId);
      }
      _lastOrderRequestIds = List.from(currentIds);

      final driverChanged = event.userID != _driverModel?.userID ||
          event.location.latitude != _driverModel?.location.latitude ||
          event.location.longitude != _driverModel?.location.longitude;
      if (driverChanged) {
        setState(() {
          _driverModel = event;
          MyAppState.currentUser = _driverModel;
        });
        log(_driverModel!.toJson().toString());
        if (mapType == "inappmap") {
          getDirections();
        } else {
          isShow = true;
        }
        getCurrentOrder();
      }
    });
  }

  void _startProximityMonitoring(String orderId) {
    _stopProximityMonitoring();
    _proximitySubscription = OrderLocationService.proximityStream.listen(
      (isNear) {
        if (mounted) {
          setState(() {
            _isNearRequiredLocation = isNear;
          });
        }
      },
    );

    // Listen to arrival detection
    _arrivalDetectionSubscription =
        OrderLocationService.arrivalDetectedStream.listen(
      (detectedOrderId) {
        if (mounted && detectedOrderId == orderId) {
          _handleRestaurantArrival(detectedOrderId);
        }
      },
    );

    // Listen to departure detection
    _departureDetectionSubscription =
        OrderLocationService.departureDetectedStream.listen(
      (detectedOrderId) {
        if (mounted && detectedOrderId == orderId) {
          _handleRestaurantDeparture(detectedOrderId);
        }
      },
    );

    // Listen to customer arrival detection
    _customerArrivalDetectionSubscription =
        OrderLocationService.customerArrivalDetectedStream.listen(
      (detectedOrderId) {
        if (mounted && detectedOrderId == orderId) {
          _handleCustomerArrival(detectedOrderId);
        }
      },
    );

    // Trigger initial check
    final driverLocation = MyAppState.currentUser?.location;
    if (driverLocation != null) {
      OrderLocationService.onLocationUpdate(driverLocation, orderId);
    }
  }

  void _stopProximityMonitoring() {
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    _arrivalDetectionSubscription?.cancel();
    _arrivalDetectionSubscription = null;
    _departureDetectionSubscription?.cancel();
    _departureDetectionSubscription = null;
    _customerArrivalDetectionSubscription?.cancel();
    _customerArrivalDetectionSubscription = null;
    _isNearRequiredLocation = false;
  }

  /// Handle restaurant arrival detection
  Future<void> _handleRestaurantArrival(String orderId) async {
    if (currentOrder == null || currentOrder!.id != orderId) return;
    if (currentOrder!.restaurantArrivalConfirmed == true) {
      OrderLocationService.markArrivalDialogShown(orderId);
      return;
    }
    if (currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
        currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
        currentOrder!.status != ORDER_STATUS_SHIPPED) {
      return;
    }

    if (!mounted) return;

    // Optional auto-set: skip dialog and mark picked up
    final prefs = await SharedPreferences.getInstance();
    final autoMarkPickedUp =
        prefs.getBool(_keyAutoMarkPickedUpAtRestaurant) ?? false;
    if (autoMarkPickedUp) {
      await _doPickupAtRestaurant(orderId);
      return;
    }

    final markPickedUp = await DialogUtils.showMarkPickedUpDialog(context);

    if (!mounted) return;

    if (markPickedUp) {
      await _doPickupAtRestaurant(orderId);
    } else {
      await _doRestaurantArrivalOnly(orderId);
    }
  }

  /// Mark order as picked up (In Transit) and set restaurantArrivalConfirmed.
  /// When [fromMapOverride] is true, logs pickupMethod and pickedUpFarFromRestaurant.
  Future<void> _doPickupAtRestaurant(String orderId,
      {bool fromMapOverride = false}) async {
    try {
      final data = <String, dynamic>{
        'status': 'In Transit',
        'pickedUpAt': FieldValue.serverTimestamp(),
        'restaurantArrivalConfirmed': true,
      };
      if (fromMapOverride) {
        data['pickupMethod'] = 'map_override';
        data['pickedUpFarFromRestaurant'] = true;
      }
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(orderId)
          .update(data);

      final currentUserId = MyAppState.currentUser?.userID;
      if (currentOrder != null && currentUserId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'In Transit',
          customerId: currentOrder!.authorID,
          customerFcmToken: currentOrder!.author.fcmToken,
          restaurantId: currentUserId,
        );
      }

      if (currentOrder != null) {
        currentOrder!.restaurantArrivalConfirmed = true;
        currentOrder!.status = ORDER_STATUS_IN_TRANSIT;
        setState(() {});
      }
      OrderLocationService.markArrivalDialogShown(orderId);

      if (mounted) {
        DialogUtils.showSnackBar(
          context,
          message: 'Pickup confirmed.',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        DialogUtils.showSnackBar(
          context,
          message: 'Failed to confirm pickup. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// Handles tap on pickup-phase button: near opens PickOrder, far shows dialog
  /// or direct pickup (when "Don't show again" is set).
  Future<void> _handlePickupButtonTap() async {
    if (currentOrder == null) return;
    final orderId = currentOrder!.id;
    final driverLocation = MyAppState.currentUser?.location;

    bool isNear;
    int distanceMeters = 0;
    if (driverLocation == null) {
      isNear = false;
    } else {
      await ProximityConfigService.instance.getConfig();
      final threshold =
          ProximityConfigService.instance.enterThreshold;
      distanceMeters = Geolocator.distanceBetween(
        currentOrder!.vendor.latitude,
        currentOrder!.vendor.longitude,
        driverLocation.latitude,
        driverLocation.longitude,
      ).round();
      isNear = distanceMeters <= threshold;
    }

    if (isNear) {
      push(context, PickOrder(currentOrder: currentOrder));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyPickupOverrideSkipFarWarning) == true) {
      await _doPickupAtRestaurant(orderId, fromMapOverride: true);
      return;
    }

    final result = await DialogUtils.showConfirmPickupWhenFarDialog(
      context,
      distanceMeters: distanceMeters,
    );
    if (!mounted) return;
    if (result == null || !result.confirmed) return;

    await _doPickupAtRestaurant(orderId, fromMapOverride: true);
    if (result.dontShowAgain) {
      await prefs.setBool(_keyPickupOverrideSkipFarWarning, true);
    }
  }

  /// Only set restaurantArrivalConfirmed and notify customer (no status change).
  Future<void> _doRestaurantArrivalOnly(String orderId) async {
    try {
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(orderId)
          .update({'restaurantArrivalConfirmed': true});

      if (currentOrder != null) {
        currentOrder!.restaurantArrivalConfirmed = true;
        setState(() {});
      }
      OrderLocationService.markArrivalDialogShown(orderId);

      final driver = MyAppState.currentUser;
      if (currentOrder != null && driver != null) {
        try {
          await OrderChatService.sendDriverMessage(
            orderId: orderId,
            message:
                'Driver is at the restaurant and waiting for your order',
            driverId: driver.userID,
            driverName: driver.fullName(),
            driverProfileImage: driver.profilePictureURL,
            customerId: currentOrder!.authorID,
            customerName: currentOrder!.author.fullName(),
            customerProfileImage: currentOrder!.author.profilePictureURL,
            customerFcmToken: currentOrder!.author.fcmToken,
          );
        } catch (e) {
          print('Error sending arrival notification to customer: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        DialogUtils.showSnackBar(
          context,
          message: 'Failed to confirm arrival. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// Handle restaurant departure detection
  Future<void> _handleRestaurantDeparture(String orderId) async {
    // Check if this is the current order
    if (currentOrder == null || currentOrder!.id != orderId) {
      return;
    }

    // Only update status if arrival was confirmed
    if (currentOrder!.restaurantArrivalConfirmed != true) {
      return;
    }

    // Only update if current status is appropriate
    if (currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
        currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
        currentOrder!.status != ORDER_STATUS_SHIPPED) {
      return;
    }

    // Prevent duplicate updates
    if (currentOrder!.status == ORDER_STATUS_IN_TRANSIT) {
      return;
    }

    if (!mounted) return;

    try {
      // Update order status to In Transit
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(orderId)
          .update({'status': ORDER_STATUS_IN_TRANSIT});

      // Update local order model
      if (currentOrder != null) {
        currentOrder!.status = ORDER_STATUS_IN_TRANSIT;
        setState(() {});
      }

      // Send system message to customer
      await OrderChatService.sendSystemMessage(
        orderId: orderId,
        status: ORDER_STATUS_IN_TRANSIT,
        customerId: currentOrder!.authorID,
        customerFcmToken: currentOrder!.author.fcmToken,
        customerName: currentOrder!.author.fullName(),
        restaurantId: currentOrder!.driverID,
      );
    } catch (e) {
      print('Error updating order status on departure: $e');
      // Don't show error to driver, just log it
    }
  }

  /// Handle customer arrival detection
  Future<void> _handleCustomerArrival(String orderId) async {
    // Check if this is the current order
    if (currentOrder == null || currentOrder!.id != orderId) {
      return;
    }

    // Check if arrival was already detected in Firestore
    if (currentOrder!.customerArrivalDetected == true) {
      OrderLocationService.markCustomerArrivalDetected(orderId);
      return;
    }

    // Only trigger when order status is "In Transit"
    if (currentOrder!.status != ORDER_STATUS_IN_TRANSIT) {
      return;
    }

    if (!mounted) return;

    try {
      // Update Firestore order document
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(orderId)
          .update({'customerArrivalDetected': true});

      // Update local order model
      if (currentOrder != null) {
        currentOrder!.customerArrivalDetected = true;
        setState(() {});
      }

      // Mark as detected in service
      OrderLocationService.markCustomerArrivalDetected(orderId);

      // Navigate to delivery confirmation page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConfirmDeliverySummaryPage(
              orderId: orderId,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error handling customer arrival: $e');
      // Don't show error to driver, just log it
    }
  }

  @override
  void dispose() {
    // Cancel debounce timer
    _routeRequestDebounceTimer?.cancel();

    // Properly dispose map controller with null check
    _mapController?.dispose();
    _mapController = null;

    FireStoreUtils().ordersStreamController.close();
    FireStoreUtils().ordersStreamSub.cancel();
    _orderSubscription?.cancel();
    _orderSubscription = null;
    _driverSubscription?.cancel();
    _driverSubscription = null;
    _stopProximityMonitoring();

    super.dispose();
  }

  bool isShow = false;

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: singleOrderReceive == true ? null : AppBar(),
      body: isLoading == true
          ? Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                _driverModel!.walletAmount <
                        double.parse(minimumDepositToRideAccept)
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          color: Colors.black,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                                "You have to minimum ${amountShow(amount: minimumDepositToRideAccept.toString())} wallet amount to receiving Order",
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center),
                          ),
                        ),
                      )
                    : Container(),
                Expanded(
                  child: mapType == "inappmap" || currentOrder == null
                      ? _MapView(
                          onMapCreated: (controller) async {
                            if (!mounted) return;

                            _mapController = controller;

                            // Add delay to ensure map is ready
                            await Future.delayed(
                                const Duration(milliseconds: 300));

                            if (!mounted || _mapController == null) return;

                            _mapController!.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: LatLng(
                                      locationDataFinal!.latitude ?? 0.0,
                                      locationDataFinal!.longitude ?? 0.0),
                                  zoom: 16,
                                  bearing: double.parse(
                                      _driverModel!.rotation.toString()),
                                ),
                              ),
                            );
                          },
                          polylines: Set<Polyline>.of(polyLines.values),
                          markers: _markers.values.toSet(),
                          currentOrder: currentOrder,
                          driverModel: _driverModel!,
                          initialPosition: LatLng(
                              _driverModel!.location.latitude,
                              _driverModel!.location.longitude),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset("assets/images/map_route.png"),
                                SizedBox(
                                  height: 30,
                                ),
                                SizedBox(
                                  height: 40,
                                  width: MediaQuery.of(context).size.width,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(4),
                                        ),
                                      ),
                                      backgroundColor: Color(COLOR_PRIMARY),
                                    ),
                                    onPressed: () async {
                                      if (currentOrder != null) {
                                        if (currentOrder!.status !=
                                            ORDER_STATUS_DRIVER_ACCEPTED) {
                                          if (currentOrder!.status ==
                                              ORDER_STATUS_SHIPPED) {
                                            FireStoreUtils.redirectMap(
                                                context: context,
                                                name:
                                                    currentOrder!.vendor.title,
                                                latitude: currentOrder!
                                                    .vendor.latitude,
                                                longLatitude: currentOrder!
                                                    .vendor.longitude);
                                          } else if (currentOrder!.status ==
                                              ORDER_STATUS_IN_TRANSIT) {
                                            FireStoreUtils.redirectMap(
                                                context: context,
                                                name: currentOrder!
                                                    .author.firstName,
                                                latitude: currentOrder!
                                                    .address.location!.latitude,
                                                longLatitude: currentOrder!
                                                    .address
                                                    .location!
                                                    .longitude);
                                          }
                                        } else {
                                          FireStoreUtils.redirectMap(
                                              context: context,
                                              name: currentOrder!
                                                  .author.firstName,
                                              latitude:
                                                  currentOrder!.vendor.latitude,
                                              longLatitude: currentOrder!
                                                  .vendor.longitude);
                                        }
                                      }
                                    },
                                    child: Text(
                                      "Direction",
                                      style: TextStyle(
                                          color: Color(0xffFFFFFF),
                                          fontFamily: "Poppinsm",
                                          letterSpacing: 0.5),
                                    ),
                                  ),
                                )
                              ]),
                        ),
                ),
                currentOrder != null &&
                        currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
                        isShow == true
                    ? buildOrderActionsCard()
                    : Container(),
                currentOrder != null &&
                        currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED
                    ? _DriverBottomSheet(
                        currentOrder: currentOrder!,
                        onAccept: acceptOrder,
                        onReject: () => rejectOrder(),
                        onTimeout: () {
                          AudioService.instance.playReassignSound(
                            orderId: currentOrder!.id,
                          );
                          rejectOrder(preselectedReason: 'timeout');
                        },
                      )
                    : Container()
              ],
            ),
      floatingActionButton: currentOrder == null
          ? Container()
          : mapType == "inappmap" &&
                  currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED &&
                  _driverModel!.inProgressOrderID != null &&
                  _driverModel!.inProgressOrderID!.isNotEmpty
              ? FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      if (isShow == true) {
                        isShow = false;
                      } else {
                        isShow = true;
                      }
                    });
                  },
                  child: Icon(
                    isShow ? Icons.close : Icons.remove_red_eye,
                    color: Colors.white,
                    size: 29,
                  ),
                  backgroundColor: Colors.black,
                  // backgroundColor: Color(COLOR_PRIMARY),
                  tooltip: 'Capture Picture',
                  elevation: 5,
                  splashColor: Colors.grey,
                )
              : null,
    );
  }

  openChatWithCustomer() async {
    await showProgress(context, "Please wait", false);

    User? customer =
        await FireStoreUtils.getCurrentUser(currentOrder!.authorID);
    User? driver =
        await FireStoreUtils.getCurrentUser(currentOrder!.driverID.toString());

    hideProgress();
    push(
        context,
        ChatScreens(
          customerName: customer!.firstName + " " + customer.lastName,
          restaurantName: driver!.firstName + " " + driver.lastName,
          orderId: currentOrder!.id,
          restaurantId: driver.userID,
          customerId: customer.userID,
          customerProfileImage: customer.profilePictureURL,
          restaurantProfileImage: driver.profilePictureURL,
          token: customer.fcmToken,
          chatType: 'Driver',
        ));
  }

  Widget buildOrderActionsCard() {
    late String title;
    String? buttonText;
    if (currentOrder!.status == ORDER_STATUS_SHIPPED ||
        currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED) {
      title = '${currentOrder!.vendor.title}';
      buttonText = 'REACHED RESTAURANT FOR PICKUP';
    } else if (currentOrder!.status == ORDER_STATUS_IN_TRANSIT) {
      title = 'Deliver to ${currentOrder!.author.firstName}';
      buttonText = 'REACHED CUSTOMER DOOR STEP';
    }

    return Container(
      margin: EdgeInsets.only(left: 8, right: 8),
      padding: EdgeInsets.symmetric(vertical: 15),
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8), topRight: Radius.circular(18)),
        color: isDarkMode(context) ? Color(0xff000000) : Color(0xffFFFFFF),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentOrder!.status == ORDER_STATUS_SHIPPED ||
                currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED)
              Column(
                children: [
                  ListTile(
                    title: Text(
                      title,
                      style: TextStyle(
                          color: isDarkMode(context)
                              ? Color(0xffFFFFFF)
                              : Color(0xff000000),
                          fontFamily: "Poppinsm",
                          letterSpacing: 0.5),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${currentOrder!.vendor.location}',
                        maxLines: 2,
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Color(0xffFFFFFF)
                                : Color(0xff000000),
                            fontFamily: "Poppinsr",
                            letterSpacing: 0.5),
                      ),
                    ),
                    trailing: TextButton.icon(
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6.0),
                            side: BorderSide(color: Color(0xff3DAE7D)),
                          ),
                          padding: EdgeInsets.zero,
                          minimumSize: Size(85, 30),
                          alignment: Alignment.center,
                          backgroundColor: Color(0xffFFFFFF),
                        ),
                        onPressed: () async {
                          await launchPhoneCall(
                              context, currentOrder?.vendor.phonenumber);
                        },
                        icon: Image.asset(
                          'assets/images/call3x.png',
                          height: 14,
                          width: 14,
                        ),
                        label: Text(
                          "CALL",
                          style: TextStyle(
                              color: Color(0xff3DAE7D),
                              fontFamily: "Poppinsm",
                              letterSpacing: 0.5),
                        )),
                  ),
                  ListTile(
                    tileColor: Color(0xffF1F4F8),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    title: Row(
                      children: [
                        Text(
                          'ORDER ID ',
                          style: TextStyle(
                              color: isDarkMode(context)
                                  ? Color(0xffFFFFFF)
                                  : Color(0xff555555),
                              fontFamily: "Poppinsr",
                              letterSpacing: 0.5),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            '${currentOrder!.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isDarkMode(context)
                                    ? Color(0xffFFFFFF)
                                    : Color(0xff000000),
                                fontFamily: "Poppinsr",
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${currentOrder!.author.fullName()}',
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Color(0xffFFFFFF)
                                : Color(0xff333333),
                            fontFamily: "Poppinsm",
                            letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            if (currentOrder!.status == ORDER_STATUS_IN_TRANSIT)
              Column(
                children: [
                  ListTile(
                    leading: Image.asset(
                      'assets/images/user3x.png',
                      height: 42,
                      width: 42,
                      color: Color(COLOR_PRIMARY),
                    ),
                    title: Text(
                      '${currentOrder!.author.fullName()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDarkMode(context)
                              ? Color(0xffFFFFFF)
                              : Color(0xff000000),
                          fontFamily: "Poppinsm",
                          letterSpacing: 0.5),
                    ),
                    subtitle: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'ORDER ID ',
                            style: TextStyle(
                                color: Color(0xff555555),
                                fontFamily: "Poppinsr",
                                letterSpacing: 0.5),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width / 4,
                            child: Text(
                              '${currentOrder!.id} ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isDarkMode(context)
                                      ? Color(0xffFFFFFF)
                                      : Color(0xff000000),
                                  fontFamily: "Poppinsr",
                                  letterSpacing: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        TextButton.icon(
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6.0),
                                side: BorderSide(color: Color(0xff3DAE7D)),
                              ),
                              padding: EdgeInsets.zero,
                              minimumSize: Size(85, 30),
                              alignment: Alignment.center,
                              backgroundColor: Color(0xffFFFFFF),
                            ),
                            onPressed: () async {
                              await launchPhoneCall(context,
                                  currentOrder?.author.phoneNumber);
                            },
                            icon: Image.asset(
                              'assets/images/call3x.png',
                              height: 14,
                              width: 14,
                            ),
                            label: Text(
                              "CALL",
                              style: TextStyle(
                                  color: Color(0xff3DAE7D),
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5),
                            )),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Image.asset(
                      'assets/images/delivery_location3x.png',
                      height: 42,
                      width: 42,
                      color: Color(COLOR_PRIMARY),
                    ),
                    title: Text(
                      'DELIVER',
                      style: TextStyle(
                          color: Color(0xff9091A4),
                          fontFamily: "Poppinsr",
                          letterSpacing: 0.5),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${currentOrder!.address.getFullAddress()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Color(0xffFFFFFF)
                                : Color(0xff333333),
                            fontFamily: "Poppinsr",
                            letterSpacing: 0.5),
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        TextButton.icon(
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6.0),
                                side: BorderSide(color: Color(0xff3DAE7D)),
                              ),
                              padding: EdgeInsets.zero,
                              minimumSize: Size(100, 30),
                              alignment: Alignment.center,
                              backgroundColor: Color(0xffFFFFFF),
                            ),
                            onPressed: () => openChatWithCustomer(),
                            icon: Icon(
                              Icons.message,
                              size: 16,
                              color: Color(0xff3DAE7D),
                            ),
                            // Image.asset(
                            //   'assets/images/call3x.png',
                            //   height: 14,
                            //   width: 14,
                            // ),
                            label: Text(
                              "Message",
                              style: TextStyle(
                                  color: Color(0xff3DAE7D),
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 40,
                width: MediaQuery.of(context).size.width,
                child: Builder(
                  builder: (context) {
                    final isPickupPhase = currentOrder!.status ==
                            ORDER_STATUS_SHIPPED ||
                        currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED;
                    final enabled = isPickupPhase || _isNearRequiredLocation;
                    final backgroundColor = isPickupPhase
                        ? (_isNearRequiredLocation
                            ? Color(COLOR_PRIMARY)
                            : Colors.orange)
                        : (_isNearRequiredLocation
                            ? Color(COLOR_PRIMARY)
                            : Color(COLOR_PRIMARY).withValues(alpha: 0.5));
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                        ),
                        backgroundColor: backgroundColor,
                      ),
                      onPressed: enabled
                          ? () async {
                              if (isPickupPhase) {
                                await _handlePickupButtonTap();
                                return;
                              }
                              if (currentOrder!.status ==
                                  ORDER_STATUS_IN_TRANSIT) {
                            push(
                              context,
                              Scaffold(
                                appBar: AppBar(
                                  leading: IconButton(
                                    icon: Icon(Icons.chevron_left),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  titleSpacing: -8,
                                  title: Text(
                                    "Deliver" + ": ${currentOrder!.id}",
                                    style: TextStyle(
                                        color: isDarkMode(context)
                                            ? Color(0xffFFFFFF)
                                            : Color(0xff000000),
                                        fontFamily: "Poppinsr",
                                        letterSpacing: 0.5),
                                  ),
                                  centerTitle: false,
                                ),
                                body: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 25.0, vertical: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 25.0, vertical: 20),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(2),
                                            border: Border.all(
                                                color: Colors.grey.shade100,
                                                width: 0.1),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.shade200,
                                                blurRadius: 2.0,
                                                spreadRadius: 0.4,
                                                offset: Offset(0.2, 0.2),
                                              ),
                                            ],
                                            color: Colors.white),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'DELIVER'.toUpperCase(),
                                                  style: TextStyle(
                                                      color: Color(0xff9091A4),
                                                      fontFamily: "Poppinsr",
                                                      letterSpacing: 0.5),
                                                ),
                                                TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6.0),
                                                        side: BorderSide(
                                                            color: Color(
                                                                0xff3DAE7D)),
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                      minimumSize: Size(85, 30),
                                                      alignment:
                                                          Alignment.center,
                                                      backgroundColor:
                                                          Color(0xffFFFFFF),
                                                    ),
                                                    onPressed: () async {
                                                      await launchPhoneCall(
                                                          context,
                                                          currentOrder?.author
                                                              .phoneNumber);
                                                    },
                                                    icon: Image.asset(
                                                      'assets/images/call3x.png',
                                                      height: 14,
                                                      width: 14,
                                                    ),
                                                    label: Text(
                                                      "CALL".toUpperCase(),
                                                      style: TextStyle(
                                                          color:
                                                              Color(0xff3DAE7D),
                                                          fontFamily:
                                                              "Poppinsm",
                                                          letterSpacing: 0.5),
                                                    )),
                                              ],
                                            ),
                                            Text(
                                              '${currentOrder!.author.fullName()}',
                                              style: TextStyle(
                                                  color: Color(0xff333333),
                                                  fontFamily: "Poppinsm",
                                                  letterSpacing: 0.5),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4.0),
                                              child: Text(
                                                "${currentOrder!.address.getFullAddress()}",
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: Color(0xff9091A4),
                                                    fontFamily: "Poppinsr",
                                                    letterSpacing: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 28),
                                      Text(
                                        "ITEMS".toUpperCase(),
                                        style: TextStyle(
                                            color: Color(0xff9091A4),
                                            fontFamily: "Poppinsm",
                                            letterSpacing: 0.5),
                                      ),
                                      SizedBox(height: 24),
                                      ListView.builder(
                                          shrinkWrap: true,
                                          itemCount:
                                              currentOrder!.products.length,
                                          itemBuilder: (context, index) {
                                            return Container(
                                                padding:
                                                    EdgeInsets.only(bottom: 10),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: CachedNetworkImage(
                                                          height: 55,
                                                          // width: 50,
                                                          imageUrl:
                                                              '${currentOrder!.products[index].photo}',
                                                          imageBuilder: (context,
                                                                  imageProvider) =>
                                                              Container(
                                                                decoration:
                                                                    BoxDecoration(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                8),
                                                                        image:
                                                                            DecorationImage(
                                                                          image:
                                                                              imageProvider,
                                                                          fit: BoxFit
                                                                              .cover,
                                                                        )),
                                                              )),
                                                    ),
                                                    Expanded(
                                                      flex: 10,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 14.0),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                              '${currentOrder!.products[index].name}',
                                                              style: TextStyle(
                                                                  fontFamily:
                                                                      'Poppinsr',
                                                                  letterSpacing:
                                                                      0.5,
                                                                  color: isDarkMode(
                                                                          context)
                                                                      ? Color(
                                                                          0xffFFFFFF)
                                                                      : Color(
                                                                          0xff333333)),
                                                            ),
                                                            SizedBox(height: 5),
                                                            Row(
                                                              children: [
                                                                Icon(
                                                                  Icons.close,
                                                                  size: 15,
                                                                  color: Color(
                                                                      COLOR_PRIMARY),
                                                                ),
                                                                Text(
                                                                    '${currentOrder!.products[index].quantity}',
                                                                    style:
                                                                        TextStyle(
                                                                      fontFamily:
                                                                          'Poppinsm',
                                                                      letterSpacing:
                                                                          0.5,
                                                                      color: Color(
                                                                          COLOR_PRIMARY),
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
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Color(0xffC2C4CE)),
                                            color: Colors.white),
                                        child: ListTile(
                                          minLeadingWidth: 20,
                                          leading: Image.asset(
                                            'assets/images/mark_selected3x.png',
                                            height: 24,
                                            width: 24,
                                          ),
                                          title: Text(
                                            "Given" +
                                                " ${currentOrder!.products.length} " +
                                                "item to customer",
                                            style: TextStyle(
                                                color: Color(0xff3DAE7D),
                                                fontFamily: 'Poppinsm',
                                                letterSpacing: 0.5),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 26),
                                    ],
                                  ),
                                ),
                                bottomNavigationBar: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14.0, horizontal: 26),
                                  child: SizedBox(
                                    height: 45,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(8),
                                          ),
                                        ),
                                        backgroundColor: Color(0xff3DAE7D),
                                      ),
                                      child: Text(
                                        "MARK ORDER DELIVER",
                                        style: TextStyle(
                                          letterSpacing: 0.5,
                                          fontFamily: 'Poppinsm',
                                        ),
                                      ),
                                      onPressed: () => completeOrder(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                              }
                            }
                          : null,
                      child: Text(
                        isPickupPhase
                            ? (_isNearRequiredLocation
                                ? (buttonText ?? "")
                                : 'CONFIRM PICKUP (OVERRIDE)')
                            : (_isNearRequiredLocation
                                ? (buttonText ?? "")
                                : "Move closer to ${currentOrder!.status == ORDER_STATUS_IN_TRANSIT ? 'customer' : 'restaurant'} (within 50m)"),
                        style: const TextStyle(
                            color: Color(0xffFFFFFF),
                            fontFamily: "Poppinsm",
                            letterSpacing: 0.5),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _showEmergencyUnassignDialog,
                child: Text(
                  'Emergency? Unassign',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  acceptOrder() async {
    final canProceed = await _guardAttendance();
    if (!canProceed) return;

    final remittanceOk = await _guardRemittance();
    if (!remittanceOk) return;

    final canAccept = _driverModel!.isOnline == true &&
        _driverModel!.riderAvailability != 'offline' &&
        _driverModel!.riderAvailability != 'on_break';
    if (!canAccept) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Go Online Required'),
          content: const Text(
            'Please go online to accept orders.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    _driverModel!.orderRequestData!.remove(currentOrder!.id);
    _driverModel!.inProgressOrderID!.add(currentOrder!.id);

    await FireStoreUtils.updateCurrentUser(_driverModel!);

    currentOrder!.status = ORDER_STATUS_DRIVER_ACCEPTED;
    currentOrder!.driverID = _driverModel!.userID;
    currentOrder!.driver = _driverModel!;

    await FireStoreUtils.updateOrder(currentOrder!);

    AudioService.instance.markOrderAsNotified(currentOrder!.id);
    setState(() {
      isShow = true;
    });
  }

  completeOrder() async {
    final canProceed = await _guardAttendance();
    if (!canProceed) return;

    showProgress(context, 'Completing Delivery...', false);
    currentOrder!.status = ORDER_STATUS_COMPLETED;
    updateWallateAmount(currentOrder!);
    await FireStoreUtils.updateOrder(currentOrder!);

    await FireStoreUtils.getFirestOrderOrNOt(currentOrder!).then((value) async {
      if (value == true) {
        await FireStoreUtils.updateReferralAmount(currentOrder!);
      }
    });

    Position? locationData = await getCurrentLocation();
    if (mounted && _mapController != null) {
      try {
        await _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
                target: LatLng(locationData.latitude, locationData.longitude),
                zoom: 20,
                bearing: double.parse(_driverModel!.rotation.toString())),
          ),
        );
      } catch (e) {
        // Silently handle map animation errors
      }
    }

    _driverModel!.inProgressOrderID!.remove(currentOrder!.id);
    await FireStoreUtils.updateCurrentUser(_driverModel!);
    await OrderService.updateRiderStatus();
    hideProgress();
    _markers.clear();
    polyLines.clear();
    // Clear route cache
    _lastRouteId = null;
    _lastDriverLocation = null;
    _lastOrderStatus = null;
    _cachedPolylineCoordinates = null;
    // Reset rate limiting variables
    _routeRequestDebounceTimer?.cancel();
    _lastApiCallTime = null;
    _isRouteRequestInProgress = false;
    currentOrder = null;
    setState(() {});
    Navigator.pop(context);
    if (singleOrderReceive == false) {
      Navigator.pop(context);
    }
  }

  rejectOrder({String? preselectedReason}) async {
    final ok = await OrderService.rejectOrderWithReason(
      context,
      currentOrder!.id,
      orderData: currentOrder!.toJson(),
      preselectedReason: preselectedReason,
    );
    if (!ok || !mounted) return;

    if (_driverModel != null) {
      final updatedDriver =
          await FireStoreUtils.getCurrentUser(_driverModel!.userID);
      if (updatedDriver != null) {
        _driverModel = updatedDriver;
      }
    }

    setState(() {
      currentOrder = null;
      _markers.clear();
      polyLines.clear();
      _lastRouteId = null;
      _lastDriverLocation = null;
      _lastOrderStatus = null;
      _cachedPolylineCoordinates = null;
      _routeRequestDebounceTimer?.cancel();
      _lastApiCallTime = null;
      _isRouteRequestInProgress = false;
    });
    if (singleOrderReceive == false && mounted) {
      Navigator.pop(context);
    }
  }

  void _showEmergencyUnassignDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency Unassign'),
        content: const SelectableText(
          'If you have an emergency and cannot complete this delivery, '
          'you can unassign yourself. A new rider will be assigned to '
          'complete the order.\n\n'
          'Note: Frequent unassignments may affect your performance score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('UNASSIGN'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _emergencyUnassign();
    }
  }

  Future<void> _emergencyUnassign() async {
    if (currentOrder == null || _driverModel == null || !mounted) return;

    try {
      final orderId = currentOrder!.id;
      final riderId = _driverModel!.userID;

      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'status': 'Order Accepted',
        'driverID': FieldValue.delete(),
        'assignedDriverName': FieldValue.delete(),
        'dispatch.emergencyUnassign': true,
        'dispatch.emergencyUnassignAt': FieldValue.serverTimestamp(),
        'dispatch.emergencyUnassignBy': riderId,
        'dispatch.excludedDriverIds': FieldValue.arrayUnion([riderId]),
        'dispatch.retryCount': FieldValue.increment(1),
      });

      await FirebaseFirestore.instance.collection('users').doc(riderId).set(
        {'inProgressOrderID': FieldValue.arrayRemove([orderId])},
        SetOptions(merge: true),
      );

      await FirebaseFirestore.instance.collection('system_logs').add({
        'type': 'emergency_unassign',
        'orderId': orderId,
        'riderId': riderId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        currentOrder = null;
        _markers.clear();
        polyLines.clear();
        _lastRouteId = null;
        _lastDriverLocation = null;
        _lastOrderStatus = null;
        _cachedPolylineCoordinates = null;
        _routeRequestDebounceTimer?.cancel();
        _lastApiCallTime = null;
        _isRouteRequestInProgress = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You have been unassigned from this order. '
            'A new rider will be assigned.',
          ),
          backgroundColor: Colors.orange,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => ContainerScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _guardAttendance() async {
    final userId = _driverModel?.userID ?? '';
    if (userId.isEmpty) return true;

    final latestUser = await AttendanceService.fetchLatestUser(userId);
    if (latestUser == null) return true;

    final isSuspended = latestUser.suspended == true ||
        (latestUser.attendanceStatus?.toLowerCase() == 'suspended');
    if (isSuspended) {
      _showSuspendedDialog();
      return false;
    }

    await AttendanceService.touchLastActiveDate(latestUser);
    return true;
  }

  Future<bool> _guardRemittance() async {
    final userId = _driverModel?.userID ?? '';
    if (userId.isEmpty) return true;

    try {
      final blocked = await RemittanceEnforcementService.evaluateIsBlocked(
        FirebaseFirestore.instance,
        userId,
      );
      if (blocked) {
        _showRemittanceRequiredDialog();
        return false;
      }
      return true;
    } catch (_) {
      _showRemittanceRequiredDialog();
      return false;
    }
  }

  void _showRemittanceRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily Remittance Required'),
        content: const SelectableText.rich(
          TextSpan(
            text:
                'Daily remittance required. Please remit your credit wallet '
                'before accepting orders.',
            style: TextStyle(color: Colors.black87),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuspendedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Suspended'),
        content: SelectableText.rich(
          TextSpan(
            text:
                'Your account is currently suspended. Please contact the '
                'administrator to restore access.',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Generate unique route ID based on order status and key locations
  String _generateRouteId() {
    if (currentOrder == null || _driverModel == null) return '';

    final status = currentOrder!.status;
    final driverLat = _driverModel!.location.latitude.toStringAsFixed(3);
    final driverLng = _driverModel!.location.longitude.toStringAsFixed(3);
    final vendorLat = currentOrder!.vendor.latitude.toStringAsFixed(3);
    final vendorLng = currentOrder!.vendor.longitude.toStringAsFixed(3);

    if (status == ORDER_STATUS_SHIPPED) {
      return '${status}_${driverLat}_${driverLng}_${vendorLat}_${vendorLng}';
    } else if (status == ORDER_STATUS_IN_TRANSIT) {
      final customerLat =
          currentOrder!.address.location!.latitude.toStringAsFixed(3);
      final customerLng =
          currentOrder!.address.location!.longitude.toStringAsFixed(3);
      return '${status}_${driverLat}_${driverLng}_${customerLat}_${customerLng}';
    } else {
      final customerLat =
          currentOrder!.author.location.latitude.toStringAsFixed(3);
      final customerLng =
          currentOrder!.author.location.longitude.toStringAsFixed(3);
      return '${status}_${customerLat}_${customerLng}_${vendorLat}_${vendorLng}';
    }
  }

  /// Check if driver has moved significantly enough to require new route
  bool _shouldUpdateRoute() {
    if (_lastDriverLocation == null || _driverModel == null) return true;

    final distanceMoved = Geolocator.distanceBetween(
      _lastDriverLocation!.latitude,
      _lastDriverLocation!.longitude,
      _driverModel!.location.latitude,
      _driverModel!.location.longitude,
    );

    // Only update if driver moved more than 100 meters
    return distanceMoved >= 100;
  }

  getDirections() async {
    // Cancel existing debounce timer
    _routeRequestDebounceTimer?.cancel();

    // Schedule debounced execution
    _routeRequestDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _executeRouteRequest();
    });
  }

  Future<void> _executeRouteRequest() async {
    if (currentOrder == null || _driverModel == null) return;

    // In-progress lock check
    if (_isRouteRequestInProgress) {
      print('Route request already in progress, skipping');
      // Still update UI with cached route if available
      if (_cachedPolylineCoordinates != null &&
          _cachedPolylineCoordinates!.isNotEmpty) {
        _updateMarkers();
        addPolyLine(_cachedPolylineCoordinates!);
      }
      return;
    }

    // Minimum interval check (30 seconds)
    if (_lastApiCallTime != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastApiCallTime!);
      if (timeSinceLastCall.inSeconds < 30) {
        print(
            'Minimum interval not met (${timeSinceLastCall.inSeconds}s < 30s), skipping API call');
        // Still update UI with cached route if available
        if (_cachedPolylineCoordinates != null &&
            _cachedPolylineCoordinates!.isNotEmpty) {
          _updateMarkers();
          addPolyLine(_cachedPolylineCoordinates!);
        }
        return;
      }
    }

    // Generate unique route ID for current state
    final currentRouteId = _generateRouteId();

    // Skip API call if route hasn't changed
    if (_lastRouteId == currentRouteId) {
      print('Route unchanged (cached), skipping API call');
      // Use cached polyline if available
      if (_cachedPolylineCoordinates != null &&
          _cachedPolylineCoordinates!.isNotEmpty) {
        _updateMarkers();
        addPolyLine(_cachedPolylineCoordinates!);
      }
      return;
    }

    // Check if driver moved significantly
    if (_lastOrderStatus == currentOrder!.status && !_shouldUpdateRoute()) {
      print('Driver position change insignificant (<100m), skipping API call');
      // Update markers with new driver position but keep existing route
      if (_cachedPolylineCoordinates != null) {
        _updateMarkers();
        addPolyLine(_cachedPolylineCoordinates!);
      }
      return;
    }

    // Proceed with API call - route changed significantly
    print('Fetching new route from Directions API');

    // Set in-progress flag before making API call
    _isRouteRequestInProgress = true;

    if (currentOrder!.status != ORDER_STATUS_DRIVER_ACCEPTED) {
      if (currentOrder!.status == ORDER_STATUS_SHIPPED) {
        await _fetchAndCacheRoute(
          PointLatLng(_driverModel!.location.latitude,
              _driverModel!.location.longitude),
          PointLatLng(
              currentOrder!.vendor.latitude, currentOrder!.vendor.longitude),
          currentRouteId,
        );
      } else if (currentOrder!.status == ORDER_STATUS_IN_TRANSIT) {
        await _fetchAndCacheRoute(
          PointLatLng(_driverModel!.location.latitude,
              _driverModel!.location.longitude),
          PointLatLng(currentOrder!.address.location!.latitude,
              currentOrder!.address.location!.longitude),
          currentRouteId,
        );
      }
    } else {
      await _fetchAndCacheRoute(
        PointLatLng(currentOrder!.author.location.latitude,
            currentOrder!.author.location.longitude),
        PointLatLng(
            currentOrder!.vendor.latitude, currentOrder!.vendor.longitude),
        currentRouteId,
      );
    }
  }

  /// Fetch route from API and update cache
  Future<void> _fetchAndCacheRoute(
    PointLatLng origin,
    PointLatLng destination,
    String routeId,
  ) async {
    List<LatLng> polylineCoordinates = [];

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        GOOGLE_API_KEY,
        origin,
        destination,
        travelMode: TravelMode.driving,
      );

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      }

      // Update cache
      _cachedPolylineCoordinates = polylineCoordinates;
      _lastRouteId = routeId;
      _lastDriverLocation = LatLng(
          _driverModel!.location.latitude, _driverModel!.location.longitude);
      _lastOrderStatus = currentOrder!.status;

      // Update timestamp after successful API call
      _lastApiCallTime = DateTime.now();

      // Update UI
      _updateMarkers();
      addPolyLine(polylineCoordinates);
    } catch (e) {
      print('Error fetching route: $e');
      // Update timestamp even on error to prevent rapid retries
      _lastApiCallTime = DateTime.now();
    } finally {
      // Clear in-progress flag after API call completes (success or failure)
      _isRouteRequestInProgress = false;
    }
  }

  /// Update map markers for current order and driver position
  void _updateMarkers() {
    if (currentOrder == null || _driverModel == null) return;

    _markers.remove("Departure");
    _markers['Departure'] = Marker(
      markerId: const MarkerId('Departure'),
      infoWindow: const InfoWindow(title: "Departure"),
      position:
          LatLng(currentOrder!.vendor.latitude, currentOrder!.vendor.longitude),
      icon: departureIcon!,
    );

    _markers.remove("Destination");
    final destPosition = currentOrder!.status == ORDER_STATUS_IN_TRANSIT
        ? LatLng(currentOrder!.address.location!.latitude,
            currentOrder!.address.location!.longitude)
        : LatLng(currentOrder!.author.location.latitude,
            currentOrder!.author.location.longitude);

    _markers['Destination'] = Marker(
      markerId: const MarkerId('Destination'),
      infoWindow: const InfoWindow(title: "Destination"),
      position: destPosition,
      icon: destinationIcon!,
    );

    _markers.remove("Driver");
    _markers['Driver'] = Marker(
      markerId: const MarkerId('Driver'),
      infoWindow: const InfoWindow(title: "Driver"),
      position: LatLng(
          _driverModel!.location.latitude, _driverModel!.location.longitude),
      icon: taxiIcon!,
      rotation: double.parse(_driverModel!.rotation.toString()),
    );
  }

  addPolyLine(List<LatLng> polylineCoordinates) {
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Color(COLOR_PRIMARY),
      points: polylineCoordinates,
      width: 8,
      geodesic: true,
    );
    setState(() {
      polyLines[id] = polyline;
    });
    updateCameraLocation(polylineCoordinates.first, _mapController);
  }

  Future<void> updateCameraLocation(
    LatLng source,
    GoogleMapController? mapController,
  ) async {
    if (!mounted || mapController == null) return;

    try {
      await mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: source,
            zoom: currentOrder == null ||
                    currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED
                ? 16
                : 20,
            bearing: double.parse(_driverModel!.rotation.toString()),
          ),
        ),
      );
    } catch (e) {
      // Silently handle map animation errors
    }
  }

  //final audioPlayer = AudioPlayer();
  //bool isPlaying = false;

  //playSound() async {
  //  final path = await rootBundle
  //      .load("assets/audio/mixkit-happy-bells-notification-937.mp3");

  //  audioPlayer.setSourceBytes(path.buffer.asUint8List());
  //  audioPlayer.setReleaseMode(ReleaseMode.loop);
  //  //audioPlayer.setSourceUrl(url);
  //  audioPlayer.play(BytesSource(path.buffer.asUint8List()),
  //      volume: 15,
  //      ctx: AudioContext(
  //          android: AudioContextAndroid(
  //              contentType: AndroidContentType.music,
  //              isSpeakerphoneOn: true,
  //              stayAwake: true,
  //              usageType: AndroidUsageType.alarm,
  //              audioFocus: AndroidAudioFocus.gainTransient),
  //          iOS: AudioContextIOS(
  //              category: AVAudioSessionCategory.playback, options: {})));
  //}
}

/// Extracted map widget with dark mode caching
class _MapView extends StatefulWidget {
  final Function(GoogleMapController) onMapCreated;
  final Set<Polyline> polylines;
  final Set<Marker> markers;
  final OrderModel? currentOrder;
  final User driverModel;
  final LatLng initialPosition;

  const _MapView({
    required this.onMapCreated,
    required this.polylines,
    required this.markers,
    required this.currentOrder,
    required this.driverModel,
    required this.initialPosition,
  });

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  GoogleMapController? _controller;
  bool? _lastIsDarkMode;

  void _updateMapStyle(bool isDark) {
    if (_controller == null) return;
    _controller!.setMapStyle(isDark ? _darkMapStyle : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentIsDarkMode = isDarkMode(context);
    if (_lastIsDarkMode != currentIsDarkMode && _controller != null) {
      _lastIsDarkMode = currentIsDarkMode;
      _updateMapStyle(currentIsDarkMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      onMapCreated: (controller) async {
        _controller = controller;
        final currentIsDark = isDarkMode(context);
        _lastIsDarkMode = currentIsDark;
        _updateMapStyle(currentIsDark);
        widget.onMapCreated(controller);
      },
      myLocationEnabled: widget.currentOrder != null &&
              widget.currentOrder!.status == ORDER_STATUS_DRIVER_ACCEPTED
          ? false
          : true,
      myLocationButtonEnabled: true,
      mapType: MapType.normal,
      zoomControlsEnabled: false,
      polylines: widget.polylines,
      markers: widget.markers,
      initialCameraPosition: CameraPosition(
        zoom: 15,
        target: widget.initialPosition,
      ),
    );
  }
}

/// Extracted driver bottom sheet widget with distance caching
class _DriverBottomSheet extends StatefulWidget {
  final OrderModel currentOrder;
  final VoidCallback onAccept;
  final Future<void> Function() onReject;
  final VoidCallback? onTimeout;

  const _DriverBottomSheet({
    required this.currentOrder,
    required this.onAccept,
    required this.onReject,
    this.onTimeout,
  });

  @override
  State<_DriverBottomSheet> createState() => _DriverBottomSheetState();
}

class _DriverBottomSheetState extends State<_DriverBottomSheet> {
  double? _cachedDistance;
  String? _lastOrderId;

  double _getDistance() {
    if (_lastOrderId != widget.currentOrder.id || _cachedDistance == null) {
      double distanceInMeters = Geolocator.distanceBetween(
        widget.currentOrder.vendor.latitude,
        widget.currentOrder.vendor.longitude,
        widget.currentOrder.address.location!.latitude,
        widget.currentOrder.address.location!.longitude,
      );
      _cachedDistance = distanceInMeters / 1000;
      _lastOrderId = widget.currentOrder.id;
    }
    return _cachedDistance!;
  }

  @override
  Widget build(BuildContext context) {
    final kilometer = _getDistance();
    final order = widget.currentOrder;
    final baseTime = order.acceptedAt?.toDate() ?? order.createdAt.toDate();
    final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
      order.estimatedTimeToPrepare,
    );
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    final readyAtStr = DateFormat.jm().format(readyAt);

    return Padding(
      padding: EdgeInsets.all(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: Color(0xff212121),
          borderRadius: BorderRadius.all(Radius.circular(15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Text(
                    "Restaurant",
                    style: TextStyle(
                        color: Color(0xffADADAD),
                        fontFamily: "Poppinsr",
                        letterSpacing: 0.5),
                  ),
                ),
                Flexible(
                  child: Text(
                    order.vendor.title.isNotEmpty
                        ? order.vendor.title
                        : "Restaurant",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Color(0xffFFFFFF),
                        fontFamily: "Poppinsm",
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Text(
                    "Order ID",
                    style: TextStyle(
                        color: Color(0xffADADAD),
                        fontFamily: "Poppinsr",
                        letterSpacing: 0.5),
                  ),
                ),
                Flexible(
                  child: Text(
                    order.id.length > 12
                        ? "${order.id.substring(0, 12)}..."
                        : order.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Color(0xffFFFFFF),
                        fontFamily: "Poppinsm",
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Text(
                    "Trip Distance",
                    style: TextStyle(
                        color: Color(0xffADADAD),
                        fontFamily: "Poppinsr",
                        letterSpacing: 0.5),
                  ),
                ),
                Text(
                  "${kilometer.toStringAsFixed(currencyModel!.decimal)} km",
                  style: TextStyle(
                      color: Color(0xffFFFFFF),
                      fontFamily: "Poppinsm",
                      letterSpacing: 0.5),
                ),
              ],
            ),
            SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade700),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: Colors.orange.shade300, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Preparing food • Ready at ~$readyAtStr",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade100,
                      fontFamily: "Poppinsm",
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Text(
                    "Delivery charge",
                    style: TextStyle(
                        color: Color(0xffADADAD),
                        fontFamily: "Poppinsr",
                        letterSpacing: 0.5),
                  ),
                ),
                Text(
                  "${amountShow(amount: widget.currentOrder.deliveryCharge.toString())}",
                  style: TextStyle(
                      color: Color(0xffFFFFFF),
                      fontFamily: "Poppinsm",
                      letterSpacing: 0.5),
                ),
              ],
            ),
            SizedBox(height: 5),
            Card(
              color: Color(0xffFFFFFF),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/location3x.png',
                      height: 55,
                    ),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 270,
                          child: Text(
                            "${widget.currentOrder.vendor.location} ",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Color(0xff333333),
                                fontFamily: "Poppinsr",
                                letterSpacing: 0.5),
                          ),
                        ),
                        SizedBox(height: 22),
                        SizedBox(
                          width: 270,
                          child: Text(
                            "${widget.currentOrder.address.getFullAddress()}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Color(0xff333333),
                                fontFamily: "Poppinsr",
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            if (order.riderAcceptDeadline != null) ...[
              Builder(
                builder: (context) {
                  final deadline = order.riderAcceptDeadline!.toDate();
                  final remaining =
                      deadline.difference(DateTime.now()).inSeconds.clamp(0, 60);
                  const totalSec = 60;
                  if (remaining > 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ShrinkingTimerBar(
                        totalSeconds: totalSec,
                        initialRemainingSeconds: remaining,
                        orderId: order.id,
                        onTimeout: widget.onTimeout ?? () => widget.onReject(),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height / 20,
                  width: MediaQuery.of(context).size.width / 2.5,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 12),
                      backgroundColor: Color(COLOR_PRIMARY),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(5),
                        ),
                      ),
                    ),
                    child: Text(
                      'Reject',
                      style: TextStyle(
                          color: Color(0xffFFFFFF),
                          fontFamily: "Poppinsm",
                          letterSpacing: 0.5),
                    ),
                    onPressed: () async {
                      try {
                        showProgress(context, 'Rejecting order...', false);
                        await widget.onReject();
                        if (context.mounted) hideProgress();
                      } catch (e) {
                        if (context.mounted) hideProgress();
                      }
                    },
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height / 20,
                  width: MediaQuery.of(context).size.width / 2.5,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 12),
                      backgroundColor: Color(COLOR_PRIMARY),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(5),
                        ),
                      ),
                    ),
                    child: Text(
                      'Accept',
                      style: TextStyle(
                          color: Color(0xffFFFFFF),
                          fontFamily: "Poppinsm",
                          letterSpacing: 0.5),
                    ),
                    onPressed: () async {
                      showProgress(context, 'Accepting order...', false);
                      widget.onAccept();
                      hideProgress();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
