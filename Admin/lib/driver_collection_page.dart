import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/widgets/driver_collection_dialog.dart';
import 'package:brgy/driver_collection_history_page.dart';
import 'package:brgy/widgets/auto_collect_settings_dialog.dart';
import 'package:brgy/driver_collection_details_page.dart';

class DriverCollectionPage extends StatefulWidget {
  const DriverCollectionPage({Key? key}) : super(key: key);

  @override
  State<DriverCollectionPage> createState() => _DriverCollectionPageState();
}

class _DriverCollectionPageState extends State<DriverCollectionPage> {
  Widget _buildAutoCollectBadge(
      Map<String, dynamic>? autoCollectSettings) {
    final failedAttempts =
        (autoCollectSettings?['failedAttempts'] as num?)?.toInt() ?? 0;
    final disabledReason =
        autoCollectSettings?['disabledReason'] as String?;
    final isDisabled = disabledReason != null;

    Color badgeColor;
    Color iconColor;
    IconData icon;
    String label;

    if (isDisabled) {
      badgeColor = Colors.red[100]!;
      iconColor = Colors.red[700]!;
      icon = Icons.error_outline;
      label = 'Disabled';
    } else if (failedAttempts > 0) {
      badgeColor = Colors.orange[100]!;
      iconColor = Colors.orange[700]!;
      icon = Icons.warning;
      label = '$failedAttempts retries';
    } else {
      badgeColor = Colors.green[100]!;
      iconColor = Colors.green[700]!;
      icon = Icons.check_circle;
      label = 'Active';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: iconColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Collect from Driver'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            tooltip: 'View Collection History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverCollectionHistoryPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(USERS)
            .where('role', isEqualTo: USER_ROLE_DRIVER)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Error loading drivers: ${snapshot.error}',
                    style: TextStyle(color: Colors.red),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: Icon(Icons.refresh),
                    label: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final drivers = snapshot.data?.docs ?? [];

          if (drivers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.drive_eta_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No drivers found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          // Process and sort drivers
          final List<Map<String, dynamic>> driverList = drivers.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String firstName = (data['firstName'] ?? '').toString();
            final String lastName = (data['lastName'] ?? '').toString();
            final dynamic rawWallet = data['wallet_amount'];
            double walletAmount = 0.0;
            if (rawWallet is num) {
              walletAmount = rawWallet.toDouble();
            } else if (rawWallet is String) {
              walletAmount = double.tryParse(rawWallet) ?? 0.0;
            }
            final autoCollectSettings =
                data['autoCollectSettings'] as Map<String, dynamic>?;
            return {
              'id': doc.id,
              'firstName': firstName,
              'lastName': lastName,
              'phoneNumber': (data['phoneNumber'] ?? '').toString(),
              'wallet_amount': walletAmount,
              'autoCollectSettings': autoCollectSettings,
            };
          }).toList();

          driverList.sort((a, b) {
            final aName =
                ('${a['firstName']} ${a['lastName']}').trim().toLowerCase();
            final bName =
                ('${b['firstName']} ${b['lastName']}').trim().toLowerCase();
            return aName.compareTo(bName);
          });

          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(Duration(milliseconds: 300));
            },
            child: ListView.separated(
              padding: EdgeInsets.all(16),
              itemCount: driverList.length,
              separatorBuilder: (context, index) => SizedBox(height: 12),
              itemBuilder: (context, index) {
                final driver = driverList[index];
                final fullName =
                    '${driver['firstName']} ${driver['lastName']}'.trim();
                final walletAmount = driver['wallet_amount'] as double;

                final autoCollectSettings =
                    driver['autoCollectSettings'] as Map<String, dynamic>?;
                final isAutoCollectEnabled =
                    autoCollectSettings?['enabled'] == true;
                final autoCollectAmount =
                    (autoCollectSettings?['amount'] as num?)?.toDouble() ?? 0.0;
                final scheduleTime =
                    autoCollectSettings?['scheduleTime'] as String? ?? '';

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DriverCollectionDetailsPage(
                            driverId: driver['id'] as String,
                            driverName: fullName.isEmpty
                                ? 'Unknown Driver'
                                : fullName,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.red.withOpacity(0.1),
                                child: Icon(
                                  Icons.drive_eta,
                                  color: Colors.red,
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName.isEmpty
                                          ? 'Unknown Driver'
                                          : fullName,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[900],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (driver['phoneNumber'] != null &&
                                        driver['phoneNumber']
                                            .toString()
                                            .isNotEmpty) ...[
                                      SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone,
                                            size: 14,
                                            color: Colors.grey[600],
                                          ),
                                          SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              driver['phoneNumber'].toString(),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isAutoCollectEnabled)
                                _buildAutoCollectBadge(
                                  autoCollectSettings,
                                ),
                            ],
                          ),
                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green[400]!,
                                  Colors.green[600]!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Balance',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.9),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '₱${walletAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 28,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.account_balance_wallet,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ],
                            ),
                          ),
                          if (isAutoCollectEnabled) ...[
                            SizedBox(height: 12),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue[200]!,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Colors.blue[700],
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Auto: ₱${autoCollectAmount.toStringAsFixed(2)} at $scheduleTime',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: walletAmount <= 0
                                      ? null
                                      : () {
                                          showDialog(
                                            context: context,
                                            builder: (context) =>
                                                DriverCollectionDialog(
                                              driverId: driver['id'] as String,
                                              driverName: fullName.isEmpty
                                                  ? 'Unknown Driver'
                                                  : fullName,
                                              currentBalance: walletAmount,
                                            ),
                                          ).then((result) {
                                            if (result == true) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Collection completed successfully',
                                                  ),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          });
                                        },
                                  icon: Icon(Icons.money_off, size: 20),
                                  label: Text(
                                    'Collect',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: walletAmount <= 0 ? 0 : 2,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'settings':
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            AutoCollectSettingsDialog(
                                          driverId: driver['id'] as String,
                                          driverName: fullName.isEmpty
                                              ? 'Unknown Driver'
                                              : fullName,
                                          currentSettings: autoCollectSettings,
                                        ),
                                      ).then((result) {
                                        if (result == true) {
                                          // Refresh is handled by StreamBuilder
                                        }
                                      });
                                      break;
                                    case 'history':
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              DriverCollectionDetailsPage(
                                            driverId: driver['id'] as String,
                                            driverName: fullName.isEmpty
                                                ? 'Unknown Driver'
                                                : fullName,
                                          ),
                                        ),
                                      );
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'settings',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.settings,
                                          size: 20,
                                          color: Colors.grey[700],
                                        ),
                                        SizedBox(width: 12),
                                        Text('Auto-Collect Settings'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'history',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.history,
                                          size: 20,
                                          color: Colors.grey[700],
                                        ),
                                        SizedBox(width: 12),
                                        Text('View Collection History'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

