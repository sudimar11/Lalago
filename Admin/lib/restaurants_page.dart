import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:brgy/restaurant_info_page.dart';

class RestaurantsPage extends StatefulWidget {
  const RestaurantsPage({super.key});

  @override
  State<RestaurantsPage> createState() => _RestaurantsPageState();
}

class _RestaurantsPageState extends State<RestaurantsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _openRestaurantLocation({
    required BuildContext context,
    required String title,
    required double? latitude,
    required double? longitude,
  }) async {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null || lat == 0 || lng == 0) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unable to open location'),
          content: SelectableText.rich(
            TextSpan(
              text: 'Could not open maps for ',
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: '.'),
              ],
              style: const TextStyle(color: Colors.red),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unable to open location'),
          content: SelectableText.rich(
            TextSpan(
              text: 'Error opening maps for $title:\n$e',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _openRestaurantInfo(BuildContext context, DocumentSnapshot vendorDoc) {
    final vData = vendorDoc.data() as Map<String, dynamic>?;
    if (vData == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RestaurantInfoPage(
          vendorId: vendorDoc.id,
          vendorData: Map<String, dynamic>.from(vData),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendorsQuery =
        FirebaseFirestore.instance.collection('vendors').orderBy('title');

    Future<int> _safeCount(Query q) async {
      try {
        final snap = await q.count().get();
        return snap.count ?? 0;
      } catch (_) {
        return 0;
      }
    }

    Future<int> _fetchOrderCountForVendor(DocumentSnapshot vendorDoc) async {
      final data = vendorDoc.data() as Map<String, dynamic>;
      final vendorDocId = vendorDoc.id;
      final title = (data['title'] ?? data['authorName'] ?? '').toString();

      final queries = <Query>[
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('vendor.id', isEqualTo: vendorDocId),
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('vendor.vendorId', isEqualTo: vendorDocId),
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('vendor.title', isEqualTo: title),
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('vendor.authorName', isEqualTo: title),
      ];

      final results = await Future.wait(queries.map(_safeCount));
      return results.fold<int>(0, (a, b) => a + b);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search restaurants',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: vendorsQuery.snapshots(),
              builder: (context, vendorsSnap) {
                if (vendorsSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vendorsSnap.hasError) {
                  return const Center(child: Text('Failed to load vendors'));
                }

                final vendors = vendorsSnap.data?.docs ?? const [];
                if (vendors.isEmpty) {
                  return const Center(child: Text('No restaurants found'));
                }

                final filteredVendors = vendors.where((v) {
                  final data = v.data() as Map<String, dynamic>;
                  final title =
                      (data['title'] ?? data['authorName'] ?? '').toString();
                  if (_query.isEmpty) return true;
                  return title.toLowerCase().contains(_query);
                }).toList();

                return ListView.separated(
                  itemCount: filteredVendors.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final vendorDoc = filteredVendors[index];
                    final vData = vendorDoc.data() as Map<String, dynamic>;
                    final title =
                        (vData['title'] ?? vData['authorName'] ?? 'Restaurant')
                            .toString();
                    final logo = (vData['photo'] ??
                            vData['logo'] ??
                            vData['imageUrl'] ??
                            '')
                        .toString();
                    final latitude = _asDouble(vData['latitude']);
                    final longitude = _asDouble(vData['longitude']);
                    final hasLocation = (latitude != null &&
                        longitude != null &&
                        latitude != 0 &&
                        longitude != 0);

                    return FutureBuilder<int>(
                      future: _fetchOrderCountForVendor(vendorDoc),
                      builder: (context, snap) {
                        final count = snap.data ?? 0;
                        final subtitle =
                            snap.connectionState == ConnectionState.waiting
                                ? 'Total orders: …'
                                : 'Total orders: $count';
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.orange,
                            backgroundImage:
                                (logo.isNotEmpty) ? NetworkImage(logo) : null,
                            child: logo.isEmpty
                                ? const Icon(Icons.store, color: Colors.white)
                                : null,
                          ),
                          title: Text(title),
                          subtitle: Text(subtitle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'View restaurant information',
                                onPressed: () =>
                                    _openRestaurantInfo(context, vendorDoc),
                                icon: const Icon(Icons.info_outline),
                              ),
                              IconButton(
                                tooltip: hasLocation
                                    ? 'Open location'
                                    : 'No location available',
                                onPressed: hasLocation
                                    ? () => _openRestaurantLocation(
                                          context: context,
                                          title: title,
                                          latitude: latitude,
                                          longitude: longitude,
                                        )
                                    : null,
                                icon: const Icon(Icons.location_on_outlined),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
