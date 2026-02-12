import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/rider_wallet_details_page.dart';

class RiderWalletPage extends StatefulWidget {
  const RiderWalletPage({Key? key}) : super(key: key);

  @override
  _RiderWalletPageState createState() => _RiderWalletPageState();
}

class _RiderWalletPageState extends State<RiderWalletPage> {
  List<Map<String, dynamic>> _riders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    setState(() => _isLoading = true);

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
        if (rawWallet is num) {
          walletAmount = rawWallet.toDouble();
        } else if (rawWallet is String) {
          walletAmount = double.tryParse(rawWallet) ?? 0.0;
        }
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
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _riders = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load riders: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rider Wallets'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadRiders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _riders.isEmpty
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
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadRiders,
                        icon: Icon(Icons.refresh),
                        label: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRiders,
                  child: ListView.separated(
                    padding: EdgeInsets.all(16),
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
                                rider['phoneNumber'].toString().isNotEmpty)
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RiderWalletDetailsPage(
                                rider: rider,
                              ),
                            ),
                          ).then((_) {
                            // Refresh riders list when returning from details page
                            _loadRiders();
                          });
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
