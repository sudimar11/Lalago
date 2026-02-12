import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class PayoutRemittancePage extends StatefulWidget {
  const PayoutRemittancePage({super.key});

  @override
  State<PayoutRemittancePage> createState() => _PayoutRemittancePageState();
}

class _PayoutRemittancePageState extends State<PayoutRemittancePage> {
  final Set<String> _processingIds = {}; // Track processing operations by userId_action
  bool _isRefreshing = false;
  final Map<String, String> _processingStatus = {};
  final Map<String, int> _processingProgress = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payout & Remittance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.indigo,
                    Colors.indigo.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Colors.indigo,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payout & Remittance',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage driver wallets',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Table Header
            Container(
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.withOpacity(0.3)),
              ),
              child: Table(
                columnWidths: {
                  0: const FlexColumnWidth(0.6), // No.
                  1: const FlexColumnWidth(2.5), // Driver Name
                  2: const FlexColumnWidth(1.8), // Earning Wallet
                  3: const FlexColumnWidth(1.8), // Credit Wallet
                  4: const FlexColumnWidth(2.5), // Actions
                },
                children: const [
                  TableRow(
                    children: [
                      _HeaderCell('No.'),
                      _HeaderCell('Driver Name'),
                      _HeaderCell('Earning Wallet'),
                      _HeaderCell('Credit Wallet'),
                      _HeaderCell('Actions'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Drivers List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(USERS)
                    .where('role', isEqualTo: USER_ROLE_DRIVER)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading drivers: ${snapshot.error}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  final drivers = snapshot.data?.docs ?? [];

                  if (drivers.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refreshData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No drivers found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshData,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.indigo.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        itemCount: drivers.length,
                        itemBuilder: (context, index) {
                          final driverDoc = drivers[index];
                          final data = driverDoc.data() as Map<String, dynamic>;
                          final userId = driverDoc.id;
                          final driverName =
                              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                  .trim();
                          final earningBalance =
                              ((data['wallet_amount'] ?? 0.0) as num)
                                  .toDouble();
                          final creditBalance =
                              ((data['wallet_credit'] ?? 0.0) as num)
                                  .toDouble();

                          final remitKey = '${userId}_remit';
                          final payoutKey = '${userId}_payout';
                          final isRemitting = _processingIds.contains(remitKey);
                          final isPayingOut = _processingIds.contains(payoutKey);
                          final remitStatus = _processingStatus[remitKey];
                          final payoutStatus = _processingStatus[payoutKey];
                          final remitProgress = _processingProgress[remitKey];
                          final payoutProgress = _processingProgress[payoutKey];

                          return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.indigo.withOpacity(0.1),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Table(
                              columnWidths: {
                                0: const FlexColumnWidth(0.6), // No.
                                1: const FlexColumnWidth(2.5), // Driver Name
                                2: const FlexColumnWidth(1.8), // Earning Wallet
                                3: const FlexColumnWidth(1.8), // Credit Wallet
                                4: const FlexColumnWidth(2.5), // Actions
                              },
                              children: [
                                TableRow(
                                  children: [
                                    _DataCell('${index + 1}'),
                                    _DataCell(driverName.isEmpty ? 'Unknown' : driverName),
                                    _DataCell(
                                      '₱${earningBalance.toStringAsFixed(2)}',
                                      color: earningBalance > 0
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                    _DataCell(
                                      '₱${creditBalance.toStringAsFixed(2)}',
                                      color: creditBalance > 0
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    _ActionsCell(
                                      earningBalance: earningBalance,
                                      creditBalance: creditBalance,
                                      onRemit: isRemitting || isPayingOut
                                          ? null
                                          : () => _handleRemittance(userId, creditBalance),
                                      onPayout: isRemitting || isPayingOut
                                          ? null
                                          : () => _handlePayout(userId, earningBalance),
                                      isRemitting: isRemitting,
                                      isPayingOut: isPayingOut,
                                      remitStatus: remitStatus,
                                      payoutStatus: payoutStatus,
                                      remitProgress: remitProgress,
                                      payoutProgress: payoutProgress,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _handleRemittance(String userId, double currentBalance) async {
    // Validate balance
    if (currentBalance <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credit wallet balance is zero or negative'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Remittance'),
        content: Text(
          'Process remittance of ₱${currentBalance.toStringAsFixed(2)} from credit wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final processKey = '${userId}_remit';

    setState(() {
      _processingIds.add(processKey);
      _processingStatus[processKey] = 'Starting...';
      _processingProgress[processKey] = 0;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection(USERS).doc(userId);

      setState(() {
        _processingStatus[processKey] = 'Fetching transactions...';
        _processingProgress[processKey] = 20;
      });

      // Get all unpaid credit transactions to track order IDs
      final unpaidCredits = await firestore
          .collection('wallet')
          .where('user_id', isEqualTo: userId)
          .where('walletType', isEqualTo: 'credit')
          .where('payment_status', isEqualTo: 'success')
          .where('isPaidOut', isEqualTo: false)
          .get();

      // Collect order IDs from unpaid transactions
      final orderIds = unpaidCredits.docs
          .where((doc) {
            final data = doc.data();
            final orderId = data['order_id'] as String? ?? '';
            return orderId.isNotEmpty;
          })
          .map((doc) => doc.data()['order_id'] as String)
          .toList();

      setState(() {
        _processingStatus[processKey] = 'Processing wallet...';
        _processingProgress[processKey] = 40;
      });

      String requestId = '';

      await firestore.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User not found');
        }

        final userData = userSnap.data() as Map<String, dynamic>;
        final walletCredit =
            ((userData['wallet_credit'] ?? 0.0) as num).toDouble();

        // Validate balance again in transaction
        if (walletCredit <= 0) {
          throw Exception('Credit wallet balance is zero or negative');
        }

        if (walletCredit != currentBalance) {
          throw Exception(
              'Balance changed. Current: ₱${walletCredit.toStringAsFixed(2)}, Expected: ₱${currentBalance.toStringAsFixed(2)}');
        }

        // Get existing transmit requests or initialize as empty array
        final List<dynamic> existingRequests =
            (userData['transmitRequests'] as List<dynamic>?) ?? [];

        // Create new transmit request with status confirmed immediately
        requestId = firestore.collection('users').doc().id;
        final newRequest = {
          'id': requestId,
          'amount': walletCredit,
          'status': 'confirmed',
          'createdAt': Timestamp.now(),
          'confirmedAt': Timestamp.now(),
          'type': 'credit_wallet_transmit',
          'orderIds': orderIds,
        };

        // Append new request to array
        final updatedRequests = [...existingRequests, newRequest];

        // Update user document: set credit wallet to 0 and add request
        transaction.update(userRef, {
          'transmitRequests': updatedRequests,
          'wallet_credit': 0.0,
        });
      });

      setState(() {
        _processingStatus[processKey] = 'Creating transaction record...';
        _processingProgress[processKey] = 60;
      });

      // Create wallet transaction entry
      final walletTransactionId =
          firestore.collection('wallet').doc().id;
      await firestore.collection('wallet').doc(walletTransactionId).set({
        'id': walletTransactionId,
        'user_id': userId,
        'amount': -currentBalance, // Negative amount = money going out
        'date': Timestamp.now(),
        'note': 'Admin Remittance',
        'payment_method': 'Transmit',
        'walletType': 'credit',
        'status': 'confirmed',
        'payment_status': 'success',
        'transmitRequestId': requestId,
        'isTopUp': false,
        'transactionUser': 'driver',
        'order_id': '',
        'isPaidOut': false,
        'confirmedAt': Timestamp.now(),
      });

      setState(() {
        _processingStatus[processKey] = 'Updating transactions...';
        _processingProgress[processKey] = 80;
      });

      // Mark related wallet transactions as paid out
      if (orderIds.isNotEmpty) {
        await _updateWalletDocumentsForRemittance(userId, requestId, orderIds);
      }

      setState(() {
        _processingStatus[processKey] = 'Complete!';
        _processingProgress[processKey] = 100;
      });

      // Wait a moment to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Success'),
              ],
            ),
            content: Text(
                'Remittance of ₱${currentBalance.toStringAsFixed(2)} processed successfully!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Remittance error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _processingStatus[processKey] = 'Error!';
        });

        String errorMessage = 'Failed to process remittance';
        if (e.toString().contains('PERMISSION_DENIED')) {
          errorMessage =
              'Permission denied. Please check Firestore security rules.';
        } else {
          errorMessage = 'Failed to process remittance: ${e.toString()}';
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Text('Error'),
              ],
            ),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _processingIds.remove(processKey);
              _processingStatus.remove(processKey);
              _processingProgress.remove(processKey);
            });
          }
        });
      }
    }
  }

  Future<void> _handlePayout(String userId, double currentBalance) async {
    // Validate balance
    if (currentBalance <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Earning wallet balance is zero or negative'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payout'),
        content: Text(
          'Process payout of ₱${currentBalance.toStringAsFixed(2)} from earning wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final processKey = '${userId}_payout';

    setState(() {
      _processingIds.add(processKey);
      _processingStatus[processKey] = 'Starting...';
      _processingProgress[processKey] = 0;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection(USERS).doc(userId);

      setState(() {
        _processingStatus[processKey] = 'Fetching transactions...';
        _processingProgress[processKey] = 20;
      });

      // Get all unpaid earning transactions to track order IDs
      final unpaidEarnings = await firestore
          .collection('wallet')
          .where('user_id', isEqualTo: userId)
          .where('walletType', isEqualTo: 'earning')
          .where('payment_status', isEqualTo: 'success')
          .where('isPaidOut', isEqualTo: false)
          .get();

      // Collect order IDs from unpaid transactions
      final orderIds = unpaidEarnings.docs
          .where((doc) {
            final data = doc.data();
            final orderId = data['order_id'] as String? ?? '';
            return orderId.isNotEmpty;
          })
          .map((doc) => doc.data()['order_id'] as String)
          .toList();

      setState(() {
        _processingStatus[processKey] = 'Processing wallet...';
        _processingProgress[processKey] = 40;
      });

      String requestId = '';

      await firestore.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User not found');
        }

        final userData = userSnap.data() as Map<String, dynamic>;
        final walletAmount =
            ((userData['wallet_amount'] ?? 0.0) as num).toDouble();

        // Validate balance again in transaction
        if (walletAmount <= 0) {
          throw Exception('Earning wallet balance is zero or negative');
        }

        if (walletAmount != currentBalance) {
          throw Exception(
              'Balance changed. Current: ₱${walletAmount.toStringAsFixed(2)}, Expected: ₱${currentBalance.toStringAsFixed(2)}');
        }

        // Get existing payout requests or initialize as empty array
        final List<dynamic> existingRequests =
            (userData['payoutRequests'] as List<dynamic>?) ?? [];

        // Create new payout request with status confirmed immediately
        requestId = firestore.collection('users').doc().id;
        final newRequest = {
          'id': requestId,
          'amount': walletAmount,
          'status': 'confirmed',
          'createdAt': Timestamp.now(),
          'confirmedAt': Timestamp.now(),
          'type': 'earning_wallet_payout',
          'orderIds': orderIds,
        };

        // Append new request to array
        final updatedRequests = [...existingRequests, newRequest];

        // Update user document: set wallet_amount to 0 and add request
        transaction.update(userRef, {
          'payoutRequests': updatedRequests,
          'wallet_amount': 0.0,
        });
      });

      setState(() {
        _processingStatus[processKey] = 'Creating transaction record...';
        _processingProgress[processKey] = 60;
      });

      // Create wallet transaction entry
      final walletTransactionId = firestore.collection('wallet').doc().id;
      await firestore.collection('wallet').doc(walletTransactionId).set({
        'id': walletTransactionId,
        'user_id': userId,
        'amount': -currentBalance, // Negative amount = money going out
        'date': Timestamp.now(),
        'note': 'Admin Payout',
        'payment_method': 'Payout',
        'walletType': 'earning',
        'status': 'confirmed',
        'payment_status': 'success',
        'payoutRequestId': requestId,
        'isTopUp': false,
        'transactionUser': 'driver',
        'order_id': '',
        'isPaidOut': false,
        'confirmedAt': Timestamp.now(),
      });

      setState(() {
        _processingStatus[processKey] = 'Updating transactions...';
        _processingProgress[processKey] = 80;
      });

      // Mark related wallet transactions as paid out
      if (orderIds.isNotEmpty) {
        await _updateWalletDocumentsForPayout(userId, requestId, orderIds);
      }

      setState(() {
        _processingStatus[processKey] = 'Complete!';
        _processingProgress[processKey] = 100;
      });

      // Wait a moment to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Success'),
              ],
            ),
            content: Text(
                'Payout of ₱${currentBalance.toStringAsFixed(2)} processed successfully!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Payout error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _processingStatus[processKey] = 'Error!';
        });

        String errorMessage = 'Failed to process payout';
        if (e.toString().contains('PERMISSION_DENIED')) {
          errorMessage =
              'Permission denied. Please check Firestore security rules.';
        } else {
          errorMessage = 'Failed to process payout: ${e.toString()}';
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Text('Error'),
              ],
            ),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _processingIds.remove(processKey);
              _processingStatus.remove(processKey);
              _processingProgress.remove(processKey);
            });
          }
        });
      }
    }
  }

  Future<void> _updateWalletDocumentsForRemittance(
    String userId,
    String requestId,
    List<String> orderIds,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Firestore whereIn limit is 10, so we need to split into chunks
      const int chunkSize = 10;
      final List<List<String>> orderIdChunks = [];
      for (int i = 0; i < orderIds.length; i += chunkSize) {
        orderIdChunks.add(
          orderIds.sublist(
            i,
            i + chunkSize > orderIds.length ? orderIds.length : i + chunkSize,
          ),
        );
      }

      // Process each chunk
      for (final chunk in orderIdChunks) {
        // Query wallet documents by order_id and user_id
        final walletQuery = await firestore
            .collection('wallet')
            .where('order_id', whereIn: chunk)
            .where('user_id', isEqualTo: userId)
            .where('walletType', isEqualTo: 'credit')
            .get();

        if (walletQuery.docs.isEmpty) {
          debugPrint(
            'No wallet documents found for orderIds: ${chunk.join(", ")}',
          );
          continue;
        }

        // Batch update wallet documents
        // Firestore batch limit is 500 operations
        var batch = firestore.batch();
        int batchCount = 0;

        for (var walletDoc in walletQuery.docs) {
          final walletRef = firestore.collection('wallet').doc(walletDoc.id);
          batch.update(walletRef, {
            'isPaidOut': true,
            'paidOutAt': Timestamp.now(),
            'paidOutRequestId': requestId,
          });
          batchCount++;

          // Commit batch if we reach the limit
          if (batchCount >= 500) {
            await batch.commit();
            batch = firestore.batch();
            batchCount = 0;
          }
        }

        // Commit remaining operations in the batch
        if (batchCount > 0) {
          await batch.commit();
        }

        debugPrint(
          'Marked ${walletQuery.docs.length} credit transactions as paid out for remittance request $requestId',
        );
      }

      // Also update the remittance request transaction itself
      final remittanceTransactionQuery = await firestore
          .collection('wallet')
          .where('transmitRequestId', isEqualTo: requestId)
          .where('user_id', isEqualTo: userId)
          .where('payment_method', isEqualTo: 'Transmit')
          .limit(1)
          .get();

      if (remittanceTransactionQuery.docs.isNotEmpty) {
        await firestore
            .collection('wallet')
            .doc(remittanceTransactionQuery.docs.first.id)
            .update({
          'isPaidOut': true,
          'paidOutAt': Timestamp.now(),
          'paidOutRequestId': requestId,
        });
        debugPrint('Updated remittance request transaction as paid out');
      }
    } catch (e, stackTrace) {
      debugPrint('Error updating wallet documents: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _updateWalletDocumentsForPayout(
    String userId,
    String requestId,
    List<String> orderIds,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Firestore whereIn limit is 10, so we need to split into chunks
      const int chunkSize = 10;
      final List<List<String>> orderIdChunks = [];
      for (int i = 0; i < orderIds.length; i += chunkSize) {
        orderIdChunks.add(
          orderIds.sublist(
            i,
            i + chunkSize > orderIds.length ? orderIds.length : i + chunkSize,
          ),
        );
      }

      // Process each chunk
      for (final chunk in orderIdChunks) {
        // Query wallet documents by order_id and user_id
        final walletQuery = await firestore
            .collection('wallet')
            .where('order_id', whereIn: chunk)
            .where('user_id', isEqualTo: userId)
            .where('walletType', isEqualTo: 'earning')
            .get();

        if (walletQuery.docs.isEmpty) {
          debugPrint(
            'No wallet documents found for orderIds: ${chunk.join(", ")}',
          );
          continue;
        }

        // Batch update wallet documents
        // Firestore batch limit is 500 operations
        var batch = firestore.batch();
        int batchCount = 0;

        for (var walletDoc in walletQuery.docs) {
          final walletRef = firestore.collection('wallet').doc(walletDoc.id);
          batch.update(walletRef, {
            'isPaidOut': true,
            'paidOutAt': Timestamp.now(),
            'paidOutRequestId': requestId,
          });
          batchCount++;

          // Commit batch if we reach the limit
          if (batchCount >= 500) {
            await batch.commit();
            batch = firestore.batch();
            batchCount = 0;
          }
        }

        // Commit remaining operations in the batch
        if (batchCount > 0) {
          await batch.commit();
        }

        debugPrint(
          'Marked ${walletQuery.docs.length} earning transactions as paid out for payout request $requestId',
        );
      }

      // Also update the payout request transaction itself
      final payoutTransactionQuery = await firestore
          .collection('wallet')
          .where('payoutRequestId', isEqualTo: requestId)
          .where('user_id', isEqualTo: userId)
          .where('payment_method', isEqualTo: 'Payout')
          .limit(1)
          .get();

      if (payoutTransactionQuery.docs.isNotEmpty) {
        await firestore
            .collection('wallet')
            .doc(payoutTransactionQuery.docs.first.id)
            .update({
          'isPaidOut': true,
          'paidOutAt': Timestamp.now(),
          'paidOutRequestId': requestId,
        });
        debugPrint('Updated payout request transaction as paid out');
      }
    } catch (e, stackTrace) {
      debugPrint('Error updating wallet documents: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.black87,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final Color? color;

  const _DataCell(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text.isEmpty ? '-' : text,
        style: TextStyle(
          fontSize: 11,
          color: color ?? (text.isEmpty ? Colors.grey : Colors.black87),
          fontWeight: color != null ? FontWeight.w600 : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

class _ActionsCell extends StatelessWidget {
  final double earningBalance;
  final double creditBalance;
  final VoidCallback? onRemit;
  final VoidCallback? onPayout;
  final bool isRemitting;
  final bool isPayingOut;
  final String? remitStatus;
  final String? payoutStatus;
  final int? remitProgress;
  final int? payoutProgress;

  const _ActionsCell({
    required this.earningBalance,
    required this.creditBalance,
    required this.onRemit,
    required this.onPayout,
    required this.isRemitting,
    required this.isPayingOut,
    required this.remitStatus,
    required this.payoutStatus,
    required this.remitProgress,
    required this.payoutProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Remit Button
          Expanded(
            child: isRemitting
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      if (remitStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          remitStatus!,
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  )
                : ElevatedButton(
                    onPressed: creditBalance > 0 ? onRemit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: const Text(
                      'Remit',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          // Payout Button
          Expanded(
            child: isPayingOut
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      if (payoutStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          payoutStatus!,
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  )
                : ElevatedButton(
                    onPressed: earningBalance > 0 ? onPayout : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: const Text(
                      'Payout',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
