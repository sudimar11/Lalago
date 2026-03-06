import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/PautosOrderModel.dart';
import 'package:foodie_driver/services/pautos_service.dart';
import 'package:foodie_driver/ui/pautos/pautos_order_detail_screen.dart';

class MyPautosOrdersScreen extends StatelessWidget {
  const MyPautosOrdersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.isEmpty) {
      return const Center(child: Text('Please sign in'));
    }

    return StreamBuilder<List<PautosOrderModel>>(
      stream: PautosService.getMyPautosOrders(driverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError) {
          final errStr = snapshot.error.toString();
          developer.log('PAUTOS Firestore error: $errStr');
          final urlMatch = RegExp(r'https://[^\s]+create_composite[^\s]+')
              .firstMatch(errStr);
          if (urlMatch != null) {
            developer.log('CREATE INDEX (copy this URL): ${urlMatch.group(0)}');
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: $errStr',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No PAUTOS orders yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode(context)
                          ? Colors.white70
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Accepted assignments will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode(context)
                          ? Colors.white54
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _MyPautosOrderTile(order: order);
          },
        );
      },
    );
  }
}

class _MyPautosOrderTile extends StatelessWidget {
  final PautosOrderModel order;

  const _MyPautosOrderTile({required this.order});

  String _truncate(String text, {int maxLen = 60}) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = order.status == 'Driver Accepted'
        ? Colors.green
        : Color(COLOR_PRIMARY);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PautosOrderDetailScreen(orderId: order.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _truncate(order.shoppingList),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      order.status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    amountShow(amount: order.maxBudget.toString()),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode(context)
                          ? Colors.white70
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a')
                        .format(order.createdAt.toDate()),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode(context)
                          ? Colors.white54
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
