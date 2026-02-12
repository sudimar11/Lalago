import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TopBuyersTodayPage extends StatefulWidget {
  const TopBuyersTodayPage({super.key});

  @override
  State<TopBuyersTodayPage> createState() => _TopBuyersTodayPageState();
}

class _TopBuyersTodayPageState extends State<TopBuyersTodayPage> {
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
        title: const Text('Top 10 Buyers Today'),
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

          // Group orders by customer/buyer
          final Map<String, int> buyerOrderCounts = {};
          final Map<String, Map<String, dynamic>> buyerInfo = {};

          for (final orderDoc in orders) {
            try {
              final data = orderDoc.data();
              if (data == null || data is! Map<String, dynamic>) continue;

              final author = data['author'];
              if (author == null || author is! Map<String, dynamic>) continue;

              final authorId =
                  author['id'] as String? ?? author['authorID'] as String? ?? '';
              final authorName = author['firstName'] as String? ?? '';
              final authorLastName = author['lastName'] as String? ?? '';
              final fullName = '$authorName $authorLastName'.trim();
              final authorEmail = author['email'] as String? ?? '';
              final authorPhone = author['phoneNumber'] as String? ?? '';

              if (authorId.isNotEmpty) {
                buyerOrderCounts[authorId] =
                    (buyerOrderCounts[authorId] ?? 0) + 1;
                if (!buyerInfo.containsKey(authorId)) {
                  buyerInfo[authorId] = {
                    'fullName': fullName.isNotEmpty ? fullName : 'Customer',
                    'email': authorEmail,
                    'phone': authorPhone,
                    'firstName': authorName,
                    'lastName': authorLastName,
                  };
                }
              }
            } catch (e) {
              // Skip invalid documents
              continue;
            }
          }

          // Convert to list and sort by order count (descending)
          final buyerEntries = buyerOrderCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          // Take top 10
          final top10Buyers = buyerEntries.take(10).toList();

          if (top10Buyers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No buyers with orders today',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: top10Buyers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = top10Buyers[index];
              final buyerId = entry.key;
              final orderCount = entry.value;
              final info = buyerInfo[buyerId] ?? {};

              return _BuyerListItem(
                buyerId: buyerId,
                buyerInfo: info,
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

class _BuyerListItem extends StatelessWidget {
  final String buyerId;
  final Map<String, dynamic> buyerInfo;
  final int orderCount;
  final int rank;

  const _BuyerListItem({
    required this.buyerId,
    required this.buyerInfo,
    required this.orderCount,
    required this.rank,
  });

  Future<Map<String, dynamic>?> _fetchBuyerDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(buyerId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      // Return null on error
    }
    return null;
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber; // Gold
      case 2:
        return Colors.grey[400]!; // Silver
      case 3:
        return Colors.brown; // Bronze
      default:
        return Colors.orange;
    }
  }

  IconData _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return Icons.emoji_events; // Trophy
      case 2:
        return Icons.workspace_premium; // Medal
      case 3:
        return Icons.military_tech; // Medal
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchBuyerDetails(),
      builder: (context, snapshot) {
        final userData = snapshot.data ?? buyerInfo;
        final fullName = userData['fullName'] as String? ??
            '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
        final displayName = fullName.isNotEmpty ? fullName : 'Customer';
        final email = userData['email'] as String? ?? '';
        final phone = userData['phoneNumber'] as String? ?? '';
        final profilePictureURL =
            userData['profilePictureURL'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: rank <= 3 ? 4 : 1,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getRankIcon(rank),
                        color: _getRankColor(rank),
                        size: 24,
                      ),
                      Text(
                        '#$rank',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getRankColor(rank),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.orange,
                  backgroundImage: profilePictureURL.isNotEmpty
                      ? NetworkImage(profilePictureURL)
                      : null,
                  child: profilePictureURL.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
              ],
            ),
            title: Text(
              displayName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: const TextStyle(fontSize: 13),
                  ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getRankColor(rank).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getRankColor(rank).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$orderCount',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getRankColor(rank),
                    ),
                  ),
                  Text(
                    'order${orderCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      color: _getRankColor(rank),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

