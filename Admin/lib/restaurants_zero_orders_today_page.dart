import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantsZeroOrdersTodayPage extends StatefulWidget {
  const RestaurantsZeroOrdersTodayPage({super.key});

  @override
  State<RestaurantsZeroOrdersTodayPage> createState() =>
      _RestaurantsZeroOrdersTodayPageState();
}

class _RestaurantsZeroOrdersTodayPageState
    extends State<RestaurantsZeroOrdersTodayPage> {
  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();
    final Query vendorsQuery =
        FirebaseFirestore.instance.collection('vendors').orderBy('title');
    final Query ordersTodayQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants with Zero Orders Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: vendorsQuery.snapshots(),
        builder: (context, vendorsSnapshot) {
          if (vendorsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vendorsSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load restaurants'),
                ],
              ),
            );
          }

          final vendors = vendorsSnapshot.data?.docs ?? [];

          if (vendors.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.restaurant, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No restaurants found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Get orders from today
          return StreamBuilder<QuerySnapshot>(
            stream: ordersTodayQuery.snapshots(),
            builder: (context, ordersSnapshot) {
              if (ordersSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Extract all restaurant IDs that have orders today
              final orders = ordersSnapshot.data?.docs ?? [];
              final Set<String> restaurantsWithOrdersToday = {};

              for (final orderDoc in orders) {
                try {
                  final data = orderDoc.data();
                  if (data == null || data is! Map<String, dynamic>) continue;

                  final vendor = data['vendor'];
                  if (vendor == null || vendor is! Map<String, dynamic>)
                    continue;

                  // Get vendor ID - try multiple possible field names
                  final vendorId = vendor['id'] as String?;
                  if (vendorId != null && vendorId.isNotEmpty) {
                    restaurantsWithOrdersToday.add(vendorId);
                  }

                  // Also check vendorId field
                  final vendorIdAlt = vendor['vendorId'] as String?;
                  if (vendorIdAlt != null && vendorIdAlt.isNotEmpty) {
                    restaurantsWithOrdersToday.add(vendorIdAlt);
                  }
                } catch (e) {
                  // Skip invalid documents
                  continue;
                }
              }

              // Now check each restaurant - if it's NOT in the set, it has 0 orders
              final zeroOrderRestaurants = <Map<String, dynamic>>[];

              for (final vendorDoc in vendors) {
                final vendorId = vendorDoc.id;
                final vendorData = vendorDoc.data() as Map<String, dynamic>;
                final title =
                    (vendorData['title'] ?? vendorData['authorName'] ?? '')
                        .toString();

                // Check if this restaurant has orders today
                // The restaurant has orders if its ID appears in today's orders
                bool hasOrdersToday =
                    restaurantsWithOrdersToday.contains(vendorId);

                // Also check if any order's vendor ID matches this restaurant
                if (!hasOrdersToday) {
                  for (final orderDoc in orders) {
                    try {
                      final data = orderDoc.data();
                      if (data == null || data is! Map<String, dynamic>)
                        continue;

                      final vendor = data['vendor'];
                      if (vendor == null || vendor is! Map<String, dynamic>) {
                        continue;
                      }

                      final orderVendorId = vendor['id'] as String?;
                      final orderVendorIdAlt = vendor['vendorId'] as String?;
                      final orderVendorTitle = vendor['title'] as String?;
                      final orderVendorAuthorName =
                          vendor['authorName'] as String?;

                      // Match by ID
                      if ((orderVendorId != null &&
                              orderVendorId == vendorId) ||
                          (orderVendorIdAlt != null &&
                              orderVendorIdAlt == vendorId)) {
                        hasOrdersToday = true;
                        break;
                      }

                      // Match by title/name
                      if (title.isNotEmpty) {
                        if ((orderVendorTitle != null &&
                                orderVendorTitle == title) ||
                            (orderVendorAuthorName != null &&
                                orderVendorAuthorName == title)) {
                          hasOrdersToday = true;
                          break;
                        }
                      }
                    } catch (e) {
                      continue;
                    }
                  }
                }

                // If restaurant has NO orders today, add it to the list
                if (!hasOrdersToday) {
                  zeroOrderRestaurants.add({
                    'vendorId': vendorId,
                    'title': title.isNotEmpty ? title : 'Restaurant',
                    'vendorData': vendorData,
                  });
                }
              }

              if (zeroOrderRestaurants.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      const Text(
                        'All restaurants have orders today!',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: zeroOrderRestaurants.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final restaurant = zeroOrderRestaurants[index];
                  final vendorId = restaurant['vendorId'] as String;
                  final title = restaurant['title'] as String;

                  return _RestaurantListItem(
                    restaurantKey: vendorId,
                    restaurantName: title,
                    orderCount: 0,
                    vendorData:
                        restaurant['vendorData'] as Map<String, dynamic>,
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

class _RestaurantListItem extends StatelessWidget {
  final String restaurantKey;
  final String restaurantName;
  final int orderCount;
  final Map<String, dynamic> vendorData;

  const _RestaurantListItem({
    required this.restaurantKey,
    required this.restaurantName,
    required this.orderCount,
    required this.vendorData,
  });

  @override
  Widget build(BuildContext context) {
    final logo = (vendorData['photo'] ??
            vendorData['logo'] ??
            vendorData['imageUrl'] ??
            '')
        .toString();

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.orange,
        backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
        child: logo.isEmpty
            ? const Icon(Icons.restaurant, color: Colors.white)
            : null,
      ),
      title: Text(
        restaurantName,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: const Text('Orders today: 0'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$orderCount',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
      ),
    );
  }
}
