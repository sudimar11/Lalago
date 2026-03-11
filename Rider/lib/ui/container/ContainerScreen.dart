//import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/CurrencyModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/session_service.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/order_location_service.dart';
import 'package:foodie_driver/services/proximity_config_service.dart';
import 'package:foodie_driver/services/rider_preset_location_service.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/services/array_validation_service.dart';
import 'package:foodie_driver/services/rider_time_config_service.dart';
import 'package:foodie_driver/services/user_listener_service.dart';
import 'package:foodie_driver/services/health_telemetry_service.dart';
import 'package:foodie_driver/ui/profile/ProfileScreen.dart';
//import 'package:foodie_driver/ui/wallet/sample.dart';
//import 'package:foodie_driver/ui/wallet/wallet.dart';
import 'package:foodie_driver/ui/wallet/wallet_detail_page.dart';
import 'package:foodie_driver/ui/ordersScreen/OrdersBlankScreen.dart';
import 'package:foodie_driver/ui/pautos/pautos_order_detail_screen.dart';
import 'package:foodie_driver/ui/communication/unified_communication_hub_screen.dart';
import 'package:foodie_driver/ui/heat_map/DriverHeatMapScreen.dart';
import 'package:foodie_driver/widgets/shared_bottom_navigation_bar.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/ui/auth/AuthScreen.dart';
import 'package:foodie_driver/widgets/shared_app_bar.dart';
import 'package:geolocator/geolocator.dart' hide LocationAccuracy;
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';

enum BottomNavSelection {
  MyOrders,
  Wallet,
  CreditWallet,
  Incentive,
  Profile,
  Hotspots,
}

class ContainerScreen extends StatefulWidget {
  ContainerScreen({Key? key}) : super(key: key);

  @override
  _ContainerScreen createState() {
    return _ContainerScreen();
  }
}

