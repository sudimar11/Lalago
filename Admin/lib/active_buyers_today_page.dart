import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveBuyersTodayPage extends StatelessWidget {
  const ActiveBuyersTodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Buyers Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load data'),
                ],
              ),
            );
          }

          final orders = snapshot.data?.docs ?? [];

          // Extract unique customers with order counts
          final Map<String, Map<String, dynamic>> uniqueCustomers = {};
          for (final orderDoc in orders) {
            try {
              final data = orderDoc.data() as Map<String, dynamic>;
              final author = data['author'] as Map<String, dynamic>?;
              if (author != null) {
                final customerId = author['id'] as String?;
                if (customerId != null && customerId.isNotEmpty) {
                  if (!uniqueCustomers.containsKey(customerId)) {
                    final firstName = author['firstName'] ?? '';
                    final lastName = author['lastName'] ?? '';
                    final email = author['email'] ?? '';
                    final phone = author['phoneNumber'] ?? '';
                    uniqueCustomers[customerId] = {
                      'firstName': firstName,
                      'lastName': lastName,
                      'email': email,
                      'phone': phone,
                      'orderCount': 0,
                    };
                  }
                  uniqueCustomers[customerId]!['orderCount'] =
                      (uniqueCustomers[customerId]!['orderCount'] as int) + 1;
                }
              }
            } catch (e) {
              continue;
            }
          }

          final customerList = uniqueCustomers.entries.toList()
            ..sort((a, b) => (b.value['orderCount'] as int)
                .compareTo(a.value['orderCount'] as int));

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange[50],
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.orange, size: 32),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Active Buyers',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '${uniqueCustomers.length}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: uniqueCustomers.isEmpty
                    ? const Center(
                        child: Text(
                          'No active buyers today',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: customerList.length,
                        itemBuilder: (context, index) {
                          final entry = customerList[index];
                          final customerData = entry.value;
                          final fullName =
                              '${customerData['firstName']} ${customerData['lastName']}'
                                  .trim();

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange,
                                child: Text(
                                  fullName.isNotEmpty
                                      ? fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                fullName.isEmpty ? 'Unknown' : fullName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (customerData['phone'] != null &&
                                      customerData['phone'].toString().isNotEmpty)
                                    Text('Phone: ${customerData['phone']}'),
                                  if (customerData['email'] != null &&
                                      customerData['email'].toString().isNotEmpty)
                                    Text('Email: ${customerData['email']}'),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${customerData['orderCount']} order${(customerData['orderCount'] as int) == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

