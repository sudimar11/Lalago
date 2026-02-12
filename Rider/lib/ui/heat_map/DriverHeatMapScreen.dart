import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/constants.dart';

class DriverHeatMapScreen extends StatefulWidget {
  const DriverHeatMapScreen({Key? key}) : super(key: key);

  @override
  State<DriverHeatMapScreen> createState() => _DriverHeatMapScreenState();
}

class _DriverHeatMapScreenState extends State<DriverHeatMapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showHeatMap = true;
  Set<Circle> _heatMapCircles = {};
  bool _dataLoaded = false; // Cache flag - load only once per screen open

  @override
  void initState() {
    super.initState();
    developer.log('🗺️ DriverHeatMapScreen: initState called',
        name: 'DriverHeatMapScreen');
    _getCurrentLocation();
  }

  /// Fallback center when location plugin is unavailable (e.g. emulator).
  static const LatLng _fallbackCenter = LatLng(0.0, 0.0);

  Future<void> _getCurrentLocation() async {
    try {
      developer.log('🗺️ Getting current location...',
          name: 'DriverHeatMapScreen');
      final position = await getCurrentLocation()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Location request timed out');
      });
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(
            position.latitude,
            position.longitude,
          );
          _errorMessage = null;
          _isLoading = false;
        });
        developer.log(
            '🗺️ Location obtained: ${position.latitude}, ${position.longitude}',
            name: 'DriverHeatMapScreen');
        _loadHeatMapData();
      }
    } catch (e) {
      developer.log('🗺️ Error getting location: $e',
          name: 'DriverHeatMapScreen', error: e);
      if (mounted) {
        setState(() {
          _currentLocation = _fallbackCenter;
          _errorMessage = 'Location unavailable. Showing hotspot zones.';
          _isLoading = false;
        });
        _loadHeatMapData();
      }
    }
  }

  Future<void> _loadHeatMapData() async {
    // Load data only once per screen open (cached)
    if (_dataLoaded) {
      return;
    }

    developer.log('🗺️ _loadHeatMapData: Loading heat map data',
        name: 'DriverHeatMapScreen');

    try {
      // Get today's date range
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startOfTomorrow = startOfDay.add(const Duration(days: 1));

      // Query today's orders from restaurant_orders collection
      final querySnapshot = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(startOfTomorrow))
          .get();

      developer.log(
          '🗺️ Today\'s orders query: Found ${querySnapshot.docs.length} orders',
          name: 'DriverHeatMapScreen');

      // Group orders by restaurant (vendorID) and count
      final restaurantOrderCount = <String, int>{};
      final restaurantData = <String, Map<String, dynamic>>{};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final vendorID = data['vendorID'] as String?;
        final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;

        if (vendorID == null || vendorID.isEmpty) {
          developer.log(
              '🗺️ Skipping invalid doc: $vendorID (missing lat/lng/weight)',
              name: 'DriverHeatMapScreen');
          continue;
        }

        // Count orders per restaurant
        restaurantOrderCount[vendorID] =
            (restaurantOrderCount[vendorID] ?? 0) + 1;

        // Store restaurant location data (use first occurrence)
        if (!restaurantData.containsKey(vendorID)) {
          final lat = vendor['latitude'];
          final lng = vendor['longitude'];

          if (lat != null && lng != null) {
            restaurantData[vendorID] = {
              'latitude': lat,
              'longitude': lng,
              'title': vendor['title'] ?? 'Restaurant',
            };
          }
        }
      }

      developer.log(
          '🗺️ Found ${restaurantOrderCount.length} restaurants with orders today',
          name: 'DriverHeatMapScreen');

      // Sort restaurants by order count (descending) and get top 10
      final sortedRestaurants = restaurantOrderCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topRestaurants = sortedRestaurants.take(10).toList();

      developer.log(
          '🗺️ Top restaurants: ${topRestaurants.map((e) => '${e.key}: ${e.value} orders').join(', ')}',
          name: 'DriverHeatMapScreen');

      // Create circles for top restaurants
      final circles = <Circle>{};
      int circleIdCounter = 0;

      // Find max order count for normalization
      final maxOrderCount =
          topRestaurants.isNotEmpty ? topRestaurants.first.value : 1;

      for (var restaurantEntry in topRestaurants) {
        final vendorID = restaurantEntry.key;
        final orderCount = restaurantEntry.value;
        final restaurant = restaurantData[vendorID];

        if (restaurant == null) {
          developer.log(
              '🗺️ Skipping restaurant $vendorID: missing location data',
              name: 'DriverHeatMapScreen');
          continue;
        }

        final lat = restaurant['latitude'];
        final lng = restaurant['longitude'];

        // Convert to double
        final latDouble = (lat is double)
            ? lat
            : (lat is num)
                ? lat.toDouble()
                : double.tryParse(lat.toString()) ?? 0.0;
        final lngDouble = (lng is double)
            ? lng
            : (lng is num)
                ? lng.toDouble()
                : double.tryParse(lng.toString()) ?? 0.0;

        // Skip if coordinates are 0,0 (invalid)
        if (latDouble == 0.0 && lngDouble == 0.0) {
          developer.log('��️ Skipping doc with 0,0 coordinates: $vendorID',
              name: 'DriverHeatMapScreen');
          continue;
        }

        // Validate coordinate ranges (lat: -90 to 90, lng: -180 to 180)
        if (latDouble < -90 ||
            latDouble > 90 ||
            lngDouble < -180 ||
            lngDouble > 180) {
          developer.log(
              '🗺️ Skipping restaurant $vendorID: invalid coordinate ranges (lat=$latDouble, lng=$lngDouble)',
              name: 'DriverHeatMapScreen');
          continue;
        }

        // Normalize order count to weight 1-5
        // More orders = higher weight
        final normalizedWeight = maxOrderCount > 0
            ? ((orderCount / maxOrderCount) * 4 + 1).round().clamp(1, 5)
            : 1;

        // Create circle based on order count
        final circle = Circle(
          circleId: CircleId('restaurant_${circleIdCounter++}'),
          center: LatLng(latDouble, lngDouble),
          radius: _getRadiusForWeight(normalizedWeight),
          fillColor: _getColorForWeight(normalizedWeight).withOpacity(0.4),
          strokeColor: _getColorForWeight(normalizedWeight).withOpacity(0.6),
          strokeWidth: 2,
        );

        circles.add(circle);
        developer.log(
            '🗺️ Created circle for restaurant $vendorID: lat=$latDouble, lng=$lngDouble, orders=$orderCount, weight=$normalizedWeight',
            name: 'DriverHeatMapScreen');
      }

      if (mounted) {
        setState(() {
          _heatMapCircles = circles;
          _dataLoaded = true; // Mark as loaded (cached)
        });

        // Log all circle coordinates for debugging
        developer.log(
            '🗺️ Heat zones loaded: ${circles.length} circles created, _showHeatMap=$_showHeatMap',
            name: 'DriverHeatMapScreen');

        if (circles.isNotEmpty && _currentLocation != null) {
          developer.log(
              '🗺️ Driver location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
              name: 'DriverHeatMapScreen');

          circles.forEach((circle) {
            final distance = _calculateDistance(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              circle.center.latitude,
              circle.center.longitude,
            );
            developer.log(
                '🗺️ Circle at ${circle.center.latitude}, ${circle.center.longitude} - Distance: ${(distance / 1000).toStringAsFixed(2)} km',
                name: 'DriverHeatMapScreen');
          });

          // Adjust map camera to show all circles if they exist
          _adjustMapToShowAllCircles();
        }
      }
    } catch (e) {
      // Handle failures gracefully - don't affect delivery workflows
      developer.log('Error loading heat map data: $e',
          name: 'DriverHeatMapScreen',
          error: e,
          stackTrace: StackTrace.current);
      if (mounted) {
        setState(() {
          _dataLoaded = true; // Mark as loaded even on error to prevent retry
          // Keep existing circles if any, or empty set
        });
      }
    }
  }

  double _getRadiusForWeight(int weight) {
    // Weight 1-5 maps to radius 200-500 meters
    switch (weight) {
      case 1:
        return 200;
      case 2:
        return 250;
      case 3:
        return 300;
      case 4:
        return 400;
      case 5:
        return 500;
      default:
        return 200;
    }
  }

  Color _getColorForWeight(int weight) {
    // Static heat map: red=high, orange=medium, green=low
    switch (weight) {
      case 1:
      case 2:
        return Colors.green; // Low
      case 3:
      case 4:
        return Colors.orange; // Medium
      case 5:
        return Colors.red; // High
      default:
        return Colors.green;
    }
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Adjust map camera to show both driver location and all circles
  Future<void> _adjustMapToShowAllCircles() async {
    if (_mapController == null || _heatMapCircles.isEmpty) {
      return;
    }

    try {
      final center = _currentLocation ?? _fallbackCenter;
      final points = <LatLng>[center];
      for (var circle in _heatMapCircles) {
        points.add(circle.center);
      }

      // Calculate bounds
      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (var point in points) {
        minLat = minLat < point.latitude ? minLat : point.latitude;
        maxLat = maxLat > point.latitude ? maxLat : point.latitude;
        minLng = minLng < point.longitude ? minLng : point.longitude;
        maxLng = maxLng > point.longitude ? maxLng : point.longitude;
      }

      // Add padding
      final latPadding = (maxLat - minLat) * 0.1;
      final lngPadding = (maxLng - minLng) * 0.1;

      final bounds = LatLngBounds(
        southwest: LatLng(minLat - latPadding, minLng - lngPadding),
        northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
      );

      // Calculate zoom level based on bounds
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      double zoom = 12.0; // Default zoom

      if (latDiff > 0 && lngDiff > 0) {
        // Calculate appropriate zoom based on the larger dimension
        final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
        if (maxDiff > 10) {
          zoom = 5.0; // Very wide area
        } else if (maxDiff > 5) {
          zoom = 7.0;
        } else if (maxDiff > 1) {
          zoom = 9.0;
        } else if (maxDiff > 0.5) {
          zoom = 11.0;
        } else {
          zoom = 13.0;
        }
      }

      // Move camera to show all points
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );

      developer.log(
          '🗺️ Map adjusted: bounds=($minLat,$minLng) to ($maxLat,$maxLng), zoom=$zoom',
          name: 'DriverHeatMapScreen');
    } catch (e) {
      developer.log('🗺️ Error adjusting map: $e',
          name: 'DriverHeatMapScreen', error: e);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final center = _currentLocation ?? _fallbackCenter;

    if (_currentLocation == null && _heatMapCircles.isEmpty) {
      return const Center(
        child: Text(
          'Location not available',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    developer.log('🗺️ Build: _showHeatMap=$_showHeatMap',
        name: 'DriverHeatMapScreen');

    final topOffset = _errorMessage != null ? 56.0 : 0.0;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: center,
            zoom: 14,
          ),
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            if (_heatMapCircles.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _adjustMapToShowAllCircles();
              });
            }
          },
          myLocationEnabled: _currentLocation != null,
          myLocationButtonEnabled: _currentLocation != null,
          mapType: MapType.normal,
          circles: _showHeatMap ? _heatMapCircles : {},
        ),
        if (_errorMessage != null)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_off, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          top: 16 + topOffset,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'Hotspots based on today\'s order activity',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ),
        Positioned(
          top: 80 + topOffset,
          left: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SwitchListTile.adaptive(
              activeColor: Color(COLOR_ACCENT),
              title: const Text(
                'Show Heat Map',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              value: _showHeatMap,
              onChanged: (bool value) {
                developer.log(
                    '🗺️ Toggle tapped! Changing from $_showHeatMap to $value',
                    name: 'DriverHeatMapScreen');
                setState(() {
                  _showHeatMap = value;
                  developer.log('🗺️ Updated _showHeatMap to: $_showHeatMap',
                      name: 'DriverHeatMapScreen');
                });
              },
            ),
          ),
        ),
        Positioned(
          top: 140 + topOffset,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.yellow.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Debug: Circles=${_heatMapCircles.length}, ShowMap=$_showHeatMap, DataLoaded=$_dataLoaded',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                if (_currentLocation != null && _heatMapCircles.isNotEmpty)
                  Text(
                    'Driver: ${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                if (_heatMapCircles.isNotEmpty)
                  Text(
                    'First circle: ${_heatMapCircles.first.center.latitude.toStringAsFixed(4)}, ${_heatMapCircles.first.center.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
        // Button to zoom out and show all circles
        if (_heatMapCircles.isNotEmpty)
          Positioned(
            top: 200 + topOffset,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _adjustMapToShowAllCircles,
              backgroundColor: Colors.white,
              child: const Icon(Icons.fit_screen, color: Colors.black87),
              tooltip: 'Show all hotspots',
            ),
          ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.shade200,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hotspots are suggestions only and do not guarantee orders.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
