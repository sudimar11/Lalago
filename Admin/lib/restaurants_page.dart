import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantsPage extends StatefulWidget {
  const RestaurantsPage({super.key});

  @override
  State<RestaurantsPage> createState() => _RestaurantsPageState();
}

class _RestaurantsPageState extends State<RestaurantsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
