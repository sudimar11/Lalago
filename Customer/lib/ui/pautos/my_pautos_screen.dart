import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/model/PautosOrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/ui/dialogs/PautosPostCompletionDialog.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/pautos/pautos_order_detail_screen.dart';
import 'package:foodie_customer/userPrefrence.dart';

class MyPautosScreen extends StatefulWidget {
  const MyPautosScreen({Key? key}) : super(key: key);

  @override
  State<MyPautosScreen> createState() => _MyPautosScreenState();
}

class _MyPautosScreenState extends State<MyPautosScreen> {
  StreamSubscription<List<PautosOrderModel>>? _completionSub;
  final Set<String> _shownCompletionOrderIds = {};

  @override
  void initState() {
    super.initState();
    _listenForCompletions();
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  void _listenForCompletions() {
    final userId = MyAppState.currentUser?.userID;
    if (userId == null) return;

    final fireStoreUtils = FireStoreUtils();
    _completionSub = fireStoreUtils.getPautosOrdersByAuthor(userId).listen(
      (List<PautosOrderModel> orders) async {
        if (!mounted) return;
        for (final order in orders) {
          if (order.status != 'Completed') continue;
          if (_shownCompletionOrderIds.contains(order.id)) continue;
          if (UserPreference.isCompletionDialogShown(userId, order.id)) {
            _shownCompletionOrderIds.add(order.id);
            continue;
          }
          _shownCompletionOrderIds.add(order.id);
          if (!mounted) return;
          try {
            await PautosPostCompletionDialog.show(context, order);
          } catch (e) {
            debugPrint('PautosPostCompletionDialog error: $e');
          }
          break;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MyAppState.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final authorID = MyAppState.currentUser!.userID;
    final fireStoreUtils = FireStoreUtils();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My PAUTOS',
          style: TextStyle(fontFamily: 'Poppinsm'),
        ),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<PautosOrderModel>>(
        stream: fireStoreUtils.getPautosOrdersByAuthor(authorID),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final errStr = snapshot.error.toString();
            debugPrint('PAUTOS Firestore error: $errStr');
            // Extract and log index creation URL for easy copy-paste
            final urlMatch = RegExp(
              r'https://[^\s]+create_composite[^\s]+',
            ).firstMatch(errStr);
            if (urlMatch != null) {
              debugPrint('CREATE INDEX (copy this URL): ${urlMatch.group(0)}');
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
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
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No PAUTOS requests yet',
                      style: TextStyle(
                        fontFamily: 'Poppinsm',
                        fontSize: 18,
                        color: isDarkMode(context)
                            ? Colors.white70
                            : Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a request from the home screen',
                      style: TextStyle(
                        fontFamily: 'Poppinsr',
                        fontSize: 14,
                        color: isDarkMode(context)
                            ? Colors.white54
                            : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
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
              return _PautosOrderTile(order: order);
            },
          );
        },
      ),
    );
  }
}

class _PautosOrderTile extends StatelessWidget {
  final PautosOrderModel order;

  const _PautosOrderTile({required this.order});

  String _truncateList(String text, {int maxLen = 60}) {
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
              builder: (context) =>
                  PautosOrderDetailScreen(orderId: order.id),
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
                      _truncateList(order.shoppingList),
                      style: TextStyle(
                        fontFamily: 'Poppinsm',
                        fontSize: 15,
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
                        fontFamily: 'Poppinsm',
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
                    '${currencyModel?.symbol ?? '₱'} '
                    '${order.maxBudget.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                    style: TextStyle(
                      fontFamily: 'Poppinsr',
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
                      fontFamily: 'Poppinsr',
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
