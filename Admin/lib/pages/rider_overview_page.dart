import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/models/service_area.dart';
import 'package:brgy/pages/driver_information_page.dart';
import 'package:brgy/services/delivery_zone_service.dart';
import 'package:brgy/services/zone_capacity_service.dart';
import 'package:brgy/widgets/capacity_dashboard_widget.dart';
import 'package:brgy/pages/order_history_page.dart';

const _activeStatuses = [
  'Driver Assigned',
  'Driver Accepted',
  'Order Shipped',
  'In Transit',
];

const _rejectedStatuses = ['Driver Rejected', 'Order Rejected'];
const _completedStatus = 'Order Completed';

class RiderOverviewPage extends StatefulWidget {
  const RiderOverviewPage({super.key});

  @override
  State<RiderOverviewPage> createState() => _RiderOverviewPageState();
}

class _RiderOverviewPageState extends State<RiderOverviewPage> {
  late Future<List<ServiceArea>> _zonesFuture;
  final _capacityService = ZoneCapacityService();
  late final Stream<List<ZoneCapacity>> _capacityStream;
  String _capacityFilter = 'all'; // 'all', 'at_capacity', 'near'

  @override
  void initState() {
    super.initState();
    _zonesFuture = DeliveryZoneService().getServiceAreas();
    _capacityStream =
        _capacityService.streamAllZoneCapacities();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _zonesFuture = DeliveryZoneService().getServiceAreas();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    final startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    final ridersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .orderBy('firstName');

    final ordersQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Overview'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ridersQuery.snapshots(),
        builder: (context, ridersSnapshot) {
          if (ridersSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ridersSnapshot.hasError) {
            final errStr = ridersSnapshot.error.toString();
            developer.log(
              'Rider overview - failed to load riders: $errStr',
              name: 'RiderOverviewPage',
              error: ridersSnapshot.error,
              stackTrace: ridersSnapshot.stackTrace,
            );
            // Extract and log index URL for easy copy-paste
            final urlMatch = RegExp(r'https://[^\s\)`]+').firstMatch(errStr);
            if (urlMatch != null) {
              final url = urlMatch.group(0)!;
              developer.log(
                'Create Firestore index - copy and open in browser: $url',
                name: 'RiderOverviewPage',
              );
              debugPrint('');
              debugPrint('=== Firestore index required - follow this link ===');
              debugPrint(url);
              debugPrint('==================================================');
              debugPrint('');
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Failed to load riders: ${ridersSnapshot.error}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final riders = ridersSnapshot.data?.docs ?? [];
          if (riders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.drive_eta, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No riders found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: ordersQuery,
            builder: (context, ordersSnapshot) {
              final orderCounts = ordersSnapshot.hasData
                  ? _aggregateOrdersByDriver(
                      ordersSnapshot.data!,
                      startOfDay,
                      endOfDay,
                    )
                  : <String, Map<String, int>>{};

              return FutureBuilder<List<ServiceArea>>(
                future: _zonesFuture,
                builder: (context, zonesSnapshot) {
                  final areas = zonesSnapshot.data ?? [];

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      scrollDirection: Axis.vertical,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          CapacityDashboardWidget(
                            capacityStream: _capacityStream,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('All'),
                                  selected:
                                      _capacityFilter == 'all',
                                  onSelected: (_) => setState(
                                    () =>
                                        _capacityFilter = 'all',
                                  ),
                                ),
                                FilterChip(
                                  label:
                                      const Text('At Capacity'),
                                  selected:
                                      _capacityFilter ==
                                          'at_capacity',
                                  onSelected: (_) => setState(
                                    () => _capacityFilter =
                                        'at_capacity',
                                  ),
                                ),
                                FilterChip(
                                  label: const Text(
                                    'Near Capacity',
                                  ),
                                  selected:
                                      _capacityFilter == 'near',
                                  onSelected: (_) => setState(
                                    () =>
                                        _capacityFilter = 'near',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _RiderOverviewTable(
                              riders: riders,
                              orderCounts: orderCounts,
                              areas: areas,
                              capacityFilter: _capacityFilter,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

Map<String, Map<String, int>> _aggregateOrdersByDriver(
  QuerySnapshot snapshot,
  DateTime startOfDay,
  DateTime endOfDay,
) {
  final result = <String, Map<String, int>>{};

  for (final doc in snapshot.docs) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) continue;

    final driverId = data['driverID'] as String?;
    if (driverId == null || driverId.isEmpty) continue;

    final status = (data['status'] ?? '').toString();
    if (status.isEmpty) continue;

    final createdAt = data['createdAt'];
    DateTime? orderDate;
    if (createdAt is Timestamp) {
      orderDate = createdAt.toDate();
    } else if (createdAt is DateTime) {
      orderDate = createdAt;
    }

    final isToday = orderDate != null &&
        !orderDate.isBefore(startOfDay) &&
        !orderDate.isAfter(endOfDay);

    result.putIfAbsent(
      driverId,
      () => {'active': 0, 'rejected': 0, 'completed': 0},
    );

    final counts = result[driverId]!;

    if (_activeStatuses.contains(status)) {
      counts['active'] = counts['active']! + 1;
    } else if (_rejectedStatuses.contains(status) && isToday) {
      counts['rejected'] = counts['rejected']! + 1;
    } else if (status == _completedStatus && isToday) {
      counts['completed'] = counts['completed']! + 1;
    }
  }

  return result;
}

String _getRiderDisplayStatus(Map<String, dynamic> riderData) {
  final availability =
      riderData['riderAvailability'] as String? ?? 'offline';
  final lastActive =
      riderData['lastActivityTimestamp'] as Timestamp?;
  final locationUpdated =
      riderData['locationUpdatedAt'] as Timestamp?;

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

String? _parseLocation(Map<String, dynamic> userData) {
  final loc = userData['location'];
  if (loc == null) return null;

  double? lat;
  double? lng;

  if (loc is GeoPoint) {
    lat = loc.latitude;
    lng = loc.longitude;
  } else if (loc is Map) {
    final latVal = loc['latitude'];
    final lngVal = loc['longitude'];
    if (latVal != null && lngVal != null) {
      lat = (latVal is num) ? latVal.toDouble() : double.tryParse('$latVal');
      lng = (lngVal is num) ? lngVal.toDouble() : double.tryParse('$lngVal');
    }
  }

  if (lat == null || lng == null) return null;
  if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return null;
  return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

class _RiderOverviewTable extends StatelessWidget {
  final List<QueryDocumentSnapshot> riders;
  final Map<String, Map<String, int>> orderCounts;
  final List<ServiceArea> areas;
  final String capacityFilter;

  const _RiderOverviewTable({
    required this.riders,
    required this.orderCounts,
    required this.areas,
    required this.capacityFilter,
  });

  List<QueryDocumentSnapshot> _filteredRiders() {
    if (capacityFilter == 'all') return riders;

    final atCapZoneIds = <String>{};
    final nearCapZoneIds = <String>{};

    for (final a in areas) {
      if (a.maxRiders == null) continue;
      final assigned = a.assignedDriverIds.length;
      if (assigned >= a.maxRiders!) {
        atCapZoneIds.add(a.id);
      } else if (assigned >= (a.maxRiders! * 0.7)) {
        nearCapZoneIds.add(a.id);
      }
    }

    return riders.where((riderDoc) {
      final riderId = riderDoc.id;
      final riderZones = areas
          .where((a) => a.assignedDriverIds.contains(riderId))
          .map((a) => a.id)
          .toSet();

      if (capacityFilter == 'at_capacity') {
        return riderZones
            .any((zId) => atCapZoneIds.contains(zId));
      }
      if (capacityFilter == 'near') {
        return riderZones.any(
          (zId) =>
              atCapZoneIds.contains(zId) ||
              nearCapZoneIds.contains(zId),
        );
      }
      return true;
    }).toList();
  }

  Future<void> _quickCleanupRider(
    BuildContext context,
    String riderId,
    String riderName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Cleanup'),
        content: Text(
          'Reset stuck orders for $riderName?\n\n'
          'This will clear inProgressOrderID, '
          'set availability to "available", '
          'and set isActive to true.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cleanup'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Direct rider status mutation is disabled. Use backend dispatch controls.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRiders = _filteredRiders();
    return Card(
      child: DataTable(
        headingRowColor:
            WidgetStateProperty.all(Colors.grey.shade200),
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Active'), numeric: true),
          DataColumn(label: Text('Rejected'), numeric: true),
          DataColumn(
            label: Text('Completed'),
            numeric: true,
          ),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Zones')),
          DataColumn(label: Text('Capacity')),
          DataColumn(label: Text('Action')),
        ],
        rows: filteredRiders.map((riderDoc) {
          final riderData =
              riderDoc.data() as Map<String, dynamic>;
          final riderId = riderDoc.id;
          final counts =
              orderCounts[riderId] ?? <String, int>{};
          final riderZones = areas
              .where(
                (a) => a.assignedDriverIds.contains(riderId),
              )
              .toList();
          final zoneNames =
              riderZones.map((a) => a.name).toList();

          final firstName = riderData['firstName'] ?? '';
          final lastName = riderData['lastName'] ?? '';
          final phoneNumber = riderData['phoneNumber'] ?? '';
          final displayStatus = _getRiderDisplayStatus(riderData);
          final riderName = '$firstName $lastName'.trim();
          final displayName = riderName.isEmpty
              ? 'Rider ${riderId.substring(0, 8)}...'
              : riderName;

          final active = counts['active'] ?? 0;
          final rejected = counts['rejected'] ?? 0;
          final completed = counts['completed'] ?? 0;
          final locationStr = _parseLocation(riderData);
          final zoneStr = zoneNames.isEmpty
              ? 'No zones'
              : zoneNames.join(', ');

          // Build capacity info from zones this rider belongs to
          final capWidgets = <Widget>[];
          for (final z in riderZones) {
            if (z.maxRiders != null) {
              final assigned = z.assignedDriverIds.length;
              final pct =
                  (assigned / z.maxRiders!).clamp(0.0, 1.0);
              final color = pct >= 1.0
                  ? Colors.red
                  : pct >= 0.9
                      ? Colors.orange
                      : pct >= 0.7
                          ? Colors.amber
                          : Colors.green;
              capWidgets.add(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation(color),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$assigned/${z.maxRiders}',
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }
          }

          return DataRow(
            cells: [
              DataCell(
                Text(
                  displayStatus,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              DataCell(
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              DataCell(
                Text(
                  phoneNumber.isEmpty
                      ? 'No phone'
                      : phoneNumber,
                ),
              ),
              DataCell(Text('$active')),
              DataCell(Text('$rejected')),
              DataCell(Text('$completed')),
              DataCell(
                SizedBox(
                  width: 120,
                  child: Text(
                    locationStr ?? 'No location',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: locationStr != null
                          ? Colors.black87
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 100,
                  child: Text(
                    zoneStr,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: zoneNames.isEmpty
                          ? Colors.grey
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
              DataCell(
                capWidgets.isEmpty
                    ? Text(
                        '—',
                        style: TextStyle(
                          color: Colors.grey[400],
                        ),
                      )
                    : Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: capWidgets,
                      ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DriverInformationPage(
                              driverId: riderId,
                            ),
                          ),
                        );
                      },
                      child: const Text('View'),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.receipt_long,
                        size: 18,
                      ),
                      tooltip: 'Order History',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OrderHistoryPage(
                              initialRiderId: riderId,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.cleaning_services,
                        size: 18,
                        color: Colors.orange,
                      ),
                      tooltip: 'Quick Cleanup',
                      onPressed: () =>
                          _quickCleanupRider(
                        context,
                        riderId,
                        displayName,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