class _ContainerScreen extends State<ContainerScreen>
    with WidgetsBindingObserver {
  String _appBarTitle = 'Orders';
  final fireStoreUtils = FireStoreUtils();
  late Widget _currentWidget;
  BottomNavSelection _bottomNavSelection = BottomNavSelection.MyOrders;
  int _currentIndex = 0;

  bool isLoading = true;

  bool isPop = false;

  Timer? _closingTimeCheckTimer;
  Timer? _inactivityWarningTimer;
  Timer? _periodicLocationTimer;
  DateTime? _lastInactivityWarningAt;
  DateTime? _lastActivityWriteAt;
  StreamSubscription? _locationSubscription;
  bool? _lastCheckedInStatus;
  bool _isSuspended = false;
  bool _remittanceDialogDismissed = false;
  String? _lastKnownAvailability;

  @override
  void initState() {
    super.initState();
    setCurrency();
    NotificationService.onOrderActionFromNotification =
        _handleOrderActionFromNotification;
    NotificationService.onPautosAssignmentTap = _handlePautosAssignmentTap;
    NotificationService.onOpenOrderCommunication =
        _handleOpenOrderCommunication;
    NotificationService.onOpenUnifiedCommunicationHub =
        _handleOpenUnifiedCommunicationHub;

    /// On iOS, we request notification permissions, Does nothing and returns null on Android
    FireStoreUtils.firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Also check immediately on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateClosingTimeTimer();
      _checkClosingTime();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          NotificationService.showEnableNotificationsDialogIfNeeded(context);
        }
      });
      // Run detection in background after UI loads
      Future.delayed(Duration(seconds: 2), () {
        _detectMissingAbsences();
      });
      _checkAttendanceStatus();
      // Start periodic location updates if already online
      Future.delayed(Duration(seconds: 3), () {
        final u = MyAppState.currentUser;
        if (mounted &&
            u != null &&
            u.isOnline == true &&
            u.riderAvailability != 'offline') {
          _startPeriodicLocationUpdates();
        }
      });
      _startInactivityWarningTimer();
      WidgetsBinding.instance.addObserver(this);
      // Start shared user document listener, health telemetry, then
      // remittance enforcement
      final userId = MyAppState.currentUser?.userID;
      if (userId != null && userId.isNotEmpty) {
        UserListenerService.instance.addCallback('container', (data) {
          if (!mounted) return;
          final updatedUser = User.fromJson(data);
          final newAvail = data['riderAvailability'] as String?;
          if (newAvail == 'offline' &&
              _lastKnownAvailability != null &&
              _lastKnownAvailability != 'offline') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'You have been set to offline due to inactivity',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            });
          }
          _lastKnownAvailability = newAvail;
          MyAppState.currentUser = updatedUser;
          setState(() {});
        });
        UserListenerService.instance.start(userId);
        HealthTelemetryService.instance.start(userId);
        final remittanceService =
            Provider.of<RemittanceEnforcementService>(
                context, listen: false);
        remittanceService.startListening(userId);
        ArrayValidationService.validate(userId);
      }
    });
  }

  void _checkClosingTime() async {
    if (MyAppState.currentUser == null || !mounted) return;

    final hasPassed = await SessionService.hasPassedClosingTime();
    if (hasPassed) {
      print(
          '⏰ Closing time passed during periodic check, performing automatic checkout...');
      await MyAppState.performAutomaticCheckout();
    }
  }

  void _startInactivityWarningTimer() {
    _inactivityWarningTimer?.cancel();
    _inactivityWarningTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkInactivityWarning(),
    );
  }

  void _resetInactivityTimer() {
    _inactivityWarningTimer?.cancel();
    _startInactivityWarningTimer();
  }

  void _pauseInactivityTimer() {
    _inactivityWarningTimer?.cancel();
  }

  Future<void> _updateLastActivityTimestamp() async {
    final user = MyAppState.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    if (_lastActivityWriteAt != null &&
        now.difference(_lastActivityWriteAt!).inSeconds < 60) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(USERS)
          .doc(user.userID)
          .update({
        'lastActivityTimestamp': FieldValue.serverTimestamp(),
      });
      _lastActivityWriteAt = now;
    } catch (e) {
      log('Error updating activity: $e');
    }
  }

  void _handleUserInteraction() {
    _resetInactivityTimer();
    _updateLastActivityTimestamp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateLastActivityTimestamp();
      _resetInactivityTimer();
    } else if (state == AppLifecycleState.paused) {
      _pauseInactivityTimer();
    }
  }

  Future<void> _checkInactivityWarning() async {
    if (!mounted) return;
    final user = MyAppState.currentUser;
    if (user == null) return;

    final avail = user.riderAvailability;
    if (avail != 'available' &&
        avail != 'on_delivery' &&
        avail != 'on_break') return;

    final lastActTs = user.lastActivityTimestamp ?? user.locationUpdatedAt;
    if (lastActTs == null) return;

    final lastAct = lastActTs.toDate();
    final now = DateTime.now();
    final inactiveMinutes = now.difference(lastAct).inMinutes;

    int timeoutMinutes = 15;
    try {
      timeoutMinutes =
          await RiderTimeConfigService.instance.getInactivityTimeoutMinutes();
    } catch (_) {}

    final warningThreshold = (timeoutMinutes - 5).clamp(1, 59);
    if (inactiveMinutes < warningThreshold) return;
    if (inactiveMinutes >= timeoutMinutes) {
      _logoutDueToInactivity();
      return;
    }

    final minsLeft = timeoutMinutes - inactiveMinutes;
    final throttle = Duration(minutes: 2);
    if (_lastInactivityWarningAt != null &&
        now.difference(_lastInactivityWarningAt!) < throttle) {
      return;
    }
    _lastInactivityWarningAt = now;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'You will be logged out due to inactivity in '
          '${minsLeft > 0 ? minsLeft : 5} minutes',
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'STAY ONLINE',
          textColor: Colors.white,
          onPressed: () {
            _handleUserInteraction();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Staying online'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _logoutDueToInactivity() async {
    if (!mounted) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text(
          'You have been inactive for too long. '
          'Please log in again to continue receiving orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('STAY ONLINE'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      final userId = MyAppState.currentUser?.userID;
      if (userId != null) {
        try {
          await FirebaseFirestore.instance
              .collection(USERS)
              .doc(userId)
              .update({
            'riderAvailability': 'offline',
            'riderDisplayStatus': 'Offline',
            'lastSeen': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          log('Error updating status on logout: $e');
        }
      }
      try {
        final u = MyAppState.currentUser;
        if (u != null && u.fcmToken.isNotEmpty) {
          unawaited(FireStoreUtils.removeFcmToken(u.userID, u.fcmToken));
        }
        await auth.FirebaseAuth.instance.signOut();
      } catch (e) {
        log('Error signing out: $e');
      }
      if (mounted) {
        pushAndRemoveUntil(context, AuthScreen(), false);
      }
    } else {
      _handleUserInteraction();
    }
  }

  void _updateClosingTimeTimer() {
    final isCheckedIn = MyAppState.currentUser?.isOnline == true;

    if (isCheckedIn && _closingTimeCheckTimer == null) {
      // Start timer when checked in and timer is not running
      _closingTimeCheckTimer = Timer.periodic(
        Duration(minutes: 15),
        (timer) => _checkClosingTime(),
      );
    } else if (!isCheckedIn && _closingTimeCheckTimer != null) {
      // Cancel timer when not checked in and timer is running
      _closingTimeCheckTimer?.cancel();
      _closingTimeCheckTimer = null;
    }
  }

  void _detectMissingAbsences() async {
    if (MyAppState.currentUser == null || !mounted) return;

    try {
      final driverId = MyAppState.currentUser!.userID;
      final absentDaysMarked =
          await DriverPerformanceService.detectAndMarkMissingAbsences(driverId);

      if (absentDaysMarked > 0 && mounted) {
        final pointsDeducted =
            absentDaysMarked * DriverPerformanceService.ADJUSTMENT_ABSENT;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$absentDaysMarked absent day(s) detected and marked. Performance deducted: ${pointsDeducted.toStringAsFixed(1)} points',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to attendance history if needed
              },
            ),
          ),
        );
      }
    } catch (e) {
      // Handle errors gracefully - don't block app startup
      print(
          '⚠️ Error detecting missing absences on app start (non-blocking): $e');
    }
  }

  Future<void> _checkAttendanceStatus() async {
    if (MyAppState.currentUser == null || !mounted) return;

    final latestUser = await AttendanceService.fetchLatestUser(
      MyAppState.currentUser!.userID,
    );
    if (latestUser != null) {
      MyAppState.currentUser = latestUser;
    }

    final currentUser = latestUser ?? MyAppState.currentUser!;
    await AttendanceService.touchLastActiveDate(currentUser);

    if (!mounted) return;
    setState(() {
      _isSuspended = currentUser.suspended == true ||
          (currentUser.attendanceStatus?.toLowerCase() == 'suspended');
    });
  }

  void _handleOrderActionFromNotification(String orderId, String action) {
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _bottomNavSelection = BottomNavSelection.MyOrders;
      _appBarTitle = 'Orders';
      _currentWidget = OrdersBlankScreen();
    });
  }

  void _handlePautosAssignmentTap(String orderId) {
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _bottomNavSelection = BottomNavSelection.MyOrders;
      _appBarTitle = 'Orders';
      _currentWidget = OrdersBlankScreen();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PautosOrderDetailScreen(orderId: orderId),
          ),
        );
      }
    });
  }

  Future<void> _handleOpenOrderCommunication(String orderId) async {
    _handleOpenUnifiedCommunicationHub(
      UnifiedCommunicationTab.restaurants.name,
      orderId,
    );
  }

  Future<void> _handleOpenUnifiedCommunicationHub(
    String initialTab,
    String orderId,
  ) async {
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _bottomNavSelection = BottomNavSelection.MyOrders;
      _appBarTitle = 'Orders';
      _currentWidget = OrdersBlankScreen();
    });

    var tab = UnifiedCommunicationTab.customers;
    if (initialTab == UnifiedCommunicationTab.restaurants.name) {
      tab = UnifiedCommunicationTab.restaurants;
    } else if (initialTab == UnifiedCommunicationTab.support.name) {
      tab = UnifiedCommunicationTab.support;
    } else if (initialTab == UnifiedCommunicationTab.community.name) {
      tab = UnifiedCommunicationTab.community;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UnifiedCommunicationHubScreen(
            initialTab: tab,
            initialOrderId: orderId.isNotEmpty ? orderId : null,
            autoOpenConversation: orderId.isNotEmpty,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    NotificationService.onOrderActionFromNotification = null;
    NotificationService.onPautosAssignmentTap = null;
    NotificationService.onOpenOrderCommunication = null;
    NotificationService.onOpenUnifiedCommunicationHub = null;
    _closingTimeCheckTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    _periodicLocationTimer?.cancel();
    _locationSubscription?.cancel();
    OrderLocationService.stopMonitoring();
    // Stop remittance enforcement listener
    try {
      final remittanceService =
          Provider.of<RemittanceEnforcementService>(
              context, listen: false);
      remittanceService.stopListening();
    } catch (_) {}
    HealthTelemetryService.instance.stop();
    UserListenerService.instance.removeCallback('container');
    UserListenerService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void setPop(bool value) {
    setState(() {
      isPop = value;
    });
  }

  setCurrency() async {
    _currentWidget = OrdersBlankScreen();

    // Show content within 2s so slide button appears promptly for first-time riders
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
    });
    // Ensure screen shows even if network/location is very slow (max 12s)
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
    });

    try {
      final currency = await FireStoreUtils()
          .getCurrency()
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          currencyModel = currency ??
              CurrencyModel(
                id: "",
                code: "USD",
                decimal: 2,
                name: "US Dollar",
                symbol: "\$",
                symbolatright: false,
              );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          currencyModel = CurrencyModel(
            id: "",
            code: "USD",
            decimal: 2,
            name: "US Dollar",
            symbol: "\$",
            symbolatright: false,
          );
        });
      }
    }

    try {
      final driverNearBy = await FireStoreUtils.firestore
          .collection(Setting)
          .doc("DriverNearBy")
          .get()
          .timeout(const Duration(seconds: 5));
      final data = driverNearBy.data();
      if (mounted) {
        setState(() {
          minimumDepositToRideAccept =
              data?['minimumDepositToRideAccept'] ?? "0";
          driverLocationUpdate = data?['driverLocationUpdate'] ?? "2";
          singleOrderReceive = data?['singleOrderReceive'] ?? false;
          mapType = data?['mapType'] ?? "normal";
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          minimumDepositToRideAccept = "0";
          driverLocationUpdate = "2";
          singleOrderReceive = false;
          mapType = "normal";
        });
      }
    }

    if (mounted) setState(() => isLoading = false);

    _loadRemainingSettings();
  }

  Future<void> _loadRemainingSettings() async {
    try {
      await updateCurrentLocation().timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } catch (e, st) {
      // Location/background slow or failed; continue loading payment settings
    }
    try {
      await FireStoreUtils.getPaypalSettingData();
      await FireStoreUtils.getStripeSettingData();
      await FireStoreUtils.getPayStackSettingData();
      await FireStoreUtils.getFlutterWaveSettingData();
      await FireStoreUtils.getPaytmSettingData();
      await FireStoreUtils.getWalletSettingData();
      await FireStoreUtils.getPayFastSettingData();
      await FireStoreUtils.getMercadoPagoSettingData();
      await FireStoreUtils.getReferralAmount();
    } catch (_) {}
    try {
      final doc = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('placeHolderImage')
          .get()
          .timeout(const Duration(seconds: 5));
      final value = doc.data()?['image'] ?? '';
      if (mounted) setState(() => placeholderImage = value);
    } catch (_) {}
  }

  DateTime preBackpress = DateTime.now();

  //final audioPlayer = AudioPlayer(playerId: "playerId");
  Location location = Location();

  // Location update optimization variables
  Duration _minLocationUpdateInterval = Duration(seconds: 25);
  double _minMovementThresholdMeters = 30.0;
  double _duplicateThresholdMeters = 5.0;
  DateTime? _lastAcceptedLocationUpdate;
  UserLocation? _lastAcceptedLocation;
  UserLocation? _lastStoredLocation;

  // Debug logging counters
  int _rawLocationEventCount = 0;
  int _acceptedLocationUpdateCount = 0;
  int _skippedLocationUpdateCount = 0;
  int _firestoreWriteCount = 0;

  // User data cache to reduce Firestore reads
  User? _cachedDriverUser;
  DateTime? _cachedDriverUserFetchedAt;

  /// Last time we showed "outside service area" warning (throttle).
  DateTime? _lastOutsideRadiusWarningAt;
  static const _outsideRadiusWarningThrottle = Duration(minutes: 5);

  /// When rider first went outside radius; null when inside.
  DateTime? _firstOutsideRadiusAt;
  /// True after penalty applied this session (until rider returns inside).
  bool _outsideRadiusPenaltyApplied = false;
  static const _outsideRadiusPenaltyThreshold = Duration(minutes: 30);

  /// Max distance filter (m) when rider has no active order for accurate ETA.
  static const double _maxDistanceFilterWhenAvailable = 20.0;

  void _adjustLocationThresholds(bool hasActiveOrder) {
    if (hasActiveOrder) {
      // Active delivery: Precise tracking
      _minLocationUpdateInterval = Duration(seconds: 25);
      _minMovementThresholdMeters = 30.0;
      _duplicateThresholdMeters = 5.0;
    } else {
      // No active order: Relaxed tracking (2x intervals)
      _minLocationUpdateInterval = Duration(seconds: 60);
      _minMovementThresholdMeters = 100.0;
      _duplicateThresholdMeters = 10.0;
    }
  }

  /// Check if rider is outside selected service area radius and show warning.
  Future<void> _checkAndWarnOutsideServiceArea(
    User value,
    UserLocation currentLocation,
  ) async {
    final presetId = value.selectedPresetLocationId;
    if (presetId == null || presetId.trim().isEmpty) return;

    final preset =
        await RiderPresetLocationService.getPresetById(presetId);
    if (preset == null || !preset.hasRadius) return;

    final isInside =
        RiderPresetLocationService.isWithinRadius(currentLocation, preset);

    if (isInside) {
      _firstOutsideRadiusAt = null;
      _outsideRadiusPenaltyApplied = false;
      return;
    }

    final now = DateTime.now();
    _firstOutsideRadiusAt ??= now;

    final hasActiveOrder = value.inProgressOrderID != null &&
        value.inProgressOrderID!.isNotEmpty;

    if (!hasActiveOrder &&
        !_outsideRadiusPenaltyApplied &&
        now.difference(_firstOutsideRadiusAt!) >=
            _outsideRadiusPenaltyThreshold) {
      _outsideRadiusPenaltyApplied = true;
      try {
        final newPerf = await DriverPerformanceService
            .applyOutsideServiceAreaPenalty(value.userID);
        if (MyAppState.currentUser?.userID == value.userID) {
          MyAppState.currentUser!.driverPerformance = newPerf;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bawasan ang performance (-1.0) dahil nasa labas ng service '
                'area ng 30+ minuto. Bumalik sa loob para makareceive ng orders.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        log('Error applying outside service area penalty: $e');
      }
    }

    if (_lastOutsideRadiusWarningAt != null &&
        now.difference(_lastOutsideRadiusWarningAt!) <
            _outsideRadiusWarningThrottle) {
      return;
    }
    _lastOutsideRadiusWarningAt = now;

    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _showOutsideServiceAreaDialog(preset.name);
  }

  void _showOutsideServiceAreaDialog(String areaName) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Labas ng Service Area'),
        content: Text(
          'Nasa labas ka na ng "$areaName". '
          'Bumalik sa loob ng radius para makareceive ng orders.',
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

  updateCurrentLocation() async {
    log("-------->$driverLocationUpdate");

    // Check if current user is null
    if (MyAppState.currentUser == null) {
      log('MyAppState.currentUser is null. Cannot update location.');
      return;
    }

    // Inner function to listen and update location (non-blocking; failures
    // must not block screen)
    void startLocationListener() {
      try {
        location.enableBackgroundMode(enable: true);
        final initialParsed = double.tryParse(driverLocationUpdate) ?? 10.0;
        final initialFilter = initialParsed <= _maxDistanceFilterWhenAvailable
            ? initialParsed
            : _maxDistanceFilterWhenAvailable;
        location.changeSettings(
          accuracy: LocationAccuracy.balanced,
          distanceFilter: initialFilter,
        );
      } catch (e, st) {
        log('Location enableBackgroundMode/changeSettings failed: $e');
        return;
      }

      _locationSubscription?.cancel();
      _locationSubscription = location.onLocationChanged.listen((locationData) async {
        // Increment raw location event counter
        _rawLocationEventCount++;
        locationDataFinal = locationData;

        final userId = MyAppState.currentUser?.userID;
        if (userId == null) {
          log('User ID is null. Skipping location update.');
          _skippedLocationUpdateCount++;
          return;
        }

        // Create new location object (needed for movement checks)
        final newLocation = UserLocation(
          latitude: locationData.latitude ?? 0.0,
          longitude: locationData.longitude ?? 0.0,
        );

        // Accuracy filter: skip low-quality GPS readings for proximity
        final maxAcc = ProximityConfigService.instance.maxAllowedAccuracy;
        if (locationData.accuracy != null &&
            locationData.accuracy! > maxAcc) {
          _skippedLocationUpdateCount++;
          return;
        }

        // Fix #1: Rate Limiter Check (before Firestore read)
        final now = DateTime.now();
        if (_lastAcceptedLocationUpdate != null) {
          final timeSinceLastUpdate =
              now.difference(_lastAcceptedLocationUpdate!);
          if (timeSinceLastUpdate < _minLocationUpdateInterval) {
            // Skip update - too soon since last accepted update
            _skippedLocationUpdateCount++;
            return;
          }
        }

        // Fix #2: Movement Threshold Check (before Firestore read)
        if (_lastAcceptedLocation != null) {
          final distanceMoved = Geolocator.distanceBetween(
            _lastAcceptedLocation!.latitude,
            _lastAcceptedLocation!.longitude,
            newLocation.latitude,
            newLocation.longitude,
          );

          if (distanceMoved < _minMovementThresholdMeters) {
            // Skip update - movement too small
            _skippedLocationUpdateCount++;
            return;
          }
        }

        // Fix #3: Prevent Duplicate Firestore Writes (before Firestore read)
        if (_lastStoredLocation != null) {
          final distanceFromLastWrite = Geolocator.distanceBetween(
            _lastStoredLocation!.latitude,
            _lastStoredLocation!.longitude,
            newLocation.latitude,
            newLocation.longitude,
          );

          if (distanceFromLastWrite < _duplicateThresholdMeters) {
            // Skip write - location essentially unchanged
            _skippedLocationUpdateCount++;
            return;
          }
        }

        // Active status check using cached or MyAppState data (before Firestore read)
        final cachedOrGlobalUser = _cachedDriverUser ?? MyAppState.currentUser;
        if (cachedOrGlobalUser != null) {
          final hasActiveOrder = cachedOrGlobalUser.inProgressOrderID != null &&
              cachedOrGlobalUser.inProgressOrderID!.isNotEmpty;
          
          // NEW: Adjust thresholds based on active order status
          _adjustLocationThresholds(hasActiveOrder);
          
          if (!hasActiveOrder && !cachedOrGlobalUser.isActive) {
            // Skip location processing when no active delivery
            _skippedLocationUpdateCount++;
            OrderLocationService.stopMonitoring();
            return;
          }
        }

        // Guard: Invalidate cache if active order state changed
        if (_cachedDriverUser != null && MyAppState.currentUser != null) {
          final cachedOrderIds =
              _cachedDriverUser!.inProgressOrderID ?? <String>[];
          final currentOrderIds =
              MyAppState.currentUser!.inProgressOrderID ?? <String>[];

          if (cachedOrderIds.length != currentOrderIds.length ||
              !cachedOrderIds.every((id) => currentOrderIds.contains(id))) {
            _cachedDriverUser = null;
            _cachedDriverUserFetchedAt = null;
          }
        }

        // Fetch user data from cache or Firestore (only after cheap checks pass)
        User? value;
        final cacheAge = _cachedDriverUserFetchedAt != null
            ? now.difference(_cachedDriverUserFetchedAt!)
            : null;
        final isCacheValid = _cachedDriverUser != null &&
            cacheAge != null &&
            cacheAge.inSeconds < 60;

        if (isCacheValid) {
          // Use cached user data
          value = _cachedDriverUser;
        } else {
          // Cache is stale or missing - fetch from Firestore
          value = await FireStoreUtils.getCurrentUser(userId);
          if (value != null) {
            _cachedDriverUser = value;
            _cachedDriverUserFetchedAt = now;
          }
        }

        if (value == null) {
          log('User not found. Skipping location update.');
          _skippedLocationUpdateCount++;
          OrderLocationService.stopMonitoring();
          return;
        }

        // Fix #4: Active Delivery Guard (verify with fresh data if needed)
        // Only process if has active order OR is explicitly tracking
        final hasActiveOrder = value.inProgressOrderID != null &&
            value.inProgressOrderID!.isNotEmpty;
        
        // NEW: Adjust thresholds based on fresh data (may differ from cached)
        _adjustLocationThresholds(hasActiveOrder);
        
        final isCheckedInAndOnline = value.isOnline == true &&
            value.riderAvailability != 'offline';
        print('LOCATION CHECK - hasActiveOrder: $hasActiveOrder, '
            'isActive: ${value.isActive}, isOnline: ${value.isOnline}, '
            'riderAvailability: ${value.riderAvailability}');
        if (!hasActiveOrder &&
            !value.isActive &&
            !isCheckedInAndOnline) {
          _skippedLocationUpdateCount++;
          OrderLocationService.stopMonitoring();
          return;
        }

        // Fix #5: Reduce accuracy when high precision is unnecessary
        // Update accuracy based on active order status
        final accuracy =
            hasActiveOrder ? LocationAccuracy.high : LocationAccuracy.balanced;
        // Distance filter: when available for orders, cap for accurate ETA
        final parsed = double.tryParse(driverLocationUpdate) ?? 10.0;
        final distanceFilterValue = hasActiveOrder
            ? parsed
            : (parsed <= _maxDistanceFilterWhenAvailable
                ? parsed
                : _maxDistanceFilterWhenAvailable);
        location.changeSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilterValue,
        );

        // All checks passed - accept this location update
        _acceptedLocationUpdateCount++;
        _lastAcceptedLocationUpdate = now;
        _lastAcceptedLocation = newLocation;

        // Update user location
        value.location = newLocation;
        value.rotation = locationData.heading;
        value.locationUpdatedAt = Timestamp.now();

        // Write to Firestore
        await FireStoreUtils.updateCurrentUser(value);
        _firestoreWriteCount++;
        _lastStoredLocation = newLocation;

        try {
          await FireStoreUtils.touchLastActivity(userId);
        } catch (e) {
          log('touchLastActivity failed (non-fatal): $e');
        }

        log('📍 Location updated for user: $userId');

        // Fix #6: Isolate Background Tracking from Paid APIs
        // Only call OrderLocationService after all filters pass
        String? activeOrderId;
        if (value.inProgressOrderID != null &&
            value.inProgressOrderID!.isNotEmpty) {
          activeOrderId = value.inProgressOrderID!.first.toString();
        }
        await OrderLocationService.onLocationUpdate(newLocation, activeOrderId);

        // Check if rider went outside their selected service area radius
        _checkAndWarnOutsideServiceArea(value, newLocation);

        // Fix #7: Debug Logging (periodic summary)
        if (_rawLocationEventCount % 10 == 0) {
          log('📍 Location Stats: raw=$_rawLocationEventCount, accepted=$_acceptedLocationUpdateCount, skipped=$_skippedLocationUpdateCount, writes=$_firestoreWriteCount');
        }
      });
    }

    try {
      await ProximityConfigService.instance.getConfig();
      final permissionStatus = await location.hasPermission().timeout(
        const Duration(seconds: 10),
        onTimeout: () => PermissionStatus.denied,
      );
      if (permissionStatus == PermissionStatus.granted) {
        startLocationListener();
        return;
      }
      final requestedPermission = await location.requestPermission().timeout(
        const Duration(seconds: 10),
        onTimeout: () => PermissionStatus.denied,
      );
      if (requestedPermission == PermissionStatus.granted) {
        startLocationListener();
      } else {
        log('Location permission denied.');
      }
    } catch (e, st) {
      log('Location permission check failed: $e');
    }
  }

  void _toggleAttendance() async {
    final user = MyAppState.currentUser;
    if (user == null) return;

    if (user.isOnline != true) {
      // Check zone capacity before allowing go-online
      final presetId = user.selectedPresetLocationId;
      if (presetId != null && presetId.trim().isNotEmpty) {
        try {
          final capResult =
              await RiderPresetLocationService.checkCapacity(
            presetId,
          );
          if (!capResult.allowed && mounted) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Zone at Capacity'),
                content: Text(
                  'This zone has '
                  '${capResult.currentCount}/'
                  '${capResult.maxRiders} riders active. '
                  'You may not receive orders. '
                  'Continue going online anyway?',
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, true),
                    child: const Text('Go Online Anyway'),
                  ),
                ],
              ),
            );
            if (proceed != true) return;
          }
        } catch (e) {
          log('Capacity check failed (proceeding): $e');
        }
      }

      user.isOnline = true;
      user.isActive = true;
      user.active = true;
      // Fix 2: Set location from preset on go-online
      if (presetId != null && presetId.trim().isNotEmpty) {
        try {
          final preset =
              await RiderPresetLocationService.getPresetById(presetId);
          if (preset != null) {
            user.location = UserLocation(
              latitude: preset.latitude,
              longitude: preset.longitude,
            );
            user.locationUpdatedAt = Timestamp.now();
          }
        } catch (e) {
          log('Preset location load failed on go-online: $e');
        }
      }
    } else {
      user.isOnline = false;
      user.riderAvailability = 'offline';
      user.isActive = false;

      // Remove rider from zone on go-offline
      final presetId = user.selectedPresetLocationId;
      if (presetId != null && presetId.trim().isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('service_areas')
              .doc(presetId)
              .update({
            'assignedDriverIds': FieldValue.arrayRemove([user.userID]),
          });
        } catch (e) {
          log('Zone removal on go-offline failed: $e');
        }
      }
      _stopPeriodicLocationUpdates();
    }

    UserListenerService.instance.markLocalMutation();
    await FireStoreUtils.updateCurrentUser(user);

    // Fix 3: Add rider to zone assignedDriverIds on go-online
    if (user.isOnline == true &&
        user.selectedPresetLocationId != null &&
        user.selectedPresetLocationId!.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('service_areas')
            .doc(user.selectedPresetLocationId!)
            .update({
          'assignedDriverIds': FieldValue.arrayUnion([user.userID]),
        });
      } catch (e) {
        log('Zone add on go-online failed: $e');
      }
    }

    await OrderService.updateRiderStatus();
    if (user.isOnline == true) {
      await FireStoreUtils.touchLastActivity(user.userID);
      _startPeriodicLocationUpdates();
    }
    if (mounted) setState(() {});
  }

  void _toggleBreak() async {
    final user = MyAppState.currentUser;
    if (user == null) return;
    final isOnBreak = user.riderAvailability == 'on_break';
    if (isOnBreak) {
      await OrderService.updateRiderStatus();
    } else {
      await OrderService.updateRiderStatus(
        overrideAvailability: 'on_break',
      );
    }
    if (mounted) setState(() {});
  }

  /// Fix 4: Periodic location refresh to keep locationUpdatedAt fresh
  void _startPeriodicLocationUpdates() {
    _stopPeriodicLocationUpdates();
    _periodicLocationTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshLocationForPrecheck(),
    );
  }

  void _stopPeriodicLocationUpdates() {
    _periodicLocationTimer?.cancel();
    _periodicLocationTimer = null;
  }

  Future<void> _refreshLocationForPrecheck() async {
    final user = MyAppState.currentUser;
    if (user == null || user.isOnline != true || !mounted) return;
    try {
      final loc = await location.getLocation();
      if (loc.latitude == null || loc.longitude == null) return;
      final freshUser = await FireStoreUtils.getCurrentUser(user.userID);
      if (freshUser == null || freshUser.isOnline != true) return;
      freshUser.location = UserLocation(
        latitude: loc.latitude!,
        longitude: loc.longitude!,
      );
      freshUser.locationUpdatedAt = Timestamp.now();
      await FireStoreUtils.updateCurrentUser(freshUser);
    } catch (_) {}
  }

  void _onBottomNavTap(int index) {
    // Prevent navigation if account is suspended
    if (MyAppState.currentUser?.suspended == true) {
      return;
    }

    setState(() {
      _currentIndex = index;
      switch (index) {
        case 0:
          _bottomNavSelection = BottomNavSelection.MyOrders;
          _appBarTitle = 'Orders';
          _currentWidget = OrdersBlankScreen();
          break;
        case 1:
          _bottomNavSelection = BottomNavSelection.Wallet;
          _appBarTitle = 'Wallet';
          _currentWidget = const WalletDetailPage(
            walletType: 'earning',
          );
          break;
        case 2:
          _bottomNavSelection = BottomNavSelection.Hotspots;
          _appBarTitle = 'Hotspots';
          _currentWidget = const DriverHeatMapScreen();
          break;
        case 3:
          _bottomNavSelection = BottomNavSelection.Profile;
          _appBarTitle = 'My Profile';
          _currentWidget = ProfileScreen(
            user: MyAppState.currentUser!,
          );
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (isPop, dynamic) async {
        final timegap = DateTime.now().difference(preBackpress);
        final cantExit = timegap >= Duration(seconds: 2);
        preBackpress = DateTime.now();
        if (cantExit) {
          final snack = SnackBar(
            content: Text(
              'Press Back button again to Exit',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.black,
          );
          ScaffoldMessenger.of(context).showSnackBar(snack);
          return setPop(false); // false will do nothing when back press
        } else {
          return setPop(true); // true will exit the app
        }
      },
      child: ChangeNotifierProvider.value(
        value: MyAppState.currentUser,
        child: Consumer<User>(
          builder: (context, user, _) {
            final remittanceService =
                context.watch<RemittanceEnforcementService>();
            if (!remittanceService.isBlockedByRemittance) {
              _remittanceDialogDismissed = false;
            }
            // Monitor check-in status changes and update timer
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final currentCheckedIn = user.isOnline == true;
              if (_lastCheckedInStatus != currentCheckedIn) {
                _updateClosingTimeTimer();
                _lastCheckedInStatus = currentCheckedIn;
              }
            });

            return GestureDetector(
              onTap: _handleUserInteraction,
              onPanDown: (_) => _handleUserInteraction(),
              behavior: HitTestBehavior.opaque,
              child: Scaffold(
                appBar: SharedAppBar(
                title: _appBarTitle,
                user: user,
                automaticallyImplyLeading: false,
                centerTitle: _bottomNavSelection == BottomNavSelection.Wallet,
                isOutsideServiceArea: _firstOutsideRadiusAt != null,
                firstOutsideAt: _firstOutsideRadiusAt,
                outsidePenaltyThresholdMinutes: 30,
                onToggleAttendance: _toggleAttendance,
              ),
              body: isLoading == true
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            _RiderStatusBar(
                              displayStatus:
                                  user.riderDisplayStatus ?? '⚪ Offline',
                              availability:
                                  user.riderAvailability ?? 'offline',
                              onToggleBreak: _toggleBreak,
                            ),
                            Expanded(child: _currentWidget),
                          ],
                        ),
                        if (remittanceService.isBlockedByRemittance &&
                            !_remittanceDialogDismissed)
                          _RemittanceBlockingOverlay(
                            onGoToWallet: () {
                              setState(() {
                                _remittanceDialogDismissed = true;
                                _currentIndex = 1;
                                _bottomNavSelection =
                                    BottomNavSelection.Wallet;
                                _appBarTitle = 'Wallet';
                                _currentWidget = const WalletDetailPage(
                                  walletType: 'credit',
                                );
                              });
                            },
                          ),
                      ],
                    ),
              bottomNavigationBar: SharedBottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: _onBottomNavTap,
                isDisabled: user.suspended == true,
              ),
            ),
            );
          },
        ),
      ),
    );
  }

}

