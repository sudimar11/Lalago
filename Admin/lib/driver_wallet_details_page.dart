import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class DriverWalletDetailsPage extends StatefulWidget {
  final Map<String, dynamic> driver;

  const DriverWalletDetailsPage({
    Key? key,
    required this.driver,
  }) : super(key: key);

  @override
  _DriverWalletDetailsPageState createState() =>
      _DriverWalletDetailsPageState();
}

class _DriverWalletDetailsPageState extends State<DriverWalletDetailsPage> {
  double? _walletCredit;
  double? _walletBalance;
  double? _tipAmount;
  List<Map<String, dynamic>> _transmitRequests = [];
  List<Map<String, dynamic>> _payoutRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    setState(() => _isLoading = true);

    try {
      final driverId = widget.driver['id'] as String;

      // Load driver document to get wallet fields and transaction arrays
      final driverDoc = await FirebaseFirestore.instance
          .collection(USERS)
          .doc(driverId)
          .get();

      if (driverDoc.exists) {
        final data = driverDoc.data()!;

        // Load wallet_credit
        final dynamic rawCredit = data['wallet_credit'];
        double walletCredit = 0.0;
        if (rawCredit is num) {
          walletCredit = rawCredit.toDouble();
        } else if (rawCredit is String) {
          walletCredit = double.tryParse(rawCredit) ?? 0.0;
        }

        // Load wallet_amount
        final dynamic rawWallet = data['wallet_amount'];
        double walletAmount = 0.0;
        if (rawWallet is num) {
          walletAmount = rawWallet.toDouble();
        } else if (rawWallet is String) {
          walletAmount = double.tryParse(rawWallet) ?? 0.0;
        }

        // Load transmitRequests array
        final transmitRequestsRaw = data['transmitRequests'];
        List<Map<String, dynamic>> transmitRequests = [];
        if (transmitRequestsRaw is List) {
          for (var req in transmitRequestsRaw) {
            if (req is Map<String, dynamic>) {
              final type = req['type'] as String? ?? '';
              if (type == 'credit_wallet_transmit') {
                transmitRequests.add(req);
              }
            }
          }
        }

        // Load payoutRequests array
        final payoutRequestsRaw = data['payoutRequests'];
        List<Map<String, dynamic>> payoutRequests = [];
        if (payoutRequestsRaw is List) {
          for (var req in payoutRequestsRaw) {
            if (req is Map<String, dynamic>) {
              final type = req['type'] as String? ?? '';
              if (type == 'earning_wallet_payout') {
                payoutRequests.add(req);
              }
            }
          }
        }

        // Sort requests by date (newest first)
        transmitRequests.sort((a, b) {
          final aDate = a['createdAt'] as Timestamp?;
          final bDate = b['createdAt'] as Timestamp?;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });

        payoutRequests.sort((a, b) {
          final aDate = a['createdAt'] as Timestamp?;
          final bDate = b['createdAt'] as Timestamp?;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });

        // Calculate tip amount from completed orders
        double tipAmount = 0.0;
        try {
          final ordersSnapshot = await FirebaseFirestore.instance
              .collection('restaurant_orders')
              .where('driverID', isEqualTo: driverId)
              .where('status', whereIn: ['Order Completed', 'completed'])
              .get();

          for (var orderDoc in ordersSnapshot.docs) {
            final orderData = orderDoc.data();
            final dynamic tipValue = orderData['tipAmount'];
            if (tipValue != null) {
              if (tipValue is num) {
                tipAmount += tipValue.toDouble();
              } else if (tipValue is String) {
                final parsed = double.tryParse(tipValue);
                if (parsed != null) {
                  tipAmount += parsed;
                }
              }
            }
          }
        } catch (e) {
          // If tip calculation fails, continue with 0.0
        }

        setState(() {
          _walletCredit = walletCredit;
          _walletBalance = walletAmount;
          _tipAmount = tipAmount;
          _transmitRequests = transmitRequests;
          _payoutRequests = payoutRequests;
          _isLoading = false;
        });
      } else {
        setState(() {
          _walletCredit = 0.0;
          _walletBalance = 0.0;
          _tipAmount = 0.0;
          _transmitRequests = [];
          _payoutRequests = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load wallet data: $e')),
      );
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final date = timestamp.toDate();
      return DateFormat('MMM dd, yyyy • HH:mm').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName =
        '${widget.driver['firstName']} ${widget.driver['lastName']}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Wallet Details'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadWalletData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWalletData,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Information Card
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Driver Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.teal.withOpacity(0.1),
                                  child: Text(
                                    widget.driver['firstName'][0]
                                        .toString()
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (widget.driver['phoneNumber'] != null &&
                                          widget.driver['phoneNumber']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                          '📱 ${widget.driver['phoneNumber']}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 16),

                    // Wallet Information Card
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wallet Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 16),
                            // Wallet Credit
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Wallet Credit',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Total credited amount transmitted',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '₱${(_walletCredit ?? 0.0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12),
                            // Wallet Balance
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Wallet Balance',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Current available balance',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '₱${(_walletBalance ?? 0.0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12),
                            // Tip Amount
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tip Amount',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Total tips from completed orders',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '₱${(_tipAmount ?? 0.0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 16),

                    // Transmit Requests Card
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.send, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  'Transmit Requests',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            if (_transmitRequests.isEmpty)
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No transmit requests',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: _transmitRequests.length,
                                separatorBuilder: (context, index) => Divider(),
                                itemBuilder: (context, index) {
                                  final request = _transmitRequests[index];
                                  final amount = (request['amount'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                                  final status = request['status'] as String? ?? '';
                                  final createdAt =
                                      request['createdAt'] as Timestamp?;
                                  final description =
                                      request['description'] as String? ?? '';

                                  Color statusColor = Colors.grey;
                                  if (status == 'confirmed') {
                                    statusColor = Colors.green;
                                  } else if (status == 'pending') {
                                    statusColor = Colors.orange;
                                  }

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          Colors.blue.withOpacity(0.1),
                                      child: Icon(Icons.send,
                                          color: Colors.blue, size: 20),
                                    ),
                                    title: Text(
                                      '₱${amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (description.isNotEmpty)
                                          Text(description),
                                        SizedBox(height: 4),
                                        Text(
                                          _formatDate(createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: statusColor.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 16),

                    // Payout Requests Card
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.payment, color: Colors.purple),
                                SizedBox(width: 8),
                                Text(
                                  'Payout Requests',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            if (_payoutRequests.isEmpty)
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No payout requests',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: _payoutRequests.length,
                                separatorBuilder: (context, index) => Divider(),
                                itemBuilder: (context, index) {
                                  final request = _payoutRequests[index];
                                  final amount = (request['amount'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                                  final status = request['status'] as String? ?? '';
                                  final createdAt =
                                      request['createdAt'] as Timestamp?;
                                  final description =
                                      request['description'] as String? ?? '';

                                  Color statusColor = Colors.grey;
                                  if (status == 'confirmed') {
                                    statusColor = Colors.green;
                                  } else if (status == 'pending') {
                                    statusColor = Colors.orange;
                                  }

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          Colors.purple.withOpacity(0.1),
                                      child: Icon(Icons.payment,
                                          color: Colors.purple, size: 20),
                                    ),
                                    title: Text(
                                      '₱${amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple[700],
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (description.isNotEmpty)
                                          Text(description),
                                        SizedBox(height: 4),
                                        Text(
                                          _formatDate(createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: statusColor.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  );
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

