import 'dart:async';

import 'package:brgy/constants.dart';
import 'package:brgy/services/zone_capacity_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriversMapPage extends StatefulWidget {
  @override
  State<DriversMapPage> createState() => _DriversMapPageState();
}

class _DriversMapPageState extends State<DriversMapPage> {
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();
  final Set<Marker> _markers = <Marker>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driverSub;
  String? _lastErrorMessage;
  int _lastSnapshotCount = 0;
  List<Map<String, dynamic>> _activeRiders = [];
  bool _mapReady = false;
  bool _hasFittedCamera = false;
  bool _streamLoaded = false;
  bool _mapError = false;
  bool _showCapacityOverlay = false;
  final Set<Circle> _capacityCircles = <Circle>{};
  StreamSubscription<List<ZoneCapacity>>? _capacitySub;
  List<ZoneCapacity> _zoneCapacities = [];

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842), // Manila fallback
    zoom: 5.5,
  );

  int _activeOrdersFromData(Map<String, dynamic> data) {
    final dynamic raw = data['inProgressOrderID'];
    if (raw is List) return raw.length;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  String _formatCheckedInTime(Map<String, dynamic> data) {
    final dynamic raw = data['checkedInTodayTimestamp'] ??
        data['checkedInAt'] ??
        data['checkedInTime'] ??
        data['checkedInTimestamp'] ??
        data['lastOnlineTimestamp'];
    if (raw is Timestamp) {
      return _formatDateTime(raw.toDate());
    }
    if (raw is DateTime) {
      return _formatDateTime(raw);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return _formatDateTime(parsed);
    }
    return 'Unknown';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} $hour:$minute';
  }

  String _getRiderDisplayStatus(Map<String, dynamic> data) {
    final availability =
        data['riderAvailability'] as String? ?? 'offline';
    final lastActive =
        data['lastActivityTimestamp'] as Timestamp?;
    final locationUpdated =
        data['locationUpdatedAt'] as Timestamp?;

    if (availability == 'offline' || availability == 'checked_out') {
      return 'Offline';
    }

    final lastActivity = lastActive ?? locationUpdated;
    if (lastActivity != null) {
      final minutesSince =
          DateTime.now().difference(lastActivity.toDate()).inMinutes;
      if (minutesSince > 15) return 'Inactive';
      if (minutesSince > 10) return 'Away';
    }

    switch (availability) {
      case 'available':
        return 'Available';
      case 'on_delivery':
        return 'On Delivery';
      case 'on_break':
        return 'On Break';
      default:
        return 'Unknown';
    }
  }

  bool _hasRecentActivity(Map<String, dynamic> data) {
    final lastActive =
        data['lastActivityTimestamp'] as Timestamp?;
    final locationUpdated =
        data['locationUpdatedAt'] as Timestamp?;
    final lastActivity = lastActive ?? locationUpdated;
    if (lastActivity == null) return false;
    final minutesSince =
        DateTime.now().difference(lastActivity.toDate()).inMinutes;
    return minutesSince <= 15;
  }

  Future<void> _checkoutAllRiders(BuildContext context) async {
    if (_activeRiders.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final rider in _activeRiders) {
        final riderId = rider['riderId'] as String?;
        if (riderId != null && riderId.isNotEmpty) {
          final riderRef =
              FirebaseFirestore.instance.collection(USERS).doc(riderId);
          batch.update(riderRef, {'checkedOutToday': true});
        }
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All riders have been checked out successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking out riders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('[DriversMap] Error checking out all riders: $e');
    }
  }

  void _showActiveRidersDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Active riders'),
          content: SizedBox(
            width: double.maxFinite,
            child: _activeRiders.isEmpty
                ? const Text('No active riders found.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _activeRiders.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final rider = _activeRiders[index];
                            final name = rider['name'] as String? ?? 'Unknown';
                            final checkedIn =
                                rider['checkedInTime'] as String? ?? 'Unknown';
                            final status =
                                rider['displayStatus'] as String? ?? '⚪ Offline';
                            return ListTile(
                              leading: Text(
                                status,
                                style: const TextStyle(fontSize: 14),
                              ),
                              title: Text(name),
                              subtitle: Text('Checked in: $checkedIn'),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _checkoutAllRiders(context),
                          icon: const Icon(Icons.logout),
                          label: const Text('Checkout All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribeDrivers();
  }

  @override
  void dispose() {
    _driverSub?.cancel();
    _capacitySub?.cancel();
    super.dispose();
  }

  void _toggleCapacityOverlay() {
    setState(() {
      _showCapacityOverlay = !_showCapacityOverlay;
      if (_showCapacityOverlay) {
        _startCapacityStream();
      } else {
        _capacitySub?.cancel();
        _capacitySub = null;
        _capacityCircles.clear();
        _zoneCapacities = [];
      }
    });
  }

  void _startCapacityStream() {
    _capacitySub?.cancel();
    final service = ZoneCapacityService();
    _capacitySub = service
        .streamAllZoneCapacities()
        .listen((capacities) {
      if (!mounted) return;
      _zoneCapacities = capacities;
      final circles = <Circle>{};
      for (final zc in capacities) {
        final zone = zc.zone;
        if (zone.boundaryType != 'radius') continue;
        final lat = zone.centerLat;
        final lng = zone.centerLng;
        final rKm = zone.radiusKm;
        if (lat == null || lng == null || rKm == null) continue;
        circles.add(
          Circle(
            circleId: CircleId('cap_${zone.id}'),
            center: LatLng(lat, lng),
            radius: rKm * 1000,
            fillColor:
                zc.statusColor.withValues(alpha: 0.2),
            strokeColor: zc.statusColor,
            strokeWidth: 2,
            consumeTapEvents: true,
            onTap: () => _showCapacityTooltip(zc),
          ),
        );
      }
      setState(() {
        _capacityCircles
          ..clear()
          ..addAll(circles);
      });
    });
  }

  void _showCapacityTooltip(ZoneCapacity zc) {
    final label = zc.maxRiders != null
        ? '${zc.currentActiveRiders}/${zc.maxRiders} riders'
        : '${zc.currentActiveRiders} riders (unlimited)';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(zc.zone.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            if (zc.maxRiders != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:
                      (zc.utilizationPercentage / 100)
                          .clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(
                    zc.statusColor,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Status: ${zc.capacityStatus.toUpperCase()}',
                style: TextStyle(
                  color: zc.statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _subscribeDrivers() {
    // Query all drivers - we'll filter by checkedOutToday in code
    // since Firestore doesn't support != true queries directly
    final query = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER);

    _driverSub = query.snapshots().listen(
      (snapshot) async {
        _streamLoaded = true;
        final Set<Marker> newMarkers = <Marker>{};
        final List<Map<String, dynamic>> activeRiders = [];
        int activeCount = 0;
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final loc = data['location'];
            final String fullName =
                '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
            final String riderName =
                fullName.isEmpty ? 'Unknown Rider' : fullName;
            final String displayStatus =
                _getRiderDisplayStatus(data);
            final String availability =
                data['riderAvailability'] as String? ?? 'offline';
            final bool isActive =
                (availability == 'available' ||
                    availability == 'on_delivery') &&
                _hasRecentActivity(data);
            if (isActive) {
              activeCount++;
              final String riderId = doc.id;
              activeRiders.add({
                'riderId': riderId,
                'name': riderName,
                'checkedInTime': _formatCheckedInTime(data),
                'displayStatus': displayStatus,
              });
            }
            if (isActive &&
                loc is Map &&
                loc['latitude'] != null &&
                loc['longitude'] != null) {
              final double lat = (loc['latitude'] as num).toDouble();
              final double lng = (loc['longitude'] as num).toDouble();
              final String riderId = doc.id;
              final String car = data['carName'] ?? '';
              final String number = data['carNumber'] ?? '';

              // Idle detection: prefer locationUpdatedAt, fallback to lastOnlineTimestamp
              final Timestamp? locTs = data['locationUpdatedAt'] as Timestamp? ??
                  data['lastOnlineTimestamp'] as Timestamp?;
              final Duration? idleDuration = locTs != null
                  ? DateTime.now().difference(locTs.toDate())
                  : null;
              // If both null, treat as stale (no recent data)
              final bool isMoving =
                  idleDuration != null && idleDuration.inMinutes < 5;
              final bool isIdle = idleDuration != null &&
                  idleDuration.inMinutes >= 5 &&
                  idleDuration.inMinutes < 15;
              final bool isStale =
                  idleDuration == null || idleDuration.inMinutes >= 15;

              String timestampText;
              if (isMoving) {
                timestampText = idleDuration!.inMinutes < 1
                    ? 'Updated: Just now'
                    : 'Moving';
              } else if (isIdle) {
                timestampText = 'Idle ${idleDuration!.inMinutes} min';
              } else {
                timestampText =
                    'No update ${idleDuration?.inMinutes ?? 0} min';
              }

              // Build snippet with car info and status
              final int activeOrders = _activeOrdersFromData(data);
              final bool hasActiveOrders = activeOrders > 0;

              final List<String> snippetParts = [];
              if (car.isNotEmpty || number.isNotEmpty) {
                snippetParts.add([car, number]
                    .where((e) => (e).toString().isNotEmpty)
                    .join(' · '));
              }
              if (hasActiveOrders) {
                snippetParts.add('Active orders: $activeOrders');
              }
              snippetParts.add(timestampText);

              // Format rider ID for display (truncate if long)
              final String displayId = riderId.length > 8
                  ? '${riderId.substring(0, 8)}...'
                  : riderId;

              BitmapDescriptor markerIcon;
              if (isMoving) {
                markerIcon = BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                );
              } else if (isIdle) {
                markerIcon = BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueYellow,
                );
              } else {
                markerIcon = BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                );
              }

              newMarkers.add(
                Marker(
                  markerId: MarkerId(riderId),
                  position: LatLng(lat, lng),
                  infoWindow: InfoWindow(
                    title: fullName.isEmpty
                        ? 'Rider (ID: $displayId)'
                        : '$fullName (ID: $displayId)',
                    snippet: snippetParts.isEmpty
                        ? 'Rider ID: $displayId'
                        : snippetParts.join('\n'),
                  ),
                  icon: markerIcon,
                  rotation: (data['rotation'] is num)
                      ? (data['rotation'] as num).toDouble()
                      : 0.0,
                ),
              );
            }
          } catch (e, st) {
            _lastErrorMessage = 'Marker build failed for ${doc.id}: $e';
            debugPrint('[DriversMap] $e\n$st');
          }
        }

        if (mounted) {
          setState(() {
            _markers
              ..clear()
              ..addAll(newMarkers);
            _activeRiders = activeRiders;
            _lastSnapshotCount = activeCount;
          });
          // Only auto-fit camera once on initial load
          if (!_hasFittedCamera && _mapReady) {
            _fitMapToMarkers();
            _hasFittedCamera = true;
          }
        }
      },
      onError: (Object error, StackTrace st) {
        _lastErrorMessage = 'Firestore stream error: $error';
        debugPrint('[DriversMap] Firestore error: $error\n$st');
        if (mounted) setState(() {});
      },
      cancelOnError: false,
    );
  }

  Widget _buildGoogleMap() {
    return Builder(
      builder: (context) {
        // Use ErrorWidget.builder to catch build-time errors
        final originalErrorBuilder = ErrorWidget.builder;
        ErrorWidget.builder = (FlutterErrorDetails details) {
          // Check if it's a Google Maps related error
          final errorStr = details.exception.toString();
          if (errorStr.contains('MapTypeId') ||
              errorStr.contains('google.maps') ||
              errorStr.contains('undefined')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _mapError = true;
                  _lastErrorMessage = 'Google Maps API error';
                });
              }
            });
            return Center(
              child: Text(
                'Map loading...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            );
          }
          // Use original error builder for other errors
          return originalErrorBuilder(details);
        };

        try {
          return GoogleMap(
            initialCameraPosition: _initialCamera,
            markers: _markers,
            circles: _showCapacityOverlay
                ? _capacityCircles
                : <Circle>{},
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            trafficEnabled: false,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              // Restore original error builder
              ErrorWidget.builder = originalErrorBuilder;

              try {
                _mapReady = true;
                if (!_mapControllerCompleter.isCompleted) {
                  _mapControllerCompleter.complete(controller);
                }
                setState(() {});
                // Fit bounds once after map creation
                if (!_hasFittedCamera) {
                  _fitMapToMarkers();
                  _hasFittedCamera = true;
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _mapError = true;
                    _lastErrorMessage = 'Map creation error: $e';
                  });
                }
              }
            },
          );
        } finally {
          // Restore original error builder if map creation fails
          ErrorWidget.builder = originalErrorBuilder;
        }
      },
    );
  }

  Future<void> _fitMapToMarkers() async {
    if (!_mapControllerCompleter.isCompleted || !mounted) return;
    try {
      final controller = await _mapControllerCompleter.future;
      if (_markers.isEmpty) return;
      if (_markers.length == 1) {
        final marker = _markers.first;
        await controller.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: marker.position, zoom: 15),
          ),
        );
        return;
      }

      double minLat = _markers.first.position.latitude;
      double maxLat = _markers.first.position.latitude;
      double minLng = _markers.first.position.longitude;
      double maxLng = _markers.first.position.longitude;
      for (final m in _markers) {
        final lat = m.position.latitude;
        final lng = m.position.longitude;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      await controller.moveCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e, st) {
      _lastErrorMessage = 'Auto-zoom failed: $e';
      debugPrint('[DriversMap] auto-zoom error: $e\n$st');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show empty state if no active riders and stream has loaded
    if (_streamLoaded && _markers.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Active Riders Live Map'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_off,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No active riders online',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'There are currently no riders checked in today.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showActiveRidersDialog(context),
          icon: const Icon(Icons.list),
          label: const Text('Active riders'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Riders Live Map'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    Navigator.of(context).maybePop(),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(
              _showCapacityOverlay
                  ? Icons.layers
                  : Icons.layers_outlined,
              color: _showCapacityOverlay
                  ? Colors.orange
                  : Colors.white,
            ),
            tooltip: 'Zone Capacity',
            onPressed: _toggleCapacityOverlay,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showActiveRidersDialog(context),
        icon: const Icon(Icons.list),
        label: const Text('Active riders'),
      ),
      body: _mapError
          ? Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Map Initialization Error',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Unable to load Google Maps. Please check your configuration or try again later.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _mapError = false;
                            _mapReady = false;
                            _hasFittedCamera = false;
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                _buildGoogleMap(),
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: Card(
                    color: Colors.black.withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DefaultTextStyle(
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Map ready: ${_mapReady ? 'yes' : 'no'}'),
                            Text('Active riders: $_lastSnapshotCount'),
                            Text('Markers: ${_markers.length}'),
                            if (_lastErrorMessage != null)
                              Text('Error: $_lastErrorMessage',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
