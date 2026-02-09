import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/ui/wallet/paid_transactions_page.dart';
import 'package:foodie_driver/ui/wallet/today_transactions_page.dart';
import 'package:intl/intl.dart';

class WalletDetailPage extends StatefulWidget {
  final String walletType;

  const WalletDetailPage({
    Key? key,
    required this.walletType,
  }) : super(key: key);

  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage> {
  static const int _pageSize = 10;

  bool _showTodayOnly = false;
  bool _isTransmitting = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _loadedMoreDocs = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _transmitError;
  bool _isRequestingPayout = false;
  String? _payoutError;
  bool _isDeletingHistory = false;
  String? _deleteHistoryError;
  Set<String> _updatingTransactions = {};
  int _payoutRetryAttempt = 0;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _walletBalanceStream(
      String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();
  }

  Future<void> _handleTransmit() async {
    if (_isTransmitting) return;

    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _transmitError = 'User not logged in';
      });
      print('❌ Transmit Error: User not logged in');
      return;
    }

    setState(() {
      _isTransmitting = true;
      _transmitError = null;
    });

    print('🔵 Starting transmit request for user: ${user.uid}');

    // Fetch current balance for validation
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!userDoc.exists) {
      setState(() {
        _transmitError = 'User document not found';
        _isTransmitting = false;
      });
      return;
    }

    final currentBalance =
        ((userDoc.data()?['wallet_credit'] ?? 0.0) as num).toDouble();
    print('🔵 Current balance: $currentBalance');

    // Validate balance
    if (currentBalance <= 0) {
      setState(() {
        _transmitError = 'Credit wallet balance is zero or negative';
        _isTransmitting = false;
      });
      print('❌ Transmit Error: Balance is zero or negative');
      return;
    }

    // Prevent duplicate: block if already has pending transmit
    final transmitRequests =
        (userDoc.data()?['transmitRequests'] as List<dynamic>?) ?? [];
    final hasPendingTransmit =
        transmitRequests.any((r) => (r['status'] as String? ?? '') == 'pending');
    if (hasPendingTransmit) {
      setState(() {
        _transmitError =
            'You already have a pending transmit request. Please wait for '
            'confirmation.';
        _isTransmitting = false;
      });
      print('❌ Transmit Error: Pending request already exists');
      return;
    }

    double transmittedAmount = 0.0;
    List<String> orderIds = [];

    try {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      print('🔵 Fetching user document...');

      // First verify the document exists
      final userDocCheck = await userRef.get();
      if (!userDocCheck.exists) {
        throw Exception('User document not found for UID: ${user.uid}');
      }

      print('✅ User document found');

      // Get all unpaid credit transactions to track order IDs
      print('🔵 Fetching unpaid credit transactions...');
      final unpaidCredits = await FirebaseFirestore.instance
          .collection('wallet')
          .where('user_id', isEqualTo: user.uid)
          .where('walletType', isEqualTo: 'credit')
          .where('payment_status', isEqualTo: 'success')
          .get();

      // Collect order IDs from unpaid transactions
      orderIds = unpaidCredits.docs
          .where((doc) {
            final data = doc.data();
            final isPaidOut = data['isPaidOut'] as bool? ?? false;
            final orderId = data['order_id'] as String? ?? '';
            return !isPaidOut && orderId.isNotEmpty;
          })
          .map((doc) => doc.data()['order_id'] as String)
          .toList();

      print('🔵 Found ${orderIds.length} unpaid orders to include in remittance');

      String requestId = '';

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User document not found in transaction');
        }

        final userData = userSnap.data() ?? {};
        print('🔵 User data retrieved: ${userData.keys.toList()}');

        final currentCredit =
            ((userData['wallet_credit'] ?? 0.0) as num).toDouble();

        print('🔵 Current credit in transaction: $currentCredit');

        // Double-check balance hasn't changed
        if (currentCredit <= 0) {
          throw Exception('Credit wallet balance is zero or negative');
        }

        // Store amount for success message
        transmittedAmount = currentCredit;

        // Get existing transmit requests or initialize as empty array
        final List<dynamic> existingRequests =
            (userData['transmitRequests'] as List<dynamic>?) ?? [];

        print('🔵 Existing transmit requests: ${existingRequests.length}');

        // Block duplicate: ensure no pending request in transaction
        final hasPending =
            existingRequests.any((r) => (r['status'] as String? ?? '') == 'pending');
        if (hasPending) {
          throw Exception('A transmit request is already pending');
        }

        // Create new transmit request with order IDs
        requestId = FirebaseFirestore.instance.collection('users').doc().id;
        final newRequest = {
          'id': requestId,
          'amount': currentCredit,
          'status': 'pending',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'type': 'credit_wallet_transmit',
          'confirmedAt': null,
          'orderIds': orderIds, // Track which orders are included
        };

        print('🔵 New request ID: $requestId');
        print('🔵 New request amount: $currentCredit');
        print('🔵 Order IDs included: ${orderIds.length}');

        // Append new request to array
        final updatedRequests = [...existingRequests, newRequest];

        // Update user document with new transmit request
        tx.update(userRef, {
          'transmitRequests': updatedRequests,
        });

        print('✅ Transaction update queued');
      });

      print('✅ Transaction committed successfully!');

      // Create a transaction entry in wallet collection
      final walletTransactionId =
          FirebaseFirestore.instance.collection('wallet').doc().id;
      await FirebaseFirestore.instance
          .collection('wallet')
          .doc(walletTransactionId)
          .set({
        'id': walletTransactionId,
        'user_id': user.uid,
        'amount': -transmittedAmount, // Negative amount = money going out
        'date': Timestamp.fromDate(DateTime.now()),
        'note': 'Transmit Request',
        'payment_method': 'Transmit',
        'walletType': widget.walletType,
        'status': 'pending',
        'transmitRequestId': requestId, // Link to the transmit request
        'isTopUp': false,
        'payment_status': 'pending',
        'transactionUser': 'driver',
        'order_id': '',
        'isPaidOut': false, // Track payout status
      });

      print('✅ Wallet transaction created: $walletTransactionId');

      // Success - show success message
      // Balance will update automatically via StreamBuilder
      if (!mounted) {
        print('⚠️ Widget unmounted, skipping UI update');
        return;
      }

      setState(() {
        _isTransmitting = false;
        _transmitError = null;
      });

      print(
          '✅ Showing success dialog for amount: ₱${transmittedAmount.toStringAsFixed(2)}');

      // Show success dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transmit Request Submitted'),
          content: Text(
            'Your transmit request for ₱${transmittedAmount.toStringAsFixed(2)} has been submitted and is pending admin confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Transmit request failed!');
      print('❌ Error: $e');
      print('❌ Stack trace: $stackTrace');

      if (!mounted) return;

      setState(() {
        _isTransmitting = false;
        _transmitError = 'Failed to submit transmit request: ${e.toString()}';
      });

      // Also show a snackbar for immediate feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit transmit request: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _updateTransactionStatus(
      String docId, String currentStatus) async {
    if (_updatingTransactions.contains(docId)) return;

    setState(() {
      _updatingTransactions.add(docId);
    });

    try {
      final newStatus = currentStatus == 'pending' ? 'requested' : 'pending';

      await FirebaseFirestore.instance.collection('wallet').doc(docId).update({
        'status': newStatus,
        'statusUpdatedAt': Timestamp.fromDate(DateTime.now()),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $newStatus'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingTransactions.remove(docId);
        });
      }
    }
  }

  /// Check if error is retryable (network/timeout/unavailable issues)
  bool _isRetryableFirestoreError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    final errorCode = error is FirebaseException ? error.code : '';
    return errorStr.contains('network') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('unavailable') ||
        errorStr.contains('deadline exceeded') ||
        errorCode == 'unavailable' ||
        errorCode == 'deadline-exceeded';
  }

  /// Retry function with exponential backoff for Firestore operations
  Future<T> _retryFirestoreOperation<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts || !_isRetryableFirestoreError(e)) {
          rethrow;
        }

        // Update retry attempt
        if (mounted) {
          setState(() {
            _payoutRetryAttempt = attempt;
          });
        }

        print(
            '🔄 Retrying payout request (attempt $attempt/$maxAttempts) after ${delay.inSeconds}s...');

        // Wait before retry with exponential backoff
        await Future.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
    }

    throw Exception('Max retry attempts reached');
  }

  Future<void> _handlePayoutRequest() async {
    if (_isRequestingPayout) return;

    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _payoutError = 'User not logged in';
      });
      print('❌ Payout Error: User not logged in');
      return;
    }

    setState(() {
      _isRequestingPayout = true;
      _payoutError = null;
      _payoutRetryAttempt = 0;
    });

    print('🔵 Starting payout request for user: ${user.uid}');

    // Fetch current balance for validation
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!userDoc.exists) {
      setState(() {
        _payoutError = 'User document not found';
        _isRequestingPayout = false;
      });
      return;
    }

    // Count today's payout requests
    final payoutRequests = (userDoc.data()?['payoutRequests'] as List<dynamic>?) ?? [];
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    int todayRequestCount = 0;
    for (var request in payoutRequests) {
      final createdAt = (request['createdAt'] as Timestamp?)?.toDate();
      if (createdAt != null &&
          !createdAt.isBefore(startOfDay) &&
          createdAt.isBefore(endOfDay)) {
        todayRequestCount++;
      }
    }

    // Check if limit reached
    if (todayRequestCount >= 2) {
      setState(() {
        _payoutError = 'You have reached the daily limit of 2 payout requests. Please try again tomorrow.';
        _isRequestingPayout = false;
      });
      print('❌ Payout Error: Daily limit reached');
      return;
    }

    final currentBalance =
        ((userDoc.data()?['wallet_amount'] ?? 0.0) as num).toDouble();
    print('🔵 Current balance: $currentBalance');

    // Validate balance
    if (currentBalance <= 0) {
      setState(() {
        _payoutError = 'Earning wallet balance is zero or negative';
        _isRequestingPayout = false;
      });
      print('❌ Payout Error: Balance is zero or negative');
      return;
    }

    // Add minimum amount check
    if (currentBalance < 100) {
      setState(() {
        _payoutError = 'Minimum payout amount is ₱100.00. Your current balance is ₱${currentBalance.toStringAsFixed(2)}';
        _isRequestingPayout = false;
      });
      print('❌ Payout Error: Balance below minimum');
      return;
    }

    // Prevent duplicate: block if already has pending payout
    final hasPendingPayout = payoutRequests.any(
        (r) => (r['status'] as String? ?? '') == 'pending');
    if (hasPendingPayout) {
      setState(() {
        _payoutError =
            'You already have a pending payout request. Please wait for '
            'confirmation.';
        _isRequestingPayout = false;
      });
      print('❌ Payout Error: Pending request already exists');
      return;
    }

    double payoutAmount = 0.0;
    List<String> orderIds = [];

    try {
      // Wrap Firestore operations in retry logic
      await _retryFirestoreOperation(
        maxAttempts: 3,
        initialDelay: const Duration(seconds: 2),
        operation: () async {
          final userRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);

          print('🔵 Fetching user document...');

          // First verify the document exists
          final userDocCheck = await userRef.get();
          if (!userDocCheck.exists) {
            throw Exception('User document not found for UID: ${user.uid}');
          }

          print('✅ User document found');

          // Get all unpaid earning transactions to track order IDs
          print('🔵 Fetching unpaid earning transactions...');
          final unpaidEarnings = await FirebaseFirestore.instance
              .collection('wallet')
              .where('user_id', isEqualTo: user.uid)
              .where('walletType', isEqualTo: 'earning')
              .where('payment_status', isEqualTo: 'success')
              .get();

          // Collect order IDs from unpaid transactions
          orderIds = unpaidEarnings.docs
              .where((doc) {
                final data = doc.data();
                final isPaidOut = data['isPaidOut'] as bool? ?? false;
                final orderId = data['order_id'] as String? ?? '';
                return !isPaidOut && orderId.isNotEmpty;
              })
              .map((doc) => doc.data()['order_id'] as String)
              .toList();

          print('🔵 Found ${orderIds.length} unpaid orders to include in payout');

          String requestId = '';
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final userSnap = await tx.get(userRef);
            if (!userSnap.exists) {
              throw Exception('User document not found in transaction');
            }

            final userData = userSnap.data() ?? {};
            print('🔵 User data retrieved: ${userData.keys.toList()}');

            final currentEarning =
                ((userData['wallet_amount'] ?? 0.0) as num).toDouble();

            print('🔵 Current earning in transaction: $currentEarning');

            // Double-check balance hasn't changed
            if (currentEarning <= 0) {
              throw Exception('Earning wallet balance is zero or negative');
            }

            // Store amount for success message
            payoutAmount = currentEarning;

            // Get existing payout requests or initialize as empty array
            final List<dynamic> existingRequests =
                (userData['payoutRequests'] as List<dynamic>?) ?? [];

            print('🔵 Existing payout requests: ${existingRequests.length}');

            // Block duplicate: ensure no pending request in transaction
            final hasPending =
                existingRequests.any((r) => (r['status'] as String? ?? '') == 'pending');
            if (hasPending) {
              throw Exception('A payout request is already pending');
            }

            // Create new payout request with order IDs
            requestId = FirebaseFirestore.instance.collection('users').doc().id;
            final newRequest = {
              'id': requestId,
              'amount': currentEarning,
              'status': 'pending',
              'createdAt': Timestamp.fromDate(DateTime.now()),
              'type': 'earning_wallet_payout',
              'confirmedAt': null,
              'orderIds': orderIds, // Track which orders are included
            };

            print('🔵 New request ID: $requestId');
            print('🔵 New request amount: $currentEarning');
            print('🔵 Order IDs included: ${orderIds.length}');

            // Append new request to array
            final updatedRequests = [...existingRequests, newRequest];

            // Update user document with new payout request
            tx.update(userRef, {
              'payoutRequests': updatedRequests,
            });

            print('✅ Transaction update queued');
          });

          print('✅ Transaction committed successfully!');

          // Create a transaction entry in wallet collection
          final walletTransactionId =
              FirebaseFirestore.instance.collection('wallet').doc().id;
          await FirebaseFirestore.instance
              .collection('wallet')
              .doc(walletTransactionId)
              .set({
            'id': walletTransactionId,
            'user_id': user.uid,
            'amount': -payoutAmount, // Negative amount = money going out
            'date': Timestamp.fromDate(DateTime.now()),
            'note': 'Payout Request',
            'payment_method': 'Payout',
            'walletType': widget.walletType,
            'status': 'pending',
            'payoutRequestId': requestId, // Link to the payout request
            'isTopUp': false,
            'payment_status': 'pending',
            'transactionUser': 'driver',
            'order_id': '',
            'isPaidOut': false, // Track payout status
          });

          print('✅ Wallet transaction created: $walletTransactionId');
        },
      );

      // Success - show success message
      // Balance will update automatically via StreamBuilder
      if (!mounted) {
        print('⚠️ Widget unmounted, skipping UI update');
        return;
      }

      setState(() {
        _isRequestingPayout = false;
        _payoutError = null;
        _payoutRetryAttempt = 0;
      });

      print(
          '✅ Showing success dialog for amount: ₱${payoutAmount.toStringAsFixed(2)}');

      // Show success dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Payout Request Submitted'),
          content: Text(
            'Your payout request for ₱${payoutAmount.toStringAsFixed(2)} has been submitted and is pending admin confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Payout request failed!');
      print('❌ Error: $e');
      print('❌ Stack trace: $stackTrace');

      if (!mounted) return;

      final isRetryable = _isRetryableFirestoreError(e);
      final errorMessage = isRetryable && _payoutRetryAttempt > 0
          ? 'Service temporarily unavailable. Please try again in a moment.'
          : 'Failed to submit payout request: ${e.toString()}';

      setState(() {
        _isRequestingPayout = false;
        _payoutError = errorMessage;
        _payoutRetryAttempt = 0;
      });

      // Show a more user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Query<Map<String, dynamic>> _buildWalletQuery(String userId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    var query = FirebaseFirestore.instance
        .collection('wallet')
        .where('user_id', isEqualTo: userId)
        .where('walletType', isEqualTo: widget.walletType)
        .where('isPaidOut', isEqualTo: false);

    if (_showTodayOnly) {
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay));
    }

    return query.orderBy('date', descending: true);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _walletStream(String userId) {
    return _buildWalletQuery(userId).limit(_pageSize).snapshots();
  }

  Future<void> _loadMore(
    String userId,
    DocumentSnapshot<Map<String, dynamic>> lastDoc,
  ) async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snapshot = await _buildWalletQuery(userId)
          .startAfterDocument(lastDoc)
          .limit(_pageSize)
          .get();

      if (!mounted) return;
      setState(() {
        _loadedMoreDocs = [..._loadedMoreDocs, ...snapshot.docs];
        _hasMore = snapshot.docs.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Query<Map<String, dynamic>> _buildDeleteQuery(String userId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    var query = FirebaseFirestore.instance
        .collection('wallet')
        .where('user_id', isEqualTo: userId)
        .where('walletType', isEqualTo: widget.walletType);

    if (_showTodayOnly) {
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay));
    }
    return query;
  }

  Future<void> _deleteHistory(String userId) async {
    if (_isDeletingHistory) return;
    setState(() {
      _isDeletingHistory = true;
      _deleteHistoryError = null;
    });

    try {
      final query = _buildDeleteQuery(userId);
      // Delete in batches to respect Firestore limits
      const int batchSize = 400;
      while (true) {
        final snapshot = await query.limit(batchSize).get();
        if (snapshot.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (snapshot.docs.length < batchSize) break;
      }
    } catch (e) {
      setState(() {
        _deleteHistoryError = 'Failed to delete history: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingHistory = false;
          _loadedMoreDocs = [];
          _hasMore = true;
        });
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String userId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete transactions?'),
        content: Text(
          _showTodayOnly
              ? 'This will delete today\'s transactions.'
              : 'This will delete all transactions for this wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteHistory(userId);
    }
  }

  Widget _buildTransactionTile(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final amount = ((data['amount'] ?? 0.0) as num).toDouble();
    final orderId = data['order_id']?.toString() ?? '';
    final note = data['note']?.toString() ?? '';
    final paymentMethod = data['payment_method']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';
    final isUpdating = _updatingTransactions.contains(doc.id);

    final isPositive = amount > 0;
    final iconColor = isPositive ? Colors.green : Colors.red;
    final icon = isPositive ? Icons.add_circle : Icons.remove_circle;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: iconColor.withValues(alpha: 0.2),
                  child: Icon(
                    icon,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderId.isNotEmpty
                            ? 'Order ${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length)}'
                            : note.isNotEmpty
                                ? note
                                : paymentMethod.isNotEmpty
                                    ? paymentMethod
                                    : 'Transaction',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(date),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (note.isNotEmpty && orderId.isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${isPositive ? '+' : ''}₱${amount.abs().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'requested'
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: status == 'requested'
                          ? Colors.orange
                          : Colors.grey.shade400,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Status: ${status.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: status == 'requested'
                          ? Colors.orange.shade800
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
                if (status != 'confirmed')
                  ElevatedButton(
                    onPressed: isUpdating
                        ? null
                        : () => _updateTransactionStatus(doc.id, status),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(COLOR_PRIMARY),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      minimumSize: const Size(80, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: isUpdating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            status == 'pending' ? 'Request' : 'Undo',
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text('User not logged in'),
      );
    }

    final currentUser = MyAppState.currentUser;
    if (currentUser == null) {
      return const Center(
        child: Text('User not logged in'),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Force refresh by invalidating cache
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance Card with StreamBuilder for real-time updates
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _walletBalanceStream(user.uid),
              builder: (context, snapshot) {
                double currentBalance = 0.0;
                String? transmitStatus;
                String? payoutStatus;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() ?? {};
                  if (widget.walletType == 'credit') {
                    currentBalance =
                        ((data['wallet_credit'] ?? 0.0) as num).toDouble();
                    final transmitRequests =
                        (data['transmitRequests'] as List<dynamic>?) ?? [];
                    if (transmitRequests.isNotEmpty) {
                      final latestRequest =
                          transmitRequests.last as Map<String, dynamic>;
                      transmitStatus =
                          latestRequest['status']?.toString() ?? 'pending';
                    }
                  } else {
                    currentBalance =
                        ((data['wallet_amount'] ?? 0.0) as num).toDouble();
                    final payoutRequests =
                        (data['payoutRequests'] as List<dynamic>?) ?? [];
                    if (payoutRequests.isNotEmpty) {
                      final latestRequest =
                          payoutRequests.last as Map<String, dynamic>;
                      payoutStatus =
                          latestRequest['status']?.toString() ?? 'pending';
                    }
                  }
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.walletType == 'credit'
                          ? [Colors.blue.shade400, Colors.blue.shade600]
                          : [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Balance',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? const SizedBox(
                                    height: 32,
                                    width: 32,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    '₱${currentBalance.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          if (widget.walletType == 'credit')
                            ElevatedButton(
                              onPressed: (_isTransmitting ||
                                      transmitStatus == 'pending')
                                  ? null
                                  : _handleTransmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(COLOR_PRIMARY),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                disabledBackgroundColor:
                                    Color(COLOR_PRIMARY).withValues(alpha: 0.6),
                              ),
                              child: _isTransmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.send, size: 18),
                                        const SizedBox(width: 8),
                                        Text('Transmit'),
                                      ],
                                    ),
                            ),
                          if (widget.walletType == 'earning')
                            ElevatedButton(
                              onPressed: (_isRequestingPayout ||
                                      payoutStatus == 'pending')
                                  ? null
                                  : _handlePayoutRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(COLOR_PRIMARY),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                disabledBackgroundColor:
                                    Color(COLOR_PRIMARY).withValues(alpha: 0.6),
                              ),
                              child: _isRequestingPayout
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.payment, size: 18),
                                        const SizedBox(width: 8),
                                        Text('Request Payout'),
                                      ],
                                    ),
                            ),
                        ],
                      ),
                      // Status Display (Credit Wallet Only)
                      if (widget.walletType == 'credit' &&
                          transmitStatus != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: transmitStatus == 'confirmed'
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.amber.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: transmitStatus == 'confirmed'
                                  ? Colors.green.shade300
                                  : Colors.amber.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                transmitStatus == 'confirmed'
                                    ? Icons.check_circle
                                    : Icons.pending,
                                size: 18,
                                color: transmitStatus == 'confirmed'
                                    ? Colors.green.shade100
                                    : Colors.amber.shade100,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                transmitStatus == 'pending'
                                    ? 'Status: Pending'
                                    : 'Status: Confirmed',
                                style: TextStyle(
                                  color: transmitStatus == 'confirmed'
                                      ? Colors.green.shade100
                                      : Colors.amber.shade100,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Status Display (Earning Wallet Only)
                      if (widget.walletType == 'earning' &&
                          payoutStatus != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: payoutStatus == 'confirmed'
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.amber.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: payoutStatus == 'confirmed'
                                  ? Colors.green.shade300
                                  : Colors.amber.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                payoutStatus == 'confirmed'
                                    ? Icons.check_circle
                                    : Icons.pending,
                                size: 18,
                                color: payoutStatus == 'confirmed'
                                    ? Colors.green.shade100
                                    : Colors.amber.shade100,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                payoutStatus == 'pending'
                                    ? 'Status: Pending'
                                    : 'Status: Confirmed',
                                style: TextStyle(
                                  color: payoutStatus == 'confirmed'
                                      ? Colors.green.shade100
                                      : Colors.amber.shade100,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            // Error Display (Credit Wallet Only)
            if (widget.walletType == 'credit' && _transmitError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText.rich(
                  TextSpan(
                    text: _transmitError!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
            // Error Display (Earning Wallet Only)
            if (widget.walletType == 'earning' && _payoutError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText.rich(
                  TextSpan(
                    text: _payoutError!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Credit Wallet Button (Earning Wallet Only)
            if (widget.walletType == 'earning') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    push(
                      context,
                      Scaffold(
                        backgroundColor: isDarkMode(context)
                            ? Color(DARK_VIEWBG_COLOR)
                            : Colors.white,
                        appBar: AppBar(
                          title: const Text('Credit Wallet'),
                          backgroundColor: Color(COLOR_PRIMARY),
                          foregroundColor: Colors.white,
                        ),
                        body: const WalletDetailPage(walletType: 'credit'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Credit Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            // Today Only Toggle
            Card(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.white,
              child: SwitchListTile(
                title: Text("Show Today's Entries Only"),
                value: _showTodayOnly,
                onChanged: (value) {
                  setState(() {
                    _showTodayOnly = value;
                    _loadedMoreDocs = [];
                    _hasMore = true;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Transaction History',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    // Button to view today's pending transactions
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TodayTransactionsPage(
                              walletType: widget.walletType,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.receipt_long,
                        size: 16,
                      ),
                      label: const Text(
                        'Today',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                    ),
                    // Button to view paid transactions history
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaidTransactionsPage(
                              walletType: widget.walletType,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.history,
                        size: 16,
                      ),
                      label: const Text(
                        'Paid',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Color(COLOR_PRIMARY),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                    ),
                    if (_isDeletingHistory)
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Delete history',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: _isDeletingHistory
                          ? null
                          : () => _confirmDelete(context, user.uid),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Transaction List
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _walletStream(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final firstPageDocs = snapshot.data?.docs ?? [];
                final allDocs = [...firstPageDocs, ..._loadedMoreDocs];

                if (_deleteHistoryError != null) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SelectableText.rich(
                      TextSpan(
                        text: _deleteHistoryError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                if (allDocs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final lastDoc = _loadedMoreDocs.isNotEmpty
                    ? _loadedMoreDocs.last
                    : firstPageDocs.last;

                return Column(
                  children: [
                    // Summary Card
                    Card(
                      color: isDarkMode(context)
                          ? Color(DARK_CARD_BG_COLOR)
                          : Colors.grey.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Total Transactions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${allDocs.length}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Transaction List
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: allDocs.length,
                      itemBuilder: (context, index) {
                        return _buildTransactionTile(allDocs[index]);
                      },
                    ),
                    if (_hasMore && _isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_hasMore && !_isLoadingMore)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextButton.icon(
                          onPressed: () => _loadMore(user.uid, lastDoc),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Load more'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
