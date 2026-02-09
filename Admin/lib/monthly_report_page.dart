import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class MonthlyReportPage extends StatefulWidget {
  @override
  _MonthlyReportPageState createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  DateTime _selectedMonth = DateTime.now();
  Map<String, double> _monthlySummary = {};
  List<Map<String, dynamic>> _monthlyTransactions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMonthlyData();
  }

  Future<void> _loadMonthlyData() async {
    setState(() => _isLoading = true);

    try {
      final year = _selectedMonth.year;
      final month = _selectedMonth.month;

      // Get all daily summaries for the selected month
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);
      
      final startDateStr = startDate.toIso8601String().split('T')[0];
      final endDateStr = endDate.toIso8601String().split('T')[0];

      // Get all documents and filter by date range
      final allSummaries = await FirebaseFirestore.instance
          .collection(DAILY_SUMMARIES)
          .get();

      final summariesSnapshot = allSummaries.docs.where((doc) {
        final dateStr = doc.id; // Document ID is the date
        return dateStr.compareTo(startDateStr) >= 0 &&
            dateStr.compareTo(endDateStr) <= 0;
      }).toList();

      double totalOpeningBalance = 0.0;
      double totalWalletTopups = 0.0;
      double totalOtherIncome = 0.0;
      double totalCreditSales = 0.0;
      double totalPaymentsReceived = 0.0;
      double totalExpenses = 0.0;
      double totalNetBalance = 0.0;
      double finalClosingBalance = 0.0;

      final allTransactions = <Map<String, dynamic>>[];

      for (var doc in summariesSnapshot) {
        final data = doc.data();
        totalOpeningBalance += (data['opening_balance'] ?? 0).toDouble();
        totalWalletTopups += (data['wallet_topups'] ?? 0).toDouble();
        totalOtherIncome += (data['other_income'] ?? 0).toDouble();
        totalCreditSales += (data['credit_sales'] ?? 0).toDouble();
        totalPaymentsReceived += (data['total_payments_received'] ?? 0).toDouble();
        totalExpenses += (data['total_expenses'] ?? 0).toDouble();
        totalNetBalance += (data['net_balance'] ?? 0).toDouble();
        finalClosingBalance = (data['closing_balance'] ?? 0).toDouble();

        // Get transactions for this day
        final txSnapshot = await doc.reference
            .collection('transactions')
            .orderBy('created_at', descending: true)
            .get();

        for (var txDoc in txSnapshot.docs) {
          final txData = txDoc.data();
          final dynamic rawAmount = txData['amount'];
          double parsedAmount = 0.0;
          if (rawAmount is num) {
            parsedAmount = rawAmount.toDouble();
          } else if (rawAmount is String) {
            parsedAmount = double.tryParse(rawAmount) ?? 0.0;
          }

          allTransactions.add({
            'id': txDoc.id,
            'date': txData['date'] ?? '',
            'type': txData['type'] ?? '',
            'amount': parsedAmount,
            'description': txData['description'] ?? '',
            'riderId': txData['riderId'],
            'creditEntryId': txData['creditEntryId'],
            'created_at': txData['created_at'],
          });
        }
      }

      // Sort transactions by date (newest first)
      allTransactions.sort((a, b) {
        final aDate = a['date'] ?? '';
        final bDate = b['date'] ?? '';
        if (aDate == bDate) {
          final aTime = a['created_at'] as Timestamp?;
          final bTime = b['created_at'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        }
        return bDate.compareTo(aDate);
      });

      setState(() {
        _monthlySummary = {
          'opening_balance': totalOpeningBalance,
          'wallet_topups': totalWalletTopups,
          'other_income': totalOtherIncome,
          'credit_sales': totalCreditSales,
          'total_payments_received': totalPaymentsReceived,
          'total_expenses': totalExpenses,
          'net_balance': totalNetBalance,
          'closing_balance': finalClosingBalance,
        };
        _monthlyTransactions = allTransactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load monthly data: $e')),
        );
      }
    }
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select Month',
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      await _loadMonthlyData();
    }
  }

  String _getMonthYearString() {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
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

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final String type = (transaction['type'] ?? '').toString();
    final double amount = (transaction['amount'] ?? 0).toDouble();
    final String description = (transaction['description'] ?? '').toString();
    final String date = (transaction['date'] ?? '').toString();

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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          SizedBox(height: 4),
          Text(
            date,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Monthly Report'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMonthlyData,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month Selector
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.calendar_month, color: Colors.blue),
                        title: Text('Month: ${_getMonthYearString()}'),
                        trailing: Icon(Icons.arrow_drop_down),
                        onTap: _selectMonth,
                      ),
                    ),

                    SizedBox(height: 16),

                    // Monthly Summary
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monthly Summary',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            _buildSummaryRow(
                                'Total Opening Balance',
                                _monthlySummary['opening_balance'] ?? 0,
                                Colors.blue),
                            _buildSummaryRow(
                                'Total Wallet Top-ups',
                                _monthlySummary['wallet_topups'] ?? 0,
                                Colors.green),
                            _buildSummaryRow(
                                'Total Other Income',
                                _monthlySummary['other_income'] ?? 0,
                                Colors.teal),
                            _buildSummaryRow(
                                'Total Credit Sales',
                                _monthlySummary['credit_sales'] ?? 0,
                                Colors.indigo),
                            _buildSummaryRow(
                                'Total Payments Received',
                                _monthlySummary['total_payments_received'] ?? 0,
                                Colors.purple),
                            _buildSummaryRow(
                                'Total Expenses',
                                _monthlySummary['total_expenses'] ?? 0,
                                Colors.red),
                            Divider(),
                            _buildSummaryRow(
                                'Total Net Balance',
                                _monthlySummary['net_balance'] ?? 0,
                                Colors.orange,
                                isBold: true),
                            _buildSummaryRow(
                                'Final Closing Balance',
                                _monthlySummary['closing_balance'] ?? 0,
                                Colors.purple,
                                isBold: true),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 16),

                    // Monthly Transactions
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Transactions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            if (_monthlyTransactions.isEmpty)
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No transactions for this month',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: _monthlyTransactions.length,
                                separatorBuilder: (context, index) => Divider(),
                                itemBuilder: (context, index) {
                                  final transaction =
                                      _monthlyTransactions[index];
                                  return _buildTransactionItem(transaction);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

