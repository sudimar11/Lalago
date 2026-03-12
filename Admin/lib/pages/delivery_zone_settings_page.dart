import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:brgy/constants.dart';
import 'package:brgy/models/service_area.dart';
import 'package:brgy/models/driver.dart';
import 'package:brgy/services/delivery_zone_service.dart';
import 'package:brgy/services/driver_service.dart';

Future<BitmapDescriptor>? _cachedOrangeMarker;

/// Creates an orange marker icon (works on web; defaultMarkerWithHue does not).
Future<BitmapDescriptor> _createOrangeMarkerIcon() async {
  _cachedOrangeMarker ??= _createOrangeMarkerIconImpl();
  return _cachedOrangeMarker!;
}

Future<BitmapDescriptor> _createOrangeMarkerIconImpl() async {
  const size = 42.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(21, 21);
  const radius = 19.0;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
}

class DeliveryZoneSettingsPage extends StatelessWidget {
  const DeliveryZoneSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Zone Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<ServiceArea>>(
        stream: DeliveryZoneService().streamServiceAreas(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final areas = snapshot.data ?? [];
          if (areas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No service areas yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a service area',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: areas.length,
            itemBuilder: (context, i) {
              final a = areas[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      a.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${a.boundaryType == "radius" ? "Radius ${a.radiusKm?.toStringAsFixed(0) ?? "?"} km" : "Fixed"} • '
                        '${a.barangays.length} barangays • '
                        '${a.assignedDriverIds.length} riders'
                        '${a.maxRiders != null ? " • Cap: ${a.maxRiders}" : ""}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEditArea(context, a),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditArea(context, null),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openEditArea(BuildContext context, ServiceArea? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ServiceAreaEditPage(initial: existing),
      ),
    );
  }
}

class _ServiceAreaEditPage extends StatefulWidget {
  final ServiceArea? initial;

  const _ServiceAreaEditPage({this.initial});

  @override
  State<_ServiceAreaEditPage> createState() => _ServiceAreaEditPageState();
}

class _ServiceAreaEditPageState extends State<_ServiceAreaEditPage> {
  final _nameCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _maxRidersCtrl = TextEditingController();
  final _mapControllerCompleter = Completer<GoogleMapController>();

  bool _searching = false;
  String? _searchError;
  final _service = DeliveryZoneService();
  final _driverService = DriverService();

  late List<String> _barangays;
  late String _boundaryType;
  double? _radiusKm;
  double? _centerLat;
  double? _centerLng;
  late Set<String> _selectedDriverIds;
  bool _saving = false;

  static const _radiusOptions = [
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
    10.0,
    15.0,
    20.0,
  ];
  static const _defaultCenter = LatLng(14.5995, 120.9842); // Manila

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _nameCtrl.text = a?.name ?? '';
    _barangays = List.from(a?.barangays ?? []);
    _boundaryType = a?.boundaryType ?? 'fixed';
    _radiusKm = a?.radiusKm ?? 5.0;
    _centerLat = a?.centerLat;
    _centerLng = a?.centerLng;
    _selectedDriverIds = Set.from(a?.assignedDriverIds ?? []);
    if (a?.maxRiders != null) {
      _maxRidersCtrl.text = a!.maxRiders.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barangayCtrl.dispose();
    _searchCtrl.dispose();
    _maxRidersCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchPlace() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(query)}&key=$GOOGLE_API_KEY',
      );
      final response = await http.get(url);
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _searching = false;
          _searchError = 'Search failed (${response.statusCode})';
        });
        return;
      }
      final data = json.decode(response.body) as Map<String, dynamic>?;
      final status = data?['status'] as String?;
      if (status == 'ZERO_RESULTS' || status == 'REQUEST_DENIED') {
        setState(() {
          _searching = false;
          _searchError = status == 'REQUEST_DENIED'
              ? 'Geocoding API not enabled or invalid key'
              : 'No results for "$query"';
        });
        return;
      }
      if (status != 'OK') {
        setState(() {
          _searching = false;
          _searchError = 'Search failed: ${status ?? "unknown"}';
        });
        return;
      }
      final results = data?['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        setState(() {
          _searching = false;
          _searchError = 'No results for "$query"';
        });
        return;
      }
      final geometry = results.first['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        setState(() {
          _searching = false;
          _searchError = 'Invalid response from geocoding';
        });
        return;
      }
      final pos = LatLng(lat, lng);
      setState(() {
        _centerLat = lat;
        _centerLng = lng;
        _searching = false;
        _searchError = null;
      });
      if (_mapControllerCompleter.isCompleted) {
        final controller = await _mapControllerCompleter.future;
        await controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 14));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = 'Search failed: ${e.toString()}';
        });
      }
    }
  }

  void _onMapTap(LatLng pos) async {
    setState(() {
      _centerLat = pos.latitude;
      _centerLng = pos.longitude;
      _searchError = null;
    });
    final controller = await _mapControllerCompleter.future;
    await controller.animateCamera(CameraUpdate.newLatLng(pos));
  }

  void _addBarangay() {
    final t = _barangayCtrl.text.trim();
    if (t.isEmpty) return;
    if (_barangays.contains(t)) return;
    setState(() {
      _barangays.add(t);
      _barangayCtrl.clear();
    });
  }

  void _showAddBarangayDialog(BuildContext context) {
    _barangayCtrl.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add barangay'),
        content: TextField(
          controller: _barangayCtrl,
          decoration: InputDecoration(
            hintText: 'Enter barangay or district name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onSubmitted: (_) {
            _addBarangay();
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _addBarangay();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeBarangay(String b) {
    setState(() => _barangays.remove(b));
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter area name')),
      );
      return;
    }
    if (_boundaryType == 'radius') {
      if (_centerLat == null || _centerLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap on map to pin center')),
        );
        return;
      }
    }
    final maxRidersText = _maxRidersCtrl.text.trim();
    int? parsedMaxRiders;
    if (maxRidersText.isNotEmpty) {
      parsedMaxRiders = int.tryParse(maxRidersText);
      if (parsedMaxRiders == null || parsedMaxRiders <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Max riders must be a positive number',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final area = ServiceArea(
        id: widget.initial?.id ?? '',
        name: name,
        barangays: _barangays,
        boundaryType: _boundaryType,
        centerLat: _boundaryType == 'radius' ? _centerLat : null,
        centerLng: _boundaryType == 'radius' ? _centerLng : null,
        radiusKm: _boundaryType == 'radius' ? _radiusKm : null,
        assignedDriverIds: _selectedDriverIds.toList(),
        createdAt: widget.initial?.createdAt,
        updatedAt: null,
        order: widget.initial?.order ?? 0,
        maxRiders: parsedMaxRiders,
      );
      if (widget.initial != null) {
        await _service.update(widget.initial!.id, area);
      } else {
        await _service.create(area);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.initial != null
                ? 'Service area updated'
                : 'Service area created'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete service area?'),
        content: Text(
          'Delete "${widget.initial!.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.delete(widget.initial!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service area deleted'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial != null ? 'Edit service area' : 'Add area'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (widget.initial != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(
              icon: Icons.badge_outlined,
              title: 'Basic info',
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Area name',
                    hintText: 'e.g. North District, Jolo',
                    filled: true,
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.map_outlined,
              title: 'Barangays / districts',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._barangays.map(
                      (b) => Chip(
                        label: Text(b),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _removeBarangay(b),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    InputChip(
                      label: const Text('Add barangay'),
                      avatar: const Icon(Icons.add, size: 18, color: Colors.orange),
                      onPressed: () => _showAddBarangayDialog(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.settings_ethernet_outlined,
              title: 'Boundary',
              children: [
                DropdownButtonFormField<String>(
                  value: _boundaryType,
                  decoration: InputDecoration(
                    filled: true,
                    prefixIcon: Icon(
                      _boundaryType == 'radius'
                          ? Icons.radar
                          : Icons.list_alt_outlined,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text('Fixed (barangay list only)'),
                    ),
                    DropdownMenuItem(
                      value: 'radius',
                      child: Text('Radius (center + km)'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _boundaryType = v ?? 'fixed'),
                ),
                if (_boundaryType == 'radius') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search place or address',
                            filled: true,
                            prefixIcon: const Icon(Icons.search),
                            errorText: _searchError,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchPlace(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _searching ? null : _searchPlace,
                        icon: _searching
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search, size: 20),
                        label: Text(_searching ? '...' : 'Search'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap on map to pin center',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 480,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder<BitmapDescriptor>(
                        future: _createOrangeMarkerIcon(),
                        builder: (context, iconSnap) {
                          final orangeIcon = iconSnap.data;
                          return StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('vendors')
                                .snapshots(),
                            builder: (context, vendorsSnap) {
                              return StreamBuilder<List<ServiceArea>>(
                                stream: _service.streamServiceAreas(),
                                builder: (context, areasSnap) {
                                  final allMarkers = <Marker>{};
                                  final allCircles = <Circle>{};

                                  if (_centerLat != null && _centerLng != null) {
                                    allMarkers.add(
                                      Marker(
                                        markerId: const MarkerId('center'),
                                        position: LatLng(
                                          _centerLat!,
                                          _centerLng!,
                                        ),
                                        infoWindow: InfoWindow(
                                          title: 'Center',
                                          snippet:
                                              '${_centerLat!.toStringAsFixed(5)}, '
                                              '${_centerLng!.toStringAsFixed(5)}',
                                        ),
                                      ),
                                    );
                                  }

                                  final showExistingAreas = widget.initial == null;
                                  if (showExistingAreas) {
                                    final existingAreas = areasSnap.data ?? [];
                                    for (final area in existingAreas) {
                                      if (area.boundaryType != 'radius') {
                                        continue;
                                      }
                                      final lat = area.centerLat;
                                      final lng = area.centerLng;
                                      final radiusKm = area.radiusKm;
                                      if (lat == null ||
                                          lng == null ||
                                          radiusKm == null) {
                                        continue;
                                      }

                                      allMarkers.add(
                                        Marker(
                                          markerId: MarkerId(
                                            'existing_area_${area.id}',
                                          ),
                                          position: LatLng(lat, lng),
                                          icon:
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueAzure,
                                              ),
                                          infoWindow: InfoWindow(
                                            title: area.name,
                                            snippet:
                                                'Existing area • ${radiusKm % 1 == 0 ? radiusKm.toStringAsFixed(0) : radiusKm.toStringAsFixed(1)} km',
                                          ),
                                        ),
                                      );

                                      allCircles.add(
                                        Circle(
                                          circleId: CircleId(
                                            'existing_radius_${area.id}',
                                          ),
                                          center: LatLng(lat, lng),
                                          radius: radiusKm * 1000,
                                          fillColor: Colors.blue.withValues(
                                            alpha: 0.08,
                                          ),
                                          strokeColor: Colors.blue,
                                          strokeWidth: 1,
                                        ),
                                      );
                                    }
                                  }

                                  final vendors = vendorsSnap.data?.docs ?? [];
                                  for (final doc in vendors) {
                                    final d =
                                        doc.data() as Map<String, dynamic>?;
                                    if (d == null) continue;
                                    double? lat = _asDouble(d['latitude']);
                                    double? lng = _asDouble(d['longitude']);
                                    if (lat == null || lng == null) {
                                      final coords = d['coordinates'];
                                      if (coords is GeoPoint) {
                                        lat = coords.latitude;
                                        lng = coords.longitude;
                                      }
                                    }
                                    if (lat != null &&
                                        lng != null &&
                                        (lat != 0 || lng != 0)) {
                                      final title = (d['title'] ??
                                              d['authorName'] ??
                                              'Restaurant')
                                          .toString();
                                      allMarkers.add(
                                        Marker(
                                          markerId: MarkerId('rest_${doc.id}'),
                                          position: LatLng(lat, lng),
                                          icon: orangeIcon ??
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueOrange,
                                              ),
                                          infoWindow: InfoWindow(
                                            title:
                                                title.isEmpty ? 'Restaurant' : title,
                                          ),
                                        ),
                                      );
                                    }
                                  }

                                  if (_centerLat != null &&
                                      _centerLng != null &&
                                      _radiusKm != null) {
                                    allCircles.add(
                                      Circle(
                                        circleId: const CircleId('radius'),
                                        center: LatLng(
                                          _centerLat!,
                                          _centerLng!,
                                        ),
                                        radius: (_radiusKm ?? 5) * 1000,
                                        fillColor: Colors.orange.withValues(
                                          alpha: 0.2,
                                        ),
                                        strokeColor: Colors.orange,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  }

                                  return GoogleMap(
                                    initialCameraPosition: CameraPosition(
                                      target:
                                          _centerLat != null && _centerLng != null
                                              ? LatLng(_centerLat!, _centerLng!)
                                              : _defaultCenter,
                                      zoom:
                                          _centerLat != null && _centerLng != null
                                              ? 14
                                              : 10,
                                    ),
                                    onTap: _onMapTap,
                                    onMapCreated: (c) =>
                                        _mapControllerCompleter.complete(c),
                                    markers: allMarkers,
                                    circles: allCircles,
                                    zoomControlsEnabled: true,
                                    myLocationEnabled: false,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Radius (km)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _radiusOptions.map((r) {
                      final sel = (_radiusKm ?? 5) == r;
                      return FilterChip(
                        label: Text(
                          r % 1 == 0 ? '${r.toInt()} km' : '$r km',
                        ),
                        selected: sel,
                        onSelected: (_) => setState(() => _radiusKm = r),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        selectedColor: Colors.orange.withValues(alpha: 0.2),
                        checkmarkColor: Colors.orange,
                        showCheckmark: true,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.groups_outlined,
              title: 'Rider Capacity',
              children: [
                TextField(
                  controller: _maxRidersCtrl,
                  decoration: InputDecoration(
                    labelText: 'Maximum Riders',
                    hintText: 'Leave empty for unlimited',
                    filled: true,
                    prefixIcon: const Icon(
                      Icons.people_outline,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
                if (widget.initial != null &&
                    widget.initial!
                        .assignedDriverIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection(USERS)
                        .where(
                          'role',
                          isEqualTo: USER_ROLE_DRIVER,
                        )
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const SizedBox.shrink();
                      }
                      final ids =
                          widget.initial!.assignedDriverIds;
                      final fiveMinAgo = DateTime.now().subtract(
                        const Duration(minutes: 5),
                      );
                      int active = 0;
                      for (final doc in snap.data!.docs) {
                        if (!ids.contains(doc.id)) continue;
                        final d = doc.data()
                            as Map<String, dynamic>;
                        if (d['checkedOutToday'] == true) {
                          continue;
                        }
                        final ts =
                            d['locationUpdatedAt'] as Timestamp?;
                        if (ts != null &&
                            ts.toDate().isAfter(fiveMinAgo)) {
                          active++;
                        }
                      }
                      final max = widget.initial!.maxRiders;
                      final label = max != null
                          ? '$active / $max active now'
                          : '$active active now (unlimited)';
                      final isOver =
                          max != null && active >= max;
                      return Row(
                        children: [
                          Icon(
                            isOver
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                            size: 18,
                            color: isOver
                                ? Colors.red
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isOver
                                  ? Colors.red
                                  : Colors.grey[600],
                              fontWeight: isOver
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.directions_bike_outlined,
              title: 'Assign riders',
              children: [
                StreamBuilder<List<Driver>>(
              stream: _driverService.streamDrivers(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final drivers = snap.data!..sort((a, b) => a.name.compareTo(b.name));
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: drivers.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (_, i) {
                      final d = drivers[i];
                      final sel = _selectedDriverIds.contains(d.id);
                      return CheckboxListTile(
                        value: sel,
                        onChanged: (_) {
                          setState(() {
                            if (sel) {
                              _selectedDriverIds.remove(d.id);
                            } else {
                              _selectedDriverIds.add(d.id);
                            }
                          });
                        },
                        title: Text(d.name),
                        subtitle: d.phoneNumber.isNotEmpty
                            ? Text(
                                d.phoneNumber,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              )
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: i == 0
                              ? const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                )
                              : i == drivers.length - 1
                                  ? const BorderRadius.vertical(
                                      bottom: Radius.circular(12),
                                    )
                                  : BorderRadius.zero,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.orange, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
