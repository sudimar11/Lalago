import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/models/service_area.dart';
import 'package:brgy/pages/driver_information_page.dart';
import 'package:brgy/services/delivery_zone_service.dart';

const _activeStatuses = [
  'Driver Assigned',
  'Driver Pending',
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

  @override
  void initState() {
    super.initState();
    _zonesFuture = DeliveryZoneService().getServiceAreas();
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
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _RiderOverviewTable(
                          riders: riders,
                          orderCounts: orderCounts,
                          areas: areas,
                        ),
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

  const _RiderOverviewTable({
    required this.riders,
    required this.orderCounts,
    required this.areas,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Active'), numeric: true),
          DataColumn(label: Text('Rejected'), numeric: true),
          DataColumn(label: Text('Completed'), numeric: true),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Zones')),
          DataColumn(label: Text('Action')),
        ],
        rows: riders.map((riderDoc) {
          final riderData = riderDoc.data() as Map<String, dynamic>;
          final riderId = riderDoc.id;
          final counts = orderCounts[riderId] ?? <String, int>{};
          final zoneNames = areas
              .where((a) => a.assignedDriverIds.contains(riderId))
              .map((a) => a.name)
              .toList();

          final firstName = riderData['firstName'] ?? '';
          final lastName = riderData['lastName'] ?? '';
          final phoneNumber = riderData['phoneNumber'] ?? '';
          final checkedInToday = riderData['checkedInToday'] == true;
          final riderName = '$firstName $lastName'.trim();
          final displayName =
              riderName.isEmpty ? 'Rider ${riderId.substring(0, 8)}...' : riderName;

          final active = counts['active'] ?? 0;
          final rejected = counts['rejected'] ?? 0;
          final completed = counts['completed'] ?? 0;
          final locationStr = _parseLocation(riderData);
          final zoneStr = zoneNames.isEmpty ? 'No zones' : zoneNames.join(', ');

          return DataRow(
            cells: [
              DataCell(
                CircleAvatar(
                  radius: 14,
                  backgroundColor: checkedInToday ? Colors.green : Colors.grey,
                  child: const Icon(
                    Icons.drive_eta,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              DataCell(
                Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              DataCell(Text(phoneNumber.isEmpty ? 'No phone' : phoneNumber)),
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
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DriverInformationPage(driverId: riderId),
                      ),
                    );
                  },
                  child: const Text('View'),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