class _RemittanceBlockingOverlay extends StatelessWidget {
  final VoidCallback onGoToWallet;

  const _RemittanceBlockingOverlay({required this.onGoToWallet});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 48,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Daily Remittance Required',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText.rich(
                    TextSpan(
                      text:
                          'You have an unremitted credit wallet balance. '
                          'Please remit your earnings from yesterday '
                          'before accepting orders. Go to Wallet to '
                          'submit a transmit request.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onGoToWallet,
                      icon: const Icon(Icons.account_balance_wallet),
                      label: const Text('Go to Wallet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderStatusBar extends StatelessWidget {
  final String displayStatus;
  final String availability;
  final VoidCallback onToggleBreak;

  const _RiderStatusBar({
    required this.displayStatus,
    required this.availability,
    required this.onToggleBreak,
  });

  @override
  Widget build(BuildContext context) {
    final isOnBreak = availability == 'on_break';
    final showBreakButton =
        availability == 'available' ||
        availability == 'on_delivery' ||
        isOnBreak;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      color: _statusColor.withOpacity(0.15),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayStatus,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showBreakButton)
            TextButton.icon(
              onPressed: onToggleBreak,
              icon: Icon(
                isOnBreak ? Icons.play_arrow : Icons.pause,
                size: 18,
              ),
              label: Text(
                isOnBreak ? 'Resume Working' : 'Take Break',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (availability) {
      case 'available':
        return Colors.green;
      case 'on_delivery':
        return Colors.amber;
      case 'on_break':
        return Colors.blue;
      case 'checked_out':
        return Colors.black54;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
