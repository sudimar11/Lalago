import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/rider_preset_location_service.dart';

class ZoneBrowserScreen extends StatefulWidget {
  const ZoneBrowserScreen({Key? key}) : super(key: key);

  @override
  State<ZoneBrowserScreen> createState() => _ZoneBrowserScreenState();
}

class _ZoneBrowserScreenState extends State<ZoneBrowserScreen> {
  GoogleMapController? _mapController;
  final ScrollController _listController = ScrollController();

  List<RiderPresetLocationData> _zones = [];
  bool _isLoading = true;
  int _selectedIndex = -1;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _loadZones() async {
    try {
      final zones =
          await RiderPresetLocationService.getPresetLocations();
      if (!mounted) return;

      final currentId =
          MyAppState.currentUser?.selectedPresetLocationId;
      int preselected = -1;
      if (currentId != null && currentId.trim().isNotEmpty) {
        preselected = zones.indexWhere((z) => z.id == currentId);
      }

      setState(() {
        _zones = zones;
        _selectedIndex = preselected;
        _isLoading = false;
      });

      if (_mapController != null && zones.isNotEmpty) {
        _fitAllZones();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load zones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _fitAllZones() {
    if (_zones.isEmpty || _mapController == null) return;

    double minLat = _zones.first.latitude;
    double maxLat = _zones.first.latitude;
    double minLng = _zones.first.longitude;
    double maxLng = _zones.first.longitude;

    for (final z in _zones) {
      if (z.latitude < minLat) minLat = z.latitude;
      if (z.latitude > maxLat) maxLat = z.latitude;
      if (z.longitude < minLng) minLng = z.longitude;
      if (z.longitude > maxLng) maxLng = z.longitude;
    }

    final latPad = (maxLat - minLat) * 0.15 + 0.005;
    final lngPad = (maxLng - minLng) * 0.15 + 0.005;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            minLat - latPad,
            minLng - lngPad,
          ),
          northeast: LatLng(
            maxLat + latPad,
            maxLng + lngPad,
          ),
        ),
        48.0,
      ),
    );
  }

  void _selectZone(int index) {
    if (index < 0 || index >= _zones.length) return;
    setState(() => _selectedIndex = index);

    final zone = _zones[index];
    final zoom = zone.hasRadius
        ? _zoomForRadius(zone.radiusKm!)
        : 14.0;

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(zone.latitude, zone.longitude),
          zoom: zoom,
        ),
      ),
    );

    final itemHeight = 56.0;
    final offset = (index * itemHeight).clamp(
      0.0,
      _listController.position.maxScrollExtent,
    );
    _listController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Set<Circle> _buildCircles() {
    final circles = <Circle>{};
    for (var i = 0; i < _zones.length; i++) {
      final z = _zones[i];
      if (!z.hasRadius) continue;
      final isSelected = i == _selectedIndex;
      circles.add(
        Circle(
          circleId: CircleId('zone_${z.id}'),
          center: LatLng(z.latitude, z.longitude),
          radius: z.radiusKm! * 1000,
          fillColor: Colors.blue.withOpacity(
            isSelected ? 0.15 : 0.08,
          ),
          strokeColor: Colors.blue.withOpacity(
            isSelected ? 0.8 : 0.4,
          ),
          strokeWidth: isSelected ? 4 : 2,
          consumeTapEvents: true,
          onTap: () => _selectZone(i),
        ),
      );
    }
    return circles;
  }

  Future<void> _confirmSelection() async {
    if (_selectedIndex < 0 || _selectedIndex >= _zones.length) {
      return;
    }
    if (_isSaving) return;

    setState(() => _isSaving = true);
    final zone = _zones[_selectedIndex];

    try {
      final oldZoneId =
          MyAppState.currentUser!.selectedPresetLocationId;

      MyAppState.currentUser!.location = UserLocation(
        latitude: zone.latitude,
        longitude: zone.longitude,
      );
      MyAppState.currentUser!.locationUpdatedAt =
          Timestamp.now();
      MyAppState.currentUser!.selectedPresetLocationId =
          zone.id;
      await FireStoreUtils.updateCurrentUser(
        MyAppState.currentUser!,
      );

      await FirebaseFirestore.instance
          .collection('service_areas')
          .doc(zone.id)
          .update({
        'assignedDriverIds': FieldValue.arrayUnion(
          [MyAppState.currentUser!.userID],
        ),
      });

      if (oldZoneId != null &&
          oldZoneId.isNotEmpty &&
          oldZoneId != zone.id) {
        await FirebaseFirestore.instance
            .collection('service_areas')
            .doc(oldZoneId)
            .update({
          'assignedDriverIds': FieldValue.arrayRemove(
            [MyAppState.currentUser!.userID],
          ),
        });
      }

      if (mounted) {
        Navigator.pop(context, zone);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Work Area'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator.adaptive(),
            )
          : _zones.isEmpty
              ? const Center(
                  child: Text(
                    'No zones available.\nContact admin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      flex: 45,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _zones.first.latitude,
                            _zones.first.longitude,
                          ),
                          zoom: 12,
                        ),
                        onMapCreated: (controller) {
                          _mapController = controller;
                          Future.delayed(
                            const Duration(
                              milliseconds: 400,
                            ),
                            () => _fitAllZones(),
                          );
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        circles: _buildCircles(),
                      ),
                    ),
                    Expanded(
                      flex: 45,
                      child: ListView.builder(
                        controller: _listController,
                        itemCount: _zones.length,
                        itemBuilder: (_, i) {
                          final z = _zones[i];
                          final isSelected =
                              i == _selectedIndex;
                          return ListTile(
                            leading: Icon(
                              Icons.place,
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            title: Text(
                              z.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedTileColor: Colors.blue
                                .withOpacity(0.08),
                            onTap: () => _selectZone(i),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed:
                                _selectedIndex >= 0 &&
                                        !_isSaving
                                    ? _confirmSelection
                                    : null,
                            style:
                                ElevatedButton.styleFrom(
                              backgroundColor:
                                  Color(COLOR_PRIMARY),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child:
                                        CircularProgressIndicator
                                            .adaptive(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'CONFIRM SELECTION',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
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

double _zoomForRadius(double radiusKm) {
  if (radiusKm <= 0) return 14.0;
  final diameter = radiusKm * 2;
  final zoom = 14.0 - (math.log(diameter) / math.ln2);
  return zoom.clamp(8.0, 17.0);
}
