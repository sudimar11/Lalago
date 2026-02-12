import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/services/sales_service.dart';
import 'package:brgy/utils/idempotency.dart';
import 'package:brgy/rider_wallet_page.dart';
import 'package:brgy/monthly_report_page.dart';
import 'dart:developer' as dev;

class SalesPage extends StatefulWidget {
  @override
  _SalesPageState createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  String _selectedDate = DateTime.now().toIso8601String().split('T')[0];
  Map<String, double> _dailySummary = {};
  List<Map<String, dynamic>> _todayTransactions = [];
  List<Map<String, dynamic>> _riders = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _pendingTxId; // reused across retries for idempotency

  @override
  void initState() {
    super.initState();
    _loadDailyData();
    _loadRiders();
  }

  Future<void> _loadDailyData() async {
    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection(DAILY_SUMMARIES)
          .doc(_selectedDate);

      final docSnap = await docRef.get();
      final data = docSnap.data() ?? {};

      final Map<String, double> summary = {
        'opening_balance': (data['opening_balance'] ?? 0).toDouble(),
        'wallet_topups': (data['wallet_topups'] ?? 0).toDouble(),
        'other_income': (data['other_income'] ?? 0).toDouble(),
        'credit_sales': (data['credit_sales'] ?? 0).toDouble(),
        'total_payments_received':
            (data['total_payments_received'] ?? 0).toDouble(),
        'total_expenses': (data['total_expenses'] ?? 0).toDouble(),
        'net_balance': (data['net_balance'] ?? 0).toDouble(),
        'closing_balance': (data['closing_balance'] ?? 0).toDouble(),
      };

      final txSnap = await docRef
          .collection('transactions')
          .orderBy('created_at', descending: true)
          .get();

      final transactions = txSnap.docs.map((d) {
        final t = d.data();
        final dynamic rawAmount = t['amount'];
        double parsedAmount = 0.0;
        if (rawAmount is num)
          parsedAmount = rawAmount.toDouble();
        else if (rawAmount is String)
          parsedAmount = double.tryParse(rawAmount) ?? 0.0;
        return {
          'id': d.id,
          'date': t['date'],
          'type': t['type'],
          'amount': parsedAmount,
          'description': t['description'] ?? '',
          'riderId': t['riderId'],
          'creditEntryId': t['creditEntryId'],
          'created_at': t['created_at'],
        };
      }).toList();

      setState(() {
        _dailySummary = summary;
        _todayTransactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
    }
  }

  Future<void> _loadRiders() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .where('active', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> firestoreRiders =
          querySnapshot.docs.map((doc) {
        final data = doc.data();
        final String firstName = (data['firstName'] ?? '').toString();
        final String lastName = (data['lastName'] ?? '').toString();
        final String safeFirstName =
            firstName.isNotEmpty ? firstName : 'Unknown';
        final dynamic rawWallet = data['wallet_amount'];
        double walletAmount = 0.0;
        if (rawWallet is num)
          walletAmount = rawWallet.toDouble();
        else if (rawWallet is String)
          walletAmount = double.tryParse(rawWallet) ?? 0.0;
        return {
          'id': doc.id,
          'firstName': safeFirstName,
          'lastName': lastName,
          'phoneNumber': (data['phoneNumber'] ?? '').toString(),
          'wallet_amount': walletAmount,
        };
      }).toList();

      firestoreRiders.sort((a, b) {
        final an = ('${a['firstName']} ${a['lastName']}')
            .toString()
            .trim()
            .toLowerCase();
        final bn = ('${b['firstName']} ${b['lastName']}')
            .toString()
            .trim()
            .toLowerCase();
        return an.compareTo(bn);
      });

      setState(() {
        _riders = firestoreRiders;
      });
    } catch (_) {
      setState(() {
        _riders = [];
      });
    }
  }

