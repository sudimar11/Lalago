import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class RemittancePage extends StatefulWidget {
  const RemittancePage({super.key});

  @override
  State<RemittancePage> createState() => _RemittancePageState();
}

class _RemittancePageState extends State<RemittancePage> {
  final Set<String> _confirmingIds = {};
  final Set<String> _deletingIds = {};
  bool _isRefreshing = false;
  final Map<String, String> _confirmingStatus = {}; // Track status message
  final Map<String, int> _confirmingProgress = {}; // Track progress percentage

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remittance'),
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
                    Colors.black,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
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
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remittance Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pending requests',
                        style: TextStyle(
                          color: Colors.grey,
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
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Table(
                columnWidths: {
                  0: const FlexColumnWidth(0.8), // No.
                  1: const FlexColumnWidth(2.5), // Driver Name
                  2: const FlexColumnWidth(1.8), // Amount
                  3: const FlexColumnWidth(2.0), // Date
                  4: const FlexColumnWidth(1.2), // Status
                  5: const FlexColumnWidth(2.2), // Action
                },
                children: const [
                  TableRow(
                    children: [
                      _HeaderCell('No.'),
                      _HeaderCell('Driver Name'),
                      _HeaderCell('Amount'),
                      _HeaderCell('Date'),
                      _HeaderCell('Status'),
                      _HeaderCell('Action'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Remittance Requests List
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
                            'Error loading requests: ${snapshot.error}',
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

                  // Collect all pending remittance requests
                  final List<RemittanceRequest> requests = [];
                  for (var doc in snapshot.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final transmitRequestsRaw = data['transmitRequests'];

                    // Debug: Print what we're getting
                    print(
                        '🔍 Driver: ${data['firstName']} ${data['lastName']}');
                    print(
                        '🔍 transmitRequests type: ${transmitRequestsRaw.runtimeType}');
                    print('🔍 transmitRequests value: $transmitRequestsRaw');

                    // Handle both array and object/map formats
                    List<dynamic> transmitRequests = [];
                    if (transmitRequestsRaw is List) {
                      // It's already an array
                      transmitRequests = transmitRequestsRaw;
                      print(
                          '🔍 Processed as List, count: ${transmitRequests.length}');
                    } else if (transmitRequestsRaw is Map) {
                      // It's an object/map - convert to list of values
                      transmitRequests = transmitRequestsRaw.values.toList();
                      print(
                          '🔍 Processed as Map, keys: ${(transmitRequestsRaw as Map).keys.toList()}');
                      print(
                          '🔍 Converted to List, count: ${transmitRequests.length}');
                    }

                    for (var requestData in transmitRequests) {
                      if (requestData is Map<String, dynamic>) {
                        final status = requestData['status'] as String? ?? '';
                        final type = requestData['type'] as String? ?? '';
                        final amount =
                            (requestData['amount'] as num?)?.toDouble() ?? 0.0;
                        final requestId = requestData['id'] as String? ?? '';

                        print(
                            '🔍 Found request - ID: $requestId, Amount: $amount, Status: $status, Type: $type');

                        if (status == 'pending' &&
                            type == 'credit_wallet_transmit') {
                          requests.add(RemittanceRequest(
                            userId: doc.id,
                            requestId: requestId,
                            driverName:
                                '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                    .trim(),
                            amount: amount,
                            createdAt: requestData['createdAt'] as Timestamp?,
                          ));
                          print('✅ Added to requests list');
                        }
                      }
                    }
                  }

                  print('🔍 Total requests collected: ${requests.length}');

                  // Sort by date (newest first)
                  requests.sort((a, b) {
                    if (a.createdAt == null && b.createdAt == null) return 0;
                    if (a.createdAt == null) return 1;
                    if (b.createdAt == null) return -1;
                    return b.createdAt!.compareTo(a.createdAt!);
                  });

                  if (requests.isEmpty) {
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
                                  Icons.account_balance_wallet_outlined,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No pending remittance requests',
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
                          color: Colors.orange.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          final confirmKey =
                              '${request.userId}_${request.requestId}';
                          final isConfirming =
                              _confirmingIds.contains(confirmKey);
                          final isDeleting =
                              _deletingIds.contains(confirmKey);
                          final status = _confirmingStatus[confirmKey];
                          final progress = _confirmingProgress[confirmKey];

                          return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.orange.withOpacity(0.1),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Table(
                              columnWidths: {
                                0: const FlexColumnWidth(0.8), // No.
                                1: const FlexColumnWidth(2.5), // Driver Name
                                2: const FlexColumnWidth(1.8), // Amount
                                3: const FlexColumnWidth(2.0), // Date
                                4: const FlexColumnWidth(1.2), // Status
                                5: const FlexColumnWidth(1.5), // Action
                              },
                              children: [
                                TableRow(
                                  children: [
                                    _DataCell('${index + 1}'),
                                    _DataCell(request.driverName),
                                    _DataCell(
                                      '₱${request.amount.toStringAsFixed(2)}',
                                    ),
                                    _DataCell(_formatDate(request.createdAt)),
                                    _DataCell(
                                      'Pending',
                                      color: Colors.orange,
                                    ),
                                    _ActionCell(
                                      onConfirm: isConfirming || isDeleting
                                          ? null
                                          : () => _confirmRemittance(
                                                request.userId,
                                                request.requestId,
                                                request.amount,
                                              ),
                                      onDelete: isConfirming || isDeleting
                                          ? null
                                          : () => _deleteRemittanceRequest(
                                                request.userId,
                                                request.requestId,
                                              ),
                                      isConfirming: isConfirming,
                                      isDeleting: isDeleting,
                                      status: status,
                                      progress: progress,
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

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteRemittanceRequest(String userId, String requestId) async {
    final confirmKey = '${userId}_$requestId';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete remittance request?'),
        content: const Text(
          'This will remove the pending request. The driver\'s credit '
          'balance will not change. They can submit a new request later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _deletingIds.add(confirmKey);
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection(USERS).doc(userId);

      await firestore.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User not found');
        }

        final userData = userSnap.data() as Map<String, dynamic>;
        final transmitRequests =
            (userData['transmitRequests'] as List<dynamic>?) ?? [];

        final List<dynamic> updatedRequests = transmitRequests
            .where((req) {
              if (req is Map<String, dynamic>) {
                final reqId = req['id'] as String? ?? '';
                return reqId != requestId;
              }
              return true;
            })
            .toList();

        transaction.update(userRef, {'transmitRequests': updatedRequests});
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remittance request deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingIds.remove(confirmKey);
        });
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    // Wait a bit for Firestore to sync
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _confirmRemittance(
    String userId,
    String requestId,
    double amount,
  ) async {
    final confirmKey = '${userId}_$requestId';

    setState(() {
      _confirmingIds.add(confirmKey);
      _confirmingStatus[confirmKey] = 'Starting...';
      _confirmingProgress[confirmKey] = 0;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection(USERS).doc(userId);

      // Update status: Processing user wallet
      setState(() {
        _confirmingStatus[confirmKey] = 'Processing wallet...';
        _confirmingProgress[confirmKey] = 20;
      });

      await firestore.runTransaction((transaction) async{
        // Read user document
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User not found');
        }

        final userData = userSnap.data() as Map<String, dynamic>;
        final transmitRequests =
            (userData['transmitRequests'] as List<dynamic>?) ?? [];
        final walletCredit =
            (userData['wallet_credit'] as num?)?.toDouble() ?? 0.0;

        // Find and update the specific request
        bool found = false;
        final List<dynamic> updatedRequests = [];

        for (var req in transmitRequests) {
          if (req is Map<String, dynamic>) {
            final reqId = req['id'] as String? ?? '';
            if (reqId == requestId) {
              found = true;
              // Create a new map preserving all original fields
              final Map<String, dynamic> updatedReq =
                  Map<String, dynamic>.from(req);
              updatedReq['status'] = 'confirmed';
              updatedReq['confirmedAt'] = Timestamp.now();
              updatedRequests.add(updatedReq);
            } else {
              updatedRequests.add(req);
            }
          } else {
            updatedRequests.add(req);
          }
        }

        if (!found) {
          throw Exception('Remittance request not found');
        }

        // Check if wallet has sufficient balance
        if (walletCredit < amount) {
          throw Exception(
            'Insufficient wallet credit. Available: ₱${walletCredit.toStringAsFixed(2)}, Required: ₱${amount.toStringAsFixed(2)}',
          );
        }

        // Calculate new wallet credit
        final newWalletCredit = walletCredit - amount;

        // Update user document
        transaction.update(userRef, {
          'transmitRequests': updatedRequests,
          'wallet_credit': newWalletCredit,
        });
      });

      // Update status: Updating transactions
      setState(() {
        _confirmingStatus[confirmKey] = 'Updating transactions...';
        _confirmingProgress[confirmKey] = 50;
      });

      // Update wallet collection documents after remittance confirmation
      try {
        // Fetch the confirmed remittance request to get orderIds
        final userDoc = await userRef.get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final transmitRequests =
              (userData['transmitRequests'] as List<dynamic>?) ?? [];

          // Find the confirmed request
          Map<String, dynamic>? confirmedRequest;
          for (var req in transmitRequests) {
            if (req is Map<String, dynamic>) {
              final reqId = req['id'] as String? ?? '';
              if (reqId == requestId) {
                confirmedRequest = req;
                break;
              }
            }
          }

          // Extract orderIds and update wallet documents
          if (confirmedRequest != null &&
              confirmedRequest['orderIds'] != null) {
            final orderIds = confirmedRequest['orderIds'] as List<dynamic>;
            if (orderIds.isNotEmpty) {
              // Update status with transaction count
              setState(() {
                _confirmingStatus[confirmKey] = 
                    'Updating ${orderIds.length} transactions...';
                _confirmingProgress[confirmKey] = 70;
              });

              await _updateWalletDocumentsForRemittance(
                userId,
                requestId,
                orderIds.cast<String>(),
              );
            }
          }
        }
      } catch (walletUpdateError) {
        // Log error but don't fail the remittance confirmation
        debugPrint(
          'Warning: Failed to update wallet documents: $walletUpdateError',
        );
      }

      // Update status: Finalizing
      setState(() {
        _confirmingStatus[confirmKey] = 'Finalizing...';
        _confirmingProgress[confirmKey] = 90;
      });

      // Small delay to show the finalizing status
      await Future.delayed(const Duration(milliseconds: 500));

      // Update status: Complete
      setState(() {
        _confirmingStatus[confirmKey] = 'Complete!';
        _confirmingProgress[confirmKey] = 100;
      });

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
            content: const Text('Remittance request confirmed successfully!'),
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
      if (mounted) {
        // Update status to show error
        setState(() {
          _confirmingStatus[confirmKey] = 'Error!';
        });

        // Log the full error for debugging
        debugPrint('Remittance confirmation error: $e');
        debugPrint('Stack trace: $stackTrace');

        String errorMessage = 'Failed to confirm request';
        if (e.toString().contains('PERMISSION_DENIED')) {
          errorMessage =
              'Permission denied. Please check Firestore security rules.';
        } else if (e.toString().contains('not found')) {
          errorMessage = e.toString();
        } else {
          errorMessage = 'Failed to confirm request: ${e.toString()}';
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
        // Clear status after a delay to show final status
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _confirmingIds.remove(confirmKey);
              _confirmingStatus.remove(confirmKey);
              _confirmingProgress.remove(confirmKey);
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
          'status': 'confirmed',
          'payment_status': 'success',
          'confirmedAt': Timestamp.now(),
        });
        debugPrint('Updated remittance request transaction status to confirmed');
      }
    } catch (e, stackTrace) {
      debugPrint('Error updating wallet documents: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}

class RemittanceRequest {
  final String userId;
  final String requestId;
  final String driverName;
  final double amount;
  final Timestamp? createdAt;

  RemittanceRequest({
    required this.userId,
    required this.requestId,
    required this.driverName,
    required this.amount,
    this.createdAt,
  });
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
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

class _ActionCell extends StatelessWidget {
  final VoidCallback? onConfirm;
  final VoidCallback? onDelete;
  final bool isConfirming;
  final bool isDeleting;
  final String? status;
  final int? progress;

  const _ActionCell({
    required this.onConfirm,
    this.onDelete,
    required this.isConfirming,
    this.isDeleting = false,
    this.status,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Center(
        child: isConfirming || isDeleting
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      status!,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$progress%',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
