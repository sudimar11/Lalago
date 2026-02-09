import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/driver_wallet_details_page.dart';

class DriverWalletPage extends StatefulWidget {
  const DriverWalletPage({Key? key}) : super(key: key);

  @override
  _DriverWalletPageState createState() => _DriverWalletPageState();
}

class _DriverWalletPageState extends State<DriverWalletPage> {
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    setState(() => _isLoading = true);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .get();

      final List<Map<String, dynamic>> firestoreDrivers =
          querySnapshot.docs.map((doc) {
        final data = doc.data();
        final String firstName = (data['firstName'] ?? '').toString();
        final String lastName = (data['lastName'] ?? '').toString();
        final String safeFirstName =
            firstName.isNotEmpty ? firstName : 'Unknown';
        final dynamic rawWallet = data['wallet_amount'];
        double walletAmount = 0.0;
        if (rawWallet is num) {
          walletAmount = rawWallet.toDouble();
        } else if (rawWallet is String) {
          walletAmount = double.tryParse(rawWallet) ?? 0.0;
        }
        final dynamic rawCredit = data['wallet_credit'];
        double walletCredit = 0.0;
        if (rawCredit is num) {
          walletCredit = rawCredit.toDouble();
        } else if (rawCredit is String) {
          walletCredit = double.tryParse(rawCredit) ?? 0.0;
        }
        return {
          'id': doc.id,
          'firstName': safeFirstName,
          'lastName': lastName,
          'phoneNumber': (data['phoneNumber'] ?? '').toString(),
          'wallet_amount': walletAmount,
          'wallet_credit': walletCredit,
        };
      }).toList();

      firestoreDrivers.sort((a, b) {
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
        _drivers = firestoreDrivers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _drivers = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load drivers: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Wallets'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDrivers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _drivers.isEmpty
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
                        'No drivers found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadDrivers,
                        icon: Icon(Icons.refresh),
                        label: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDrivers,
                  child: ListView.separated(
                    padding: EdgeInsets.all(16),
                    itemCount: _drivers.length,
                    separatorBuilder: (context, index) => Divider(),
                    itemBuilder: (context, index) {
                      final driver = _drivers[index];
                      final fullName =
                          '${driver['firstName']} ${driver['lastName']}';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.withOpacity(0.1),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Colors.teal,
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
                            if (driver['phoneNumber'] != null &&
                                driver['phoneNumber'].toString().isNotEmpty)
                              Text('📱 ${driver['phoneNumber']}'),
                            if (driver['wallet_amount'] != null)
                              Text(
                                '💰 Balance: ₱${driver['wallet_amount'].toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.green[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (driver['wallet_credit'] != null)
                              Text(
                                '💳 Credit: ₱${driver['wallet_credit'].toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.blue[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DriverWalletDetailsPage(
                                driver: driver,
                              ),
                            ),
                          ).then((_) {
                            // Refresh drivers list when returning from details page
                            _loadDrivers();
                          });
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