  Future<void> _submitTransaction(
    String type,
    double amount,
    String description, {
    String? riderId,
    String? creditEntryId,
  }) async {
    setState(() {
      _isSubmitting = true;
      _pendingTxId ??= newPendingTxId();
    });

    final String originalType = type;
    final String originalDate = _selectedDate;

    try {
      dev.log('AddTransaction pressed',
          name: 'Sales', error: null, stackTrace: null);
      dev.log(
          'txId=$_pendingTxId type=$originalType amount=$amount date=$originalDate riderId=$riderId',
          name: 'Sales');
      await SalesService.addTransactionAtomic(
        dateKey: originalDate,
        type: originalType,
        amount: amount,
        description: description,
        riderId: riderId,
        txId: _pendingTxId!,
        creditEntryId: creditEntryId,
      );

      await _loadDailyData();
      await _loadRiders();

      String successMessage;
      if (originalType == 'wallet_topup') {
        successMessage =
            'Transaction added and rider wallet updated successfully!';
      } else if (originalType == 'credit_payment') {
        successMessage = 'Credit payment processed successfully!';
      } else {
        successMessage = 'Transaction added successfully';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _isSubmitting = false;
        _pendingTxId = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save transaction: $e'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _retryTransaction(
              amount,
              description,
              originalType: originalType,
              originalRiderId: riderId,
              originalDate: originalDate,
              originalCreditEntryId: creditEntryId,
            ),
          ),
        ),
      );
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _showTransactionModal(String type) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    Map<String, dynamic>? selectedRider;
    bool isWalletTopup = type == 'wallet_topup';

    try {
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(_getTransactionTypeLabel(type)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isWalletTopup) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final rider = await _showRiderSelectionModal();
                        if (rider != null) {
                          setModalState(() {
                            selectedRider = rider;
                          });
                        }
                      },
                      icon: Icon(Icons.person_search, color: Colors.orange),
                      label: Text(
                        selectedRider == null
                            ? 'Select Rider'
                            : '${selectedRider!['firstName']} ${selectedRider!['lastName']}',
                        style: TextStyle(
                          color: selectedRider == null
                              ? Colors.grey[600]
                              : Colors.orange,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: selectedRider == null
                              ? Colors.grey[400]!
                              : Colors.orange,
                        ),
                      ),
                    ),
                    if (selectedRider != null) ...[
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.orange.withOpacity(0.2),
                              child: Text(
                                selectedRider!['firstName'][0].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${selectedRider!['firstName']} ${selectedRider!['lastName']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (selectedRider!['wallet_amount'] != null)
                                    Text(
                                      'Wallet: ₱${selectedRider!['wallet_amount'].toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close,
                                  size: 18, color: Colors.grey[600]),
                              onPressed: () {
                                setModalState(() {
                                  selectedRider = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (amountController.text.isEmpty ||
                      descriptionController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please fill all fields')),
                    );
                    return;
                  }

                  if (isWalletTopup && selectedRider == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('Please select a rider for wallet top-up')),
                    );
                    return;
                  }

                  final amount = double.tryParse(amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a valid amount')),
                    );
                    return;
                  }

                  String finalDescription = descriptionController.text;
                  if (isWalletTopup && selectedRider != null) {
                    final riderName =
                        '${selectedRider!['firstName']} ${selectedRider!['lastName']}';
                    finalDescription = '$finalDescription (Rider: $riderName)';
                  }

                  Navigator.pop(context);
                  _submitTransaction(
                    type,
                    amount,
                    finalDescription,
                    riderId: isWalletTopup && selectedRider != null
                        ? (selectedRider!['id'] as String?)
                        : null,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: Text('Submit', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Wait for dialog animation to complete before disposing
      await Future.delayed(Duration(milliseconds: 300));
      amountController.dispose();
      descriptionController.dispose();
    }
  }

  String _getTransactionTypeLabel(String type) {
    switch (type) {
      case 'wallet_topup':
        return 'Wallet Top-up';
      case 'other_income':
        return 'Other Income';
      case 'credit_sale':
        return 'Credit Sale';
      case 'credit_payment':
        return 'Payment (Bayad Utang)';
      case 'expense':
        return 'Expense';
      default:
        return type;
    }
  }

  Future<Map<String, dynamic>?> _showOutstandingDebtSelectionModal() async {
    try {
      final outstandingDebts = await SalesService.getOutstandingCreditEntries();

      if (outstandingDebts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No outstanding debts found'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }

      final selectedDebt = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select Outstanding Debt',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: outstandingDebts.length,
                    separatorBuilder: (context, index) => Divider(),
                    itemBuilder: (context, index) {
                      final debt = outstandingDebts[index];
                      final balance =
                          (debt['outstanding_balance'] ?? 0).toDouble();
                      final initial = (debt['initial_amount'] ?? 0).toDouble();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.withOpacity(0.1),
                          child: Icon(
                            Icons.credit_card,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          debt['description'] ?? 'No description',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date: ${debt['date'] ?? ''}'),
                            SizedBox(height: 4),
                            Text(
                              'Outstanding: ₱${balance.toStringAsFixed(2)} / ₱${initial.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.indigo[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.pop(context, debt);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      return selectedDebt;
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error loading outstanding debts';
        if (e.toString().contains('PERMISSION_DENIED') ||
            e.toString().contains('permission')) {
          errorMessage =
              'Permission denied. Please update Firestore security rules to allow read access to the credit_entries collection.';
        } else {
          errorMessage = 'Error loading outstanding debts: ${e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _showCreditPaymentModal() async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    Map<String, dynamic>? selectedDebt;

    try {
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text('Payment (Bayad Utang)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final debt = await _showOutstandingDebtSelectionModal();
                      if (debt != null) {
                        setModalState(() {
                          selectedDebt = debt;
                          descriptionController.text =
                              'Payment for: ${debt['description'] ?? ''}';
                        });
                      }
                    },
                    icon: Icon(Icons.credit_card, color: Colors.indigo),
                    label: Text(
                      selectedDebt == null
                          ? 'Select Outstanding Debt'
                          : '₱${(selectedDebt!['outstanding_balance'] ?? 0).toStringAsFixed(2)} - ${selectedDebt!['description'] ?? ''}',
                      style: TextStyle(
                        color: selectedDebt == null
                            ? Colors.grey[600]
                            : Colors.indigo,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: selectedDebt == null
                            ? Colors.grey[400]!
                            : Colors.indigo,
                      ),
                    ),
                  ),
                  if (selectedDebt != null) ...[
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.indigo.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.indigo, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Outstanding Balance',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            '₱${(selectedDebt!['outstanding_balance'] ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Payment Amount',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                      helperText: selectedDebt != null
                          ? 'Max: ₱${(selectedDebt!['outstanding_balance'] ?? 0).toStringAsFixed(2)}'
                          : null,
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedDebt == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please select an outstanding debt'),
                      ),
                    );
                    return;
                  }

                  if (amountController.text.isEmpty ||
                      descriptionController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please fill all fields')),
                    );
                    return;
                  }

                  final amount = double.tryParse(amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a valid amount')),
                    );
                    return;
                  }

                  final outstandingBalance =
                      (selectedDebt!['outstanding_balance'] ?? 0).toDouble();
                  if (amount > outstandingBalance) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Payment amount cannot exceed outstanding balance'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  _submitTransaction(
                    'credit_payment',
                    amount,
                    descriptionController.text,
                    creditEntryId: selectedDebt!['id'] as String,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                ),
                child: Text('Submit Payment',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Wait for dialog animation to complete before disposing
      await Future.delayed(Duration(milliseconds: 300));
      amountController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _retryTransaction(double amount, String description,
      {String? originalType,
      String? originalRiderId,
      String? originalDate,
      String? originalCreditEntryId}) async {
    setState(() {
      _isSubmitting = true;
      _pendingTxId ??= newPendingTxId();
    });

    try {
      final String currentType = originalType ?? 'wallet_topup';
      final String? riderId = originalRiderId;
      final String dateKey = originalDate ?? _selectedDate;
      await SalesService.addTransactionAtomic(
        dateKey: dateKey,
        type: currentType,
        amount: amount,
        description: description,
        riderId: riderId,
        txId: _pendingTxId!,
        creditEntryId: originalCreditEntryId,
      );

      await _loadDailyData();
      await _loadRiders();

      final successMessage = currentType == 'wallet_topup'
          ? 'Transaction retry successful! Wallet and transaction updated.'
          : 'Transaction retry successful!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _isSubmitting = false;
        _pendingTxId = null; // clear after success
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked.toIso8601String().split('T')[0];
      });
      await _loadDailyData();
    }
  }

  Future<Map<String, dynamic>?> _showRiderSelectionModal() async {
    final selectedRider = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Text(
                'Select Rider',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              SizedBox(height: 16),

              // Search bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search riders...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (value) {
                  // TODO: Implement search functionality if needed
                },
              ),

              SizedBox(height: 16),

              // Riders list
              Expanded(
                child: _riders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No riders found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _riders.length,
                        separatorBuilder: (context, index) => Divider(),
                        itemBuilder: (context, index) {
                          final rider = _riders[index];
                          final fullName =
                              '${rider['firstName']} ${rider['lastName']}';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withOpacity(0.1),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              fullName,
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (rider['phoneNumber'] != null &&
                                    rider['phoneNumber'].isNotEmpty)
                                  Text('📱 ${rider['phoneNumber']}'),
                                if (rider['wallet_amount'] != null)
                                  Text(
                                    '💰 Wallet: ₱${rider['wallet_amount'].toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.green[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              Navigator.pop(context, rider);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    return selectedRider;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _isLoading && _todayTransactions.isEmpty
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadDailyData();
                    await _loadRiders();
                  },
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Selector
                        Card(
                          child: ListTile(
                            leading: Icon(Icons.calendar_today,
                                color: Colors.orange),
                            title: Text('Date: $_selectedDate'),
                            trailing: Icon(Icons.arrow_drop_down),
                            onTap: _selectDate,
                          ),
                        ),

                        SizedBox(height: 16),

                        // Daily Summary
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Daily Summary',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 12),
                                _buildSummaryRow(
                                    'Opening Balance',
                                    _dailySummary['opening_balance'] ?? 0,
                                    Colors.blue),
                                _buildSummaryRow(
                                    'Wallet Top-ups',
                                    _dailySummary['wallet_topups'] ?? 0,
                                    Colors.green),
                                _buildSummaryRow(
                                    'Other Income',
                                    _dailySummary['other_income'] ?? 0,
                                    Colors.teal),
                                _buildSummaryRow(
                                    'Credit Sales',
                                    _dailySummary['credit_sales'] ?? 0,
                                    Colors.indigo),
                                _buildSummaryRow(
                                    'Payments Received',
                                    _dailySummary['total_payments_received'] ??
                                        0,
                                    Colors.purple),
                                _buildSummaryRow(
                                    'Total Expenses',
                                    _dailySummary['total_expenses'] ?? 0,
                                    Colors.red),
                                Divider(),
                                _buildSummaryRow(
                                    'Net Balance',
                                    _dailySummary['net_balance'] ?? 0,
                                    Colors.orange,
                                    isBold: true),
                                _buildSummaryRow(
                                    'Closing Balance',
                                    _dailySummary['closing_balance'] ?? 0,
                                    Colors.purple,
                                    isBold: true),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        // Credit Sales Only Card
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.credit_card,
                                      color: Colors.indigo,
                                      size: 24,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Credit Sales Only',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                _buildSummaryRow(
                                  'Total Credit Sales',
                                  _dailySummary['credit_sales'] ?? 0,
                                  Colors.indigo,
                                  isBold: true,
                                ),
                                SizedBox(height: 12),
                                Divider(),
                                SizedBox(height: 12),
                                _getCreditSalesTransactions().isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(20),
                                          child: Text(
                                            'No credit sales for this date',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        physics: NeverScrollableScrollPhysics(),
                                        itemCount: _getCreditSalesTransactions()
                                            .length,
                                        separatorBuilder: (context, index) =>
                                            Divider(),
                                        itemBuilder: (context, index) {
                                          final transaction =
                                              _getCreditSalesTransactions()[
                                                  index];
                                          return _buildCreditSaleItem(
                                              transaction);
                                        },
                                      ),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        // Add Transaction Form
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Transaction',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 16),

                                // Transaction Type Buttons
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        RiderWalletPage(),
                                                  ),
                                                );
                                              },
                                        icon: Icon(Icons.account_balance_wallet,
                                            color: Colors.white),
                                        label: Text('Wallet Top-up',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 20, horizontal: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => _showTransactionModal(
                                                'other_income'),
                                        icon: Icon(Icons.trending_up,
                                            color: Colors.white),
                                        label: Text('Other Income',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 20, horizontal: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => _showTransactionModal(
                                                'credit_sale'),
                                        icon: Icon(Icons.credit_card,
                                            color: Colors.white),
                                        label: Text('Credit (Utang)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.indigo,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 20, horizontal: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => _showCreditPaymentModal(),
                                        icon: Icon(Icons.payment,
                                            color: Colors.white),
                                        label: Text('Payment (Bayad Utang)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 20, horizontal: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => _showTransactionModal(
                                                'expense'),
                                        icon: Icon(Icons.trending_down,
                                            color: Colors.white),
                                        label: Text('Expense (Gastu)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 20, horizontal: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        // Today's Transactions
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Today\'s Transactions',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 12),
                                if (_todayTransactions.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Text(
                                        'No transactions for this date',
                                        style:
                                            TextStyle(color: Colors.grey[600]),
                                      ),
                                    ),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: NeverScrollableScrollPhysics(),
                                    itemCount: _todayTransactions.length,
                                    separatorBuilder: (context, index) =>
                                        Divider(),
                                    itemBuilder: (context, index) {
                                      final transaction =
                                          _todayTransactions[index];
                                      return _buildTransactionItem(transaction);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        // Monthly Report Button
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MonthlyReportPage(),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.calendar_month,
                                    color: Colors.white, size: 24),
                                label: Text(
                                  'Monthly Report',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    vertical: 20,
                                    horizontal: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          if (_isSubmitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getCreditSalesTransactions() {
    return _todayTransactions
        .where((transaction) => transaction['type'] == 'credit_sale')
        .toList();
  }

  Widget _buildSummaryRow(String label, double amount, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditSaleItem(Map<String, dynamic> transaction) {
    final double amount = (transaction['amount'] ?? 0).toDouble();
    final String description = (transaction['description'] ?? '').toString();
    final String transactionId = (transaction['id'] ?? '').toString();
    final String? creditEntryId = transaction['creditEntryId'] as String?;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.indigo.withOpacity(0.1),
        child: Icon(Icons.credit_card, color: Colors.indigo),
      ),
      title: Text(
        'Credit Sale',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.indigo,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red),
            onPressed: () => _confirmDeleteCreditSale(
              transactionId,
              amount,
              description,
              creditEntryId,
            ),
            tooltip: 'Delete credit sale',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCreditSale(
    String transactionId,
    double amount,
    String description,
    String? creditEntryId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Credit Sale'),
        content: Text(
          'Are you sure you want to delete this credit sale?\n\n'
          'Amount: ₱${amount.toStringAsFixed(2)}\n'
          'Description: $description\n\n'
          'This will also delete the associated credit entry if it exists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() => _isSubmitting = true);

        await SalesService.deleteCreditSale(
          dateKey: _selectedDate,
          transactionId: transactionId,
          amount: amount,
          creditEntryId: creditEntryId,
        );

        await _loadDailyData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Credit sale deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete credit sale: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    }
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final String type = (transaction['type'] ?? '').toString();
    final double amount = (transaction['amount'] ?? 0).toDouble();
    final String description = (transaction['description'] ?? '').toString();

    String typeLabel;
    Color typeColor;
    IconData typeIcon;

    switch (type) {
      case 'wallet_topup':
        typeLabel = 'Wallet Top-up';
        typeColor = Colors.green;
        typeIcon = Icons.account_balance_wallet;
        break;
      case 'other_income':
        typeLabel = 'Other Income';
        typeColor = Colors.teal;
        typeIcon = Icons.trending_up;
        break;
      case 'credit_sale':
        typeLabel = 'Credit Sale';
        typeColor = Colors.indigo;
        typeIcon = Icons.credit_card;
        break;
      case 'credit_payment':
        typeLabel = 'Payment (Bayad Utang)';
        typeColor = Colors.purple;
        typeIcon = Icons.payment;
        break;
      case 'expense':
        typeLabel = 'Expense';
        typeColor = Colors.red;
        typeIcon = Icons.trending_down;
        break;
      default:
        typeLabel = type;
        typeColor = Colors.grey;
        typeIcon = Icons.help;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: typeColor.withOpacity(0.1),
        child: Icon(typeIcon, color: typeColor),
      ),
      title: Text(typeLabel),
      subtitle: Text(description),
      trailing: Text(
        '₱${amount.toStringAsFixed(2)}',
        style: TextStyle(
          color: typeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
