import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TopRestaurantsOrdersTodayPage extends StatefulWidget {
  const TopRestaurantsOrdersTodayPage({super.key});

  @override
  State<TopRestaurantsOrdersTodayPage> createState() =>
      _TopRestaurantsOrdersTodayPageState();
}

class _TopRestaurantsOrdersTodayPageState
    extends State<TopRestaurantsOrdersTodayPage> {
  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();
    final Query ordersTodayQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Restaurants by Orders Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ordersTodayQuery.snapshots(),
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ordersSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load orders'),
                ],
              ),
            );
          }

          final orders = ordersSnapshot.data?.docs ?? [];

          // Group orders by restaurant/vendor
          final Map<String, int> restaurantOrderCounts = {};
          final Map<String, Map<String, dynamic>> restaurantInfo = {};

          for (final orderDoc in orders) {
            try {
              final data = orderDoc.data();
              if (data == null || data is! Map<String, dynamic>) continue;

              final vendor = data['vendor'];
              if (vendor == null || vendor is! Map<String, dynamic>) continue;

              // Try multiple vendor ID fields to match restaurants
              final vendorId = vendor['id'] as String? ??
                  vendor['vendorId'] as String? ??
                  '';
              final vendorTitle = vendor['title'] as String? ??
                  vendor['authorName'] as String? ??
                  '';

              String? restaurantKey;
              String restaurantName = vendorTitle;

              // Use vendor ID as primary key if available
              if (vendorId.isNotEmpty) {
                restaurantKey = vendorId;
              } else if (vendorTitle.isNotEmpty) {
                restaurantKey = vendorTitle;
              }

              if (restaurantKey != null && restaurantKey.isNotEmpty) {
                restaurantOrderCounts[restaurantKey] =
                    (restaurantOrderCounts[restaurantKey] ?? 0) + 1;
                if (!restaurantInfo.containsKey(restaurantKey)) {
                  restaurantInfo[restaurantKey] = {
                    'name': restaurantName,
                    'vendorId': vendorId,
                    'vendorTitle': vendorTitle,
                  };
                }
              }
            } catch (e) {
              // Skip invalid documents
              continue;
            }
          }

          // Convert to list and sort by order count (descending)
          final restaurantEntries = restaurantOrderCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          if (restaurantEntries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.restaurant, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No restaurants with orders today',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: restaurantEntries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = restaurantEntries[index];
              final restaurantKey = entry.key;
              final orderCount = entry.value;
              final info = restaurantInfo[restaurantKey] ?? {};
              final restaurantName = info['name'] ?? 'Restaurant';

              return _RestaurantListItem(
                restaurantKey: restaurantKey,
                restaurantName: restaurantName,
                orderCount: orderCount,
                rank: index + 1,
              );
            },
          );
        },
      ),
    );
  }
}

class _RestaurantListItem extends StatelessWidget {
  final String restaurantKey;
  final String restaurantName;
  final int orderCount;
  final int rank;

  const _RestaurantListItem({
    required this.restaurantKey,
    required this.restaurantName,
    required this.orderCount,
    required this.rank,
  });

  Future<Map<String, dynamic>?> _fetchRestaurantInfo() async {
    try {
      // Try to fetch restaurant details from vendors collection
      final doc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(restaurantKey)
          .get();

      if (doc.exists) {
        return doc.data();
      }

      // If not found by ID, try searching by title
      final querySnapshot = await FirebaseFirestore.instance
          .collection('vendors')
          .where('title', isEqualTo: restaurantName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data();
      }
    } catch (e) {
      // Return null on error
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchRestaurantInfo(),
      builder: (context, snapshot) {
        final vendorData = snapshot.data;
        final logo = vendorData != null
            ? (vendorData['photo'] ??
                    vendorData['logo'] ??
                    vendorData['imageUrl'] ??
                    '')
                .toString()
            : '';

        return ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                alignment: Alignment.center,
                child: Text(
                  '#$rank',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.orange,
                backgroundImage:
                    logo.isNotEmpty ? NetworkImage(logo) : null,
                child: logo.isEmpty
                    ? const Icon(Icons.restaurant, color: Colors.white)
                    : null,
              ),
            ],
          ),
          title: Text(
            restaurantName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          subtitle: Text('Orders today: $orderCount'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$orderCount',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
        );
      },
    );
  }
}

