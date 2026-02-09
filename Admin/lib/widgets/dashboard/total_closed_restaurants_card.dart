import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TotalClosedRestaurantsCard extends StatelessWidget {
  final Stream<QuerySnapshot> restaurantsStream;

  const TotalClosedRestaurantsCard({
    super.key,
    required this.restaurantsStream,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: StreamBuilder<QuerySnapshot>(
          stream: restaurantsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 96,
                child: Center(child: Text('Failed to load')),
              );
            }

            final restaurants = snapshot.data?.docs ?? [];

            // Count closed restaurants
            int closedCount = 0;
            for (final restaurantDoc in restaurants) {
              final data = restaurantDoc.data();

              // Add null safety check to prevent crashes
              if (data == null || data is! Map<String, dynamic>) {
                continue; // Skip documents with null or invalid data
              }

              final dataMap = data;

              // Check various possible fields that indicate closed status
              final isOpen = dataMap['isOpen'];
              final closed = dataMap['closed'];
              final status = dataMap['status']?.toString().toLowerCase();
              final isPublished = dataMap['isPublished'];

              // Consider closed if:
              // - isOpen is false
              // - closed is true
              // - status contains 'closed'
              // - isPublished is false (if that's how they mark closed)
              if (isOpen == false ||
                  closed == true ||
                  (status != null && status.contains('closed')) ||
                  (isPublished == false &&
                      dataMap['isOpen'] == null &&
                      dataMap['closed'] == null)) {
                closedCount++;
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.store_mall_directory,
                    size: 20, color: Colors.orange),
                SizedBox(height: 4),
                Text(
                  'Total Closed Restaurants',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 2),
                Text(
                  '$closedCount',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
