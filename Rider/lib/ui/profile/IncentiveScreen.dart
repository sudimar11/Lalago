import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:intl/intl.dart';

class IncentiveScreen extends StatefulWidget {
  const IncentiveScreen({Key? key}) : super(key: key);

  @override
  State<IncentiveScreen> createState() => _IncentiveScreenState();
}

class _IncentiveScreenState extends State<IncentiveScreen> {
  List<Map<String, dynamic>> _claimedIncentives = [];
  bool _isLoading = true;
  double _totalAmount = 0.0;
  DateTime _selectedMonth = DateTime.now();
  bool _isCombining = false;

  @override
  void initState() {
    super.initState();
    _fetchClaimedIncentives();
  }

  Future<void> _fetchClaimedIncentives() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final user = auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!snap.exists) {
        throw Exception('User document not found');
      }

      final data = snap.data() ?? {};
      final claimedIncentives =
          (data['claimedIncentives'] as List<dynamic>?) ?? [];

      // Fetch lastCombinedAt timestamp
      final lastCombinedTimestamp = data['lastCombinedAt'] as Timestamp?;
      final lastCombined = lastCombinedTimestamp?.toDate();

      // Filter by selected month
      final startOfMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month,
        1,
      );
      final endOfMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        1,
      ).subtract(const Duration(days: 1));

      final filteredIncentives = claimedIncentives
          .map((item) => item as Map<String, dynamic>)
          .where((item) {
        final date = (item['date'] as Timestamp?)?.toDate();
        if (date == null) return false;

        // Filter by selected month
        final isInMonth =
            date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
                date.isBefore(endOfMonth.add(const Duration(days: 1)));

        if (!isInMonth) return false;

        // Filter out already-combined incentives
        if (lastCombined != null) {
          return date.isAfter(lastCombined);
        }

        return true;
      }).toList();

      // Sort by date descending
      filteredIncentives.sort((a, b) {
        final dateA = (a['date'] as Timestamp?)?.toDate() ?? DateTime(0);
        final dateB = (b['date'] as Timestamp?)?.toDate() ?? DateTime(0);
        return dateB.compareTo(dateA);
      });

      // Calculate total of uncombined incentives
      final total = filteredIncentives.fold<double>(
        0.0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0),
      );

      // Only update state if fetch was successful
      if (mounted) {
        setState(() {
          _claimedIncentives = filteredIncentives;
          _totalAmount = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error fetching claimed incentives: $e');
      // Preserve existing data when there's an error
      // Only set loading to false, don't clear the data
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Keep _claimedIncentives and _totalAmount as they were
        });
      }
    }
  }

  Future<void> _selectMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = picked;
      });
      await _fetchClaimedIncentives();
    }
  }

  double _calculateUncombinedTotal() {
    return _totalAmount;
  }

  Future<void> _combineToEarnings() async {
    final uncombinedTotal = _calculateUncombinedTotal();

    // Validate there are uncombined incentives
    if (uncombinedTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No uncombined incentives to transfer'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Combine to Earnings'),
        content: Text(
          'Transfer ₱${uncombinedTotal.toStringAsFixed(2)} to your wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isCombining = true;
    });

    try {
      final user = auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final userId = user.uid;
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final now = DateTime.now();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Get current user data
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw Exception('User document not found');
        }

        final userData = userSnap.data()!;
        final currentWalletAmount =
            (userData['wallet_amount'] ?? 0.0).toDouble();

        // Update wallet amount
        transaction.update(userRef, {
          'wallet_amount': currentWalletAmount + uncombinedTotal,
          'lastCombinedAt': Timestamp.fromDate(now),
        });

        // Create wallet transaction log (earning wallet)
        final walletLogRef =
            FirebaseFirestore.instance.collection(Wallet).doc();
        final transactionId = walletLogRef.id;
        transaction.set(walletLogRef, {
          'id': transactionId,
          'user_id': userId,
          'amount': uncombinedTotal,
          'date': Timestamp.fromDate(now),
          'payment_method': 'Incentive Transfer',
          'payment_status': 'success',
          'transactionUser': 'driver',
          'isTopUp': true,
          'note': 'Combined Incentives',
          'driverEarnings': uncombinedTotal,
          'walletType': 'earning',
        });
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully transferred ₱${uncombinedTotal.toStringAsFixed(2)} to wallet!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Refresh data
      await _fetchClaimedIncentives();
    } catch (e) {
      print('❌ Error combining incentives: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to combine incentives: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCombining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.grey.shade100,
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: isDarkMode(context) ? Colors.white : Colors.black,
        ),
        backgroundColor:
            isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        title: Text(
          'Incentives',
          style: TextStyle(
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchClaimedIncentives,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Column(
                children: [
                  // Total Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Incentives',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            IconButton(
                              onPressed: _selectMonth,
                              icon: Icon(
                                Icons.calendar_today,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Select Month',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('MMMM yyyy').format(_selectedMonth),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '₱${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_isCombining || _totalAmount <= 0)
                                ? null
                                : _combineToEarnings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.orange.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: _isCombining
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.orange,
                                      ),
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.account_balance_wallet,
                                          size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Combine to Earnings',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Incentives List
                  Expanded(
                    child: _claimedIncentives.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.card_giftcard_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No Incentives Claimed',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Claim incentives from the Profile screen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode(context)
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _claimedIncentives.length,
                            itemBuilder: (context, index) {
                              final incentive = _claimedIncentives[index];
                              final date =
                                  (incentive['date'] as Timestamp?)?.toDate();
                              final amount =
                                  (incentive['amount'] as num?)?.toDouble() ??
                                      0.0;
                              final status =
                                  incentive['status'] as String? ?? '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                color: isDarkMode(context)
                                    ? Color(DARK_CARD_BG_COLOR)
                                    : Colors.white,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.card_giftcard,
                                      color: Colors.orange.shade700,
                                      size: 28,
                                    ),
                                  ),
                                  title: Text(
                                    '₱${amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode(context)
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: date != null
                                      ? Text(
                                          DateFormat('MMM d, yyyy • h:mm a')
                                              .format(date),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600,
                                          ),
                                        )
                                      : null,
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
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
}
