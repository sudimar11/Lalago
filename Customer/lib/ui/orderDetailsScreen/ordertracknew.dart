import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/services/ad_service.dart';
import 'package:foodie_customer/widgets/banner_ad_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class OrderTrackingPage extends StatefulWidget {
  final String orderId;

  const OrderTrackingPage({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderTrackingPageState createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with WidgetsBindingObserver {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  Completer<GoogleMapController> _controller = Completer();
  LatLng? authorLocation;
  LatLng? driverLocation;
  List<LatLng> polylineCoordinates = [];
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      driverLocationSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? orderSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _settingsSubscription;
  String? _driverId;
  BitmapDescriptor? _driverIcon;
  BitmapDescriptor? _authorIcon;
  DateTime? _lastRouteFetch;
  LatLng? _lastRouteOrigin;
  DateTime? _lastUiUpdate;
  // Aggressive throttling to reduce costs
  final Duration _minRouteInterval = const Duration(minutes: 3);
  final double _minRouteDistanceMeters = 800;
  static const double _reRouteDeviationMeters = 80; // off-route threshold
  final Duration _minUiUpdateInterval = const Duration(seconds: 1);
  final double _minDriverMoveForUiMeters = 15; // ignore tiny jitters

  // Client-side fallback to Google Directions is disabled by default
  bool _enableClientDirectionsFallback = false;

  // Cap client-side Directions calls per session (fallback only)
  int _routeCalls = 0;
  static const int _maxCallsPerSession = 0; // prod default: effectively disable

  // Simple in-memory route cache (rounded origin/destination)
  static final Map<String, List<LatLng>> _routeCache = {};

  bool _isActive = true;
  bool _listenersCancelled = false;
  String? _lastEncodedPolyline;
  LatLngBounds? _lastBounds;
  Timer? _idleTimer;
  final Duration _maxIdle = const Duration(minutes: 10);

  DateTime? _eta;
  Timer? _etaTimer;

  // Optional: poll driver location instead of live listener (cheaper for chattery drivers)
  Timer? _driverPollTimer;
  bool _useDriverPolling = false;
  Duration _driverPollInterval = const Duration(seconds: 10);

  // Audit sampling to reduce Firestore chatter (1 in N)
  int _auditEveryN = 5;
  int _auditCounter = 0;

  static const String googleApiKey = "AIzaSyBXNXXV60p-VYnIMD0mevMk8HeW9kSJnPs";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCustomMarker();
    fetchInitialLocations().then((_) => _calculateETA());
    _subscribeToRouteDocument();
    _subscribeToSettingsKillSwitch();
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    driverLocationSubscription?.cancel(); // Cancel the Firestore subscription
    orderSubscription?.cancel();
    _settingsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _isActive;
    _isActive = state == AppLifecycleState.resumed;

    if (!_isActive && wasActive) {
      _cancelAllListeners(permanent: false);
    } else if (_isActive && !_listenersCancelled) {
      _resubscribeAfterResume();
    }
  }

  void _subscribeToRouteDocument() {
    if (orderSubscription != null) return;
    orderSubscription = firestore
        .collection('restaurant_orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> orderDoc) async {
      if (!mounted) return;
      final data = orderDoc.data();
      if (data == null) return;
      _bumpIdleTimer();
      // Cancel listeners on terminal statuses
      final String? status = data['status']?.toString();
      if (status != null) {
        final s = status.toLowerCase();
        if (s.contains('completed') ||
            s.contains('delivered') ||
            s.contains('cancelled') ||
            s.contains('rejected')) {
          _cancelAllListeners();
        }
      }
      // Pick up driver assignment if it appears later
      final String? driverIdUpdate = (data['driverID'] ??
              data['driverId'] ??
              (data['driver'] is Map<String, dynamic>
                  ? data['driver']['id']
                  : null))
          ?.toString();
      if (_driverId == null &&
          driverIdUpdate != null &&
          driverIdUpdate.isNotEmpty) {
        _driverId = driverIdUpdate;
        subscribeToDriverLocation(_driverId!);
      }
      final Map<String, dynamic>? route = data['route'] is Map<String, dynamic>
          ? data['route'] as Map<String, dynamic>
          : null;
      final String? polyline = route?['polyline']?.toString();
      if (polyline == null || polyline.isEmpty) return;
      // Ignore duplicate polylines
      if (_lastEncodedPolyline != null && _lastEncodedPolyline == polyline) {
        return;
      }
      _lastEncodedPolyline = polyline;

      final decoded = _decodePolyline(polyline);
      if (decoded.isEmpty) return;

      polylineCoordinates = decoded;
      _setStateThrottled(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: polylineCoordinates,
          ),
        };
      });

      // Only animate camera if bounds changed significantly
      if (_controller.isCompleted) {
        final next = _getLatLngBounds(polylineCoordinates);
        if (_lastBounds == null || _boundsChanged(_lastBounds!, next)) {
          final GoogleMapController mapController = await _controller.future;
          mapController.animateCamera(
            CameraUpdate.newLatLngBounds(next, 50.0),
          );
          _lastBounds = next;
        }
      }
    });
  }

  void _subscribeToSettingsKillSwitch() {
    if (_settingsSubscription != null) return;
    _settingsSubscription = firestore
        .collection('app_settings')
        .doc('maps')
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      if (data == null) return;
      final dynamic v = data['enable_client_directions_fallback'];
      if (v is bool) {
        _enableClientDirectionsFallback = v;
      }

      // Configure optional driver polling
      final dynamic pollSeconds = data['driver_poll_seconds'];
      bool nextUsePolling = false;
      Duration nextInterval = _driverPollInterval;
      if (pollSeconds is int && pollSeconds > 0) {
        nextUsePolling = true;
        nextInterval = Duration(seconds: pollSeconds);
      } else if (pollSeconds is double && pollSeconds > 0) {
        nextUsePolling = true;
        nextInterval = Duration(seconds: pollSeconds.toInt());
      }

      final bool modeChanged = (nextUsePolling != _useDriverPolling) ||
          (nextUsePolling && nextInterval != _driverPollInterval);

      if (modeChanged) {
        _useDriverPolling = nextUsePolling;
        _driverPollInterval = nextInterval;

        if (_useDriverPolling) {
          _startDriverPolling();
        } else {
          _stopDriverPolling();
          if (_driverId != null &&
              driverLocationSubscription == null &&
              !_listenersCancelled &&
              _isActive) {
            subscribeToDriverLocation(_driverId!);
          }
        }
      }
    });
  }

  String _routeCacheKey(LatLng o, LatLng d) {
    double r(double v) => double.parse(v.toStringAsFixed(2)); // ~1.1 km grid
    return '${r(o.latitude)},${r(o.longitude)}->${r(d.latitude)},${r(d.longitude)}';
  }

  Future<void> fetchInitialLocations() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> orderDoc = await firestore
          .collection('restaurant_orders')
          .doc(widget.orderId)
          .get();

      final Map<String, dynamic>? data = orderDoc.data();
      if (data == null) throw Exception('Order document has no data');

      // Fetch Author Location (author.location), fallback guarded
      final Map<String, dynamic>? authorData =
          (data['author'] is Map<String, dynamic>)
              ? (data['author'] as Map<String, dynamic>)
              : null;
      final Map<String, dynamic>? authorLoc =
          (authorData != null && authorData['location'] is Map<String, dynamic>)
              ? (authorData['location'] as Map<String, dynamic>)
              : null;
      if (authorLoc != null &&
          authorLoc['latitude'] != null &&
          authorLoc['longitude'] != null) {
        authorLocation = LatLng(
          (authorLoc['latitude'] as num).toDouble(),
          (authorLoc['longitude'] as num).toDouble(),
        );
      }

      // Fetch Driver ID and Subscribe to Driver Location (multi-key support)
      _driverId = (data['driverID'] ??
              data['driverId'] ??
              (data['driver'] is Map<String, dynamic>
                  ? data['driver']['id']
                  : null))
          ?.toString();
      if (_driverId != null && _driverId!.isNotEmpty) {
        // Fetch initial driver location immediately
        await _fetchInitialDriverLocation(_driverId!);
        // Subscribe to driver location changes
        subscribeToDriverLocation(_driverId!);
      }

      setState(() {
        if (authorLocation != null) {
          markers.add(Marker(
            markerId: const MarkerId('author'),
            position: authorLocation!,
            icon: _authorIcon ?? BitmapDescriptor.defaultMarker,
            infoWindow: const InfoWindow(title: "Author Location"),
          ));
        }
      });
    } catch (e) {
      print("Error fetching initial locations: $e");
    }
  }

  Future<void> _loadCustomMarker() async {
    _driverIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(96, 96)), // Image configuration
      'assets/images/location_orange3x.png', // Path to the custom PNG asset
    );
    _authorIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(96, 96)), // Image configuration
      'assets/images/location.png', // Path to the author location PNG asset
    );
    setState(() {}); // Trigger UI update after loading the icon
  }

  Future<void> _fetchInitialDriverLocation(String driverId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> driverDoc =
          await firestore.collection('users').doc(driverId).get();

      if (!driverDoc.exists) return;

      final Map<String, dynamic>? data = driverDoc.data();
      if (data == null) return;

      final Map<String, dynamic>? loc = data['location'] is Map<String, dynamic>
          ? data['location'] as Map<String, dynamic>
          : null;
      if (loc == null) return;

      final LatLng initialDriverLocation = LatLng(
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );

      // Set initial driver location and add marker
      driverLocation = initialDriverLocation;
      _setStateThrottled(() {
        markers.add(Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: const InfoWindow(title: "Driver Location"),
        ));
      });
    } catch (e) {
      print("Error fetching initial driver location: $e");
    }
  }

  void subscribeToDriverLocation(String driverId) {
    if (_listenersCancelled) return;
    if (_useDriverPolling) return;
    if (driverLocationSubscription != null) return;
    driverLocationSubscription = firestore
        .collection('users')
        .doc(driverId)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> driverDoc) async {
      if (!_isActive) return;
      if (!driverDoc.exists) return;
      _bumpIdleTimer();

      final Map<String, dynamic>? data = driverDoc.data();
      if (data == null) return;
      final Map<String, dynamic>? loc = data['location'] is Map<String, dynamic>
          ? data['location'] as Map<String, dynamic>
          : null;
      if (loc == null) return;

      final LatLng newDriverLocation = LatLng(
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );
      await _onDriverLocation(newDriverLocation);
    });
  }

  Future<void> _onDriverLocation(LatLng newDriverLocation) async {
    // Throttle UI/movement updates: ignore tiny movement
    final bool movedForUi = driverLocation == null ||
        Geolocator.distanceBetween(
                (driverLocation?.latitude ?? newDriverLocation.latitude),
                (driverLocation?.longitude ?? newDriverLocation.longitude),
                newDriverLocation.latitude,
                newDriverLocation.longitude) >
            _minDriverMoveForUiMeters;

    driverLocation = newDriverLocation;

    if (movedForUi) {
      _setStateThrottled(() {
        markers.removeWhere((m) => m.markerId.value == 'driver');
        markers.add(Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: const InfoWindow(title: "Driver Location"),
        ));
      });
    }

    final now = DateTime.now();
    final bool movedEnough = _lastRouteOrigin == null ||
        Geolocator.distanceBetween(
                _lastRouteOrigin!.latitude,
                _lastRouteOrigin!.longitude,
                newDriverLocation.latitude,
                newDriverLocation.longitude) >
            _minRouteDistanceMeters;
    final bool timeOk = _lastRouteFetch == null ||
        now.difference(_lastRouteFetch!) > _minRouteInterval;

    // Skip reroute if still near the current polyline
    final bool nearCurrentRoute = polylineCoordinates.isNotEmpty &&
        polylineCoordinates.any((p) =>
            Geolocator.distanceBetween(newDriverLocation.latitude,
                newDriverLocation.longitude, p.latitude, p.longitude) <
            _reRouteDeviationMeters);

    if (nearCurrentRoute) return;

    // Best approach: routes are supplied by backend via _subscribeToRouteDocument().
    // Only use client-side Directions if explicitly enabled as a fallback.
    if (movedEnough && timeOk) {
      if (!mounted || !_isActive) return;
      if (_routeCalls >= _maxCallsPerSession) return;
      if (!_enableClientDirectionsFallback) {
        // Audit suppressed client directions attempt
        if (authorLocation != null) {
          await _auditDirections(
            action: 'suppressed',
            reason: 'remote_kill_switch',
            origin: newDriverLocation,
            destination: authorLocation!,
          );
        }
        return;
      }
      _lastRouteFetch = now;
      _lastRouteOrigin = newDriverLocation;
      await _fetchRoute();
    }
  }

  void _startDriverPolling() {
    _stopDriverPolling();
    driverLocationSubscription?.cancel();
    driverLocationSubscription = null;
    if (!_isActive || _listenersCancelled) return;
    if (_driverId == null) return;
    _driverPollTimer = Timer.periodic(_driverPollInterval, (_) async {
      if (!_isActive || _listenersCancelled || _driverId == null) return;
      try {
        final driverDoc =
            await firestore.collection('users').doc(_driverId!).get();
        if (!driverDoc.exists) return;
        _bumpIdleTimer();
        final Map<String, dynamic>? data = driverDoc.data();
        if (data == null) return;
        final Map<String, dynamic>? loc =
            data['location'] is Map<String, dynamic>
                ? data['location'] as Map<String, dynamic>
                : null;
        if (loc == null) return;
        final LatLng newDriverLocation = LatLng(
          (loc['latitude'] as num).toDouble(),
          (loc['longitude'] as num).toDouble(),
        );
        await _onDriverLocation(newDriverLocation);
      } catch (_) {}
    });
  }

  void _stopDriverPolling() {
    _driverPollTimer?.cancel();
    _driverPollTimer = null;
  }

  Future<void> _fetchRoute() async {
    if (authorLocation == null || driverLocation == null) return;
    if (!mounted || !_isActive) return; // app not visible
    if (_routeCalls >= _maxCallsPerSession) return; // absolute cap
    if (!_enableClientDirectionsFallback) return; // disabled by default

    // Try cache first
    final key = _routeCacheKey(driverLocation!, authorLocation!);
    final cached = _routeCache[key];
    if (cached != null) {
      polylineCoordinates = cached;
      await _auditDirections(
        action: 'cache_hit',
        origin: driverLocation!,
        destination: authorLocation!,
      );
      _setStateThrottled(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: polylineCoordinates,
          ),
        };
      });
      return;
    }

    final origin = '${driverLocation!.latitude},${driverLocation!.longitude}';
    final destination =
        '${authorLocation!.latitude},${authorLocation!.longitude}';
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';

    await _auditDirections(
      action: 'executed',
      origin: driverLocation!,
      destination: authorLocation!,
    );

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final points = data['routes'][0]['overview_polyline']['points'];
      polylineCoordinates = _decodePolyline(points);

      _routeCache[key] = polylineCoordinates;

      _setStateThrottled(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: polylineCoordinates,
          ),
        };
      });

      final GoogleMapController mapController = await _controller.future;
      mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
            _getLatLngBounds(polylineCoordinates), 50.0),
      );

      _routeCalls++;
    } else {
      print("Failed to fetch route");
    }
  }

  void _cancelAllListeners({bool permanent = true}) {
    if (_listenersCancelled && permanent) return;
    driverLocationSubscription?.cancel();
    driverLocationSubscription = null;
    orderSubscription?.cancel();
    orderSubscription = null;
    _settingsSubscription?.cancel();
    _settingsSubscription = null;
    _stopDriverPolling();
    _listenersCancelled = permanent;
  }

  void _resubscribeAfterResume() {
    if (orderSubscription == null) {
      _subscribeToRouteDocument();
    }
    if (_useDriverPolling) {
      if (_driverId != null && _driverPollTimer == null) {
        _startDriverPolling();
      }
    } else {
      if (_driverId != null && driverLocationSubscription == null) {
        subscribeToDriverLocation(_driverId!);
      }
    }
    if (_settingsSubscription == null) {
      _subscribeToSettingsKillSwitch();
    }
  }

  void _setStateThrottled(VoidCallback fn) {
    final now = DateTime.now();
    if (_lastUiUpdate != null &&
        now.difference(_lastUiUpdate!) < _minUiUpdateInterval) {
      return;
    }
    _lastUiUpdate = now;
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _auditDirections({
    required String action,
    required LatLng origin,
    required LatLng destination,
    String? reason,
  }) async {
    // Sample audits to reduce Firestore writes
    if (_auditEveryN > 1) {
      _auditCounter++;
      if ((_auditCounter % _auditEveryN) != 0) {
        return;
      }
    }
    try {
      await firestore
          .collection('audit')
          .doc('directions_client')
          .collection('logs')
          .add({
        'ts': FieldValue.serverTimestamp(),
        'orderId': widget.orderId,
        'action': action,
        'reason': reason,
        'origin': {'lat': origin.latitude, 'lng': origin.longitude},
        'destination': {
          'lat': destination.latitude,
          'lng': destination.longitude
        },
      });
    } catch (e) {
      // ignore audit errors
    }
  }

  bool _boundsChanged(LatLngBounds a, LatLngBounds b) {
    double d(double x, double y) => (x - y).abs();
    return d(a.northeast.latitude, b.northeast.latitude) > 0.01 ||
        d(a.northeast.longitude, b.northeast.longitude) > 0.01 ||
        d(a.southwest.latitude, b.southwest.latitude) > 0.01 ||
        d(a.southwest.longitude, b.southwest.longitude) > 0.01;
  }

  void _bumpIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_maxIdle, _cancelAllListeners);
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
  }

  LatLngBounds _getLatLngBounds(List<LatLng> points) {
    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;

    for (LatLng point in points) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _calculateETA() async {
    if (driverLocation == null || authorLocation == null) return;
    if (!mounted) return;

    final origin =
        '${driverLocation!.latitude},${driverLocation!.longitude}';
    final destination =
        '${authorLocation!.latitude},${authorLocation!.longitude}';
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 || !mounted) return;

      final data = json.decode(response.body);
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return;

      final legs = routes[0]['legs'] as List<dynamic>?;
      if (legs == null || legs.isEmpty) return;

      final duration = legs[0]['duration'];
      if (duration == null) return;

      final seconds = (duration['value'] as num?)?.toInt() ?? 0;
      if (seconds <= 0) return;

      if (!mounted) return;
      setState(() {
        _eta = DateTime.now().add(Duration(seconds: seconds));
        _etaTimer?.cancel();
        _etaTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) setState(() {});
        });
      });
    } catch (e) {
      print('ETA fetch error: $e');
    }
  }

  String _formatETA(DateTime? eta) {
    if (eta == null) return '';
    final diff = eta.difference(DateTime.now());
    final totalMins = diff.inMinutes;
    if (totalMins < 1) return 'Arriving now';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}min';
    return '$totalMins min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LalaGO Order Tracking"),
        bottom: _eta != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Container(
                  color: Colors.blue,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'ETA: ${_formatETA(_eta)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: authorLocation == null || driverLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: authorLocation!,
                    zoom: 12,
                  ),
                  markers: markers,
                  polylines: polylines,
                  onMapCreated: (controller) {
                    _controller.complete(controller);
                  },
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BannerAdWidget(
                            adUnitId: AdService.instance.bannerAdUnitId),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
