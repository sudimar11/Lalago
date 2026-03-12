import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/attendance_page.dart';

class DriverListPage extends StatefulWidget {
  @override
  _DriverListPageState createState() => _DriverListPageState();
}

class _DriverListPageState extends State<DriverListPage> {
  List<DriverData> _drivers = [];
  List<DriverData> _allDrivers = [];
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;

  // Batch pagination variables
  int _currentBatch = 1;
  int _batchSize = 100;
  int _totalBatches = 0;
  bool _isLoadingBatch = false;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
        _currentBatch = 1;
      });

      // Load from Firestore
      await _loadDriversFromFirestore();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading drivers: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDriversFromFirestore() async {
    try {
      List<DriverData> allDrivers = [];

      // Build query - fetch all users with driver role
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .where('active', isEqualTo: true)
          .get();

      // Process documents
      for (QueryDocumentSnapshot doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Extract driver data from Firestore document
        String driverId = doc.id;
        String firstName = data['firstName'] ?? '';
        String lastName = data['lastName'] ?? '';
        String phoneNumber = data['phoneNumber'] ?? '';
        String email = data['email'] ?? '';
        bool active = data['active'] ?? false;
        String carName = data['carName'] ?? 'N/A';
        String carNumber = data['carNumber'] ?? 'N/A';
        String carPictureURL = data['carPictureURL'] ?? '';
        double walletAmount = (data['wallet_amount'] ?? 0.0).toDouble();

        // Get location data
        double latitude = 0.0;
        double longitude = 0.0;
        if (data['location'] != null) {
          if (data['location'] is GeoPoint) {
            GeoPoint geoPoint = data['location'] as GeoPoint;
            latitude = geoPoint.latitude;
            longitude = geoPoint.longitude;
          } else if (data['location'] is Map) {
            latitude = (data['location']['latitude'] ?? 0.0).toDouble();
            longitude = (data['location']['longitude'] ?? 0.0).toDouble();
          }
        }

        bool isAvailable = data['isAvailable'] ?? false;
        String riderDisplayStatus =
            data['riderDisplayStatus'] as String? ?? '⚪ Offline';
        bool multipleOrders = data['multipleOrders'] ?? false;
        List<dynamic>? inProgressOrderID = data['inProgressOrderID'];
        int activeOrders = inProgressOrderID?.length ?? 0;

        // Create full name
        String fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
        if (fullName.isEmpty) {
          fullName = 'Unknown Driver';
        }

        // Create status based on active field
        String status = active ? 'Active' : 'Inactive';
        String availability = isAvailable ? 'Available' : 'Unavailable';

        // Assign batch number
        int driverIndex = allDrivers.length;
        int batchNumber = (driverIndex ~/ _batchSize) + 1;
        String batch = 'Batch $batchNumber';

        allDrivers.add(DriverData(
          driverId: driverId,
          name: fullName,
          phoneNumber: phoneNumber,
          email: email,
          status: status,
          availability: availability,
          carName: carName,
          carNumber: carNumber,
          carPictureURL: carPictureURL,
          walletAmount: walletAmount,
          latitude: latitude,
          longitude: longitude,
          activeOrders: activeOrders,
          batch: batch,
          riderDisplayStatus: riderDisplayStatus,
          multipleOrders: multipleOrders,
        ));
      }

      _allDrivers = allDrivers;
      // Sort alphabetically by name
      _allDrivers
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _totalBatches = (_allDrivers.length / _batchSize).ceil();
      _loadCurrentBatch();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading drivers from Firestore: $e';
        });
      }
    }
  }

  void _loadCurrentBatch() {
    if (!mounted) return;

    if (_allDrivers.isEmpty) {
      setState(() {
        _drivers = [];
        _totalBatches = 0;
      });
      return;
    }

    int startIndex = (_currentBatch - 1) * _batchSize;
    int endIndex = startIndex + _batchSize;

    if (endIndex > _allDrivers.length) {
      endIndex = _allDrivers.length;
    }

    setState(() {
      _drivers = _allDrivers.sublist(startIndex, endIndex);
      _totalBatches = (_allDrivers.length / _batchSize).ceil();
    });
  }

  void _nextBatch() {
    if (_currentBatch < _totalBatches) {
      setState(() {
        _currentBatch++;
        _isLoadingBatch = true;
      });

      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          _loadCurrentBatch();
          setState(() {
            _isLoadingBatch = false;
          });
        }
      });
    }
  }

  void _previousBatch() {
    if (_currentBatch > 1) {
      setState(() {
        _currentBatch--;
        _isLoadingBatch = true;
      });

      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          _loadCurrentBatch();
          setState(() {
            _isLoadingBatch = false;
          });
        }
      });
    }
  }

  void _goToBatch(int batchNumber) {
    if (batchNumber >= 1 && batchNumber <= _totalBatches) {
      setState(() {
        _currentBatch = batchNumber;
        _isLoadingBatch = true;
      });

      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          _loadCurrentBatch();
          setState(() {
            _isLoadingBatch = false;
          });
        }
      });
    }
  }

  // Update driver's multiple orders setting in Firestore
  Future<void> _updateDriverMultipleOrders(
      String driverId, bool newValue) async {
    try {
      await FirebaseFirestore.instance
          .collection(USERS)
          .doc(driverId)
          .update({'multipleOrders': newValue});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Multiple orders setting updated successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating multiple orders: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.0),
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
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.drive_eta,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver List',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.event_note,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AttendancePage(),
                            ),
                          );
                        },
                        tooltip: 'Attendance',
                        padding: EdgeInsets.all(8),
                        constraints:
                            BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      // Refresh button
                      IconButton(
                        icon:
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: _isLoading ? null : _loadDrivers,
                        tooltip: 'Refresh',
                        padding: EdgeInsets.all(8),
                        constraints:
                            BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

            // Loading indicator
            if (_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Loading drivers...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              // Error state
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDrivers,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Content - Scrollable table
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 2.0,
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Table(
                            columnWidths: {
                              0: FlexColumnWidth(0.5), // No.
                              1: FlexColumnWidth(1.5), // Name
                              2: FlexColumnWidth(0.8), // Online
                              3: FlexColumnWidth(1.2), // Phone
                              4: FlexColumnWidth(1.5), // Email
                              5: FlexColumnWidth(0.7), // Status
                              6: FlexColumnWidth(0.9), // Availability
                              7: FlexColumnWidth(1.0), // Multiple Orders
                              8: FlexColumnWidth(1.1), // Car Name
                              9: FlexColumnWidth(0.9), // Car Number
                              10: FlexColumnWidth(0.8), // Wallet
                              11: FlexColumnWidth(1.2), // Location
                              12: FlexColumnWidth(0.7), // Orders
                            },
                            children: [
                              TableRow(
                                children: [
                                  _buildHeaderCell('No.'),
                                  _buildHeaderCell('Name'),
                                  _buildHeaderCell('Online'),
                                  _buildHeaderCell('Phone'),
                                  _buildHeaderCell('Email'),
                                  _buildHeaderCell('Status'),
                                  _buildHeaderCell('Availability'),
                                  _buildHeaderCell('Multiple Orders'),
                                  _buildHeaderCell('Car Name'),
                                  _buildHeaderCell('Car Number'),
                                  _buildHeaderCell('Wallet'),
                                  _buildHeaderCell('Location'),
                                  _buildHeaderCell('Active Orders'),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 8),

                        // Driver List
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _isLoadingBatch
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text(
                                          'Loading batch $_currentBatch...',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _drivers.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.drive_eta,
                                              size: 64,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'No drivers found',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Drivers must have role = "driver" in Firestore',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _drivers.length,
                                        itemBuilder: (context, index) {
                                          final driver = _drivers[index];
                                          return Container(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Colors.orange
                                                      .withOpacity(0.1),
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Table(
                                              columnWidths: {
                                                0: FlexColumnWidth(0.5),
                                                1: FlexColumnWidth(1.5),
                                                2: FlexColumnWidth(0.8),
                                                3: FlexColumnWidth(1.2),
                                                4: FlexColumnWidth(1.5),
                                                5: FlexColumnWidth(0.7),
                                                6: FlexColumnWidth(0.9),
                                                7: FlexColumnWidth(1.0),
                                                8: FlexColumnWidth(1.1),
                                                9: FlexColumnWidth(0.9),
                                                10: FlexColumnWidth(0.8),
                                                11: FlexColumnWidth(1.2),
                                                12: FlexColumnWidth(0.7),
                                              },
                                              children: [
                                                TableRow(
                                                  children: [
                                                    _buildDataCell(
                                                        '${index + 1}'),
                                                    _buildDataCell(driver.name),
                                                    _buildOnlineStatusCell(
                                                        driver.riderDisplayStatus),
                                                    _buildDataCell(
                                                        driver.phoneNumber),
                                                    _buildDataCell(
                                                        driver.email),
                                                    _buildStatusCell(
                                                        driver.status),
                                                    _buildAvailabilityCell(
                                                        driver.availability),
                                                    _buildSwitchCell(
                                                        driver.multipleOrders,
                                                        (newValue) {
                                                      setState(() {
                                                        driver.multipleOrders =
                                                            newValue;
                                                      });
                                                      _updateDriverMultipleOrders(
                                                          driver.driverId,
                                                          newValue);
                                                    }),
                                                    _buildDataCell(
                                                        driver.carName),
                                                    _buildDataCell(
                                                        driver.carNumber),
                                                    _buildDataCell(
                                                        '₱${driver.walletAmount.toStringAsFixed(2)}'),
                                                    _buildDataCell(driver
                                                                .latitude !=
                                                            0.0
                                                        ? '${driver.latitude.toStringAsFixed(4)}, ${driver.longitude.toStringAsFixed(4)}'
                                                        : 'N/A'),
                                                    _buildDataCell(driver
                                                        .activeOrders
                                                        .toString()),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: Colors.black87,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDataCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text.isEmpty ? '-' : text,
        style: TextStyle(
          fontSize: 10,
          color: text.isEmpty ? Colors.grey : Colors.black87,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  Widget _buildStatusCell(String status) {
    Color statusColor = status == 'Active' ? Colors.green : Colors.red;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 10,
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildAvailabilityCell(String availability) {
    Color availabilityColor =
        availability == 'Available' ? Colors.blue : Colors.orange;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: availabilityColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: availabilityColor.withOpacity(0.3)),
        ),
        child: Text(
          availability,
          style: TextStyle(
            fontSize: 10,
            color: availabilityColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildOnlineStatusCell(String displayStatus) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        displayStatus,
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSwitchCell(bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Center(
        child: Transform.scale(
          scale: 0.8,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.green,
            activeTrackColor: Colors.green.withOpacity(0.5),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}

// Driver data model
class DriverData {
  final String driverId;
  final String name;
  final String phoneNumber;
  final String email;
  final String status;
  final String availability;
  final String carName;
  final String carNumber;
  final String carPictureURL;
  final double walletAmount;
  final double latitude;
  final double longitude;
  final int activeOrders;
  final String batch;
  String riderDisplayStatus;
  bool multipleOrders;

  DriverData({
    required this.driverId,
    required this.name,
    required this.phoneNumber,
    required this.email,
    required this.status,
    required this.availability,
    required this.carName,
    required this.carNumber,
    this.carPictureURL = '',
    required this.walletAmount,
    required this.latitude,
    required this.longitude,
    this.activeOrders = 0,
    required this.batch,
    this.riderDisplayStatus = '⚪ Offline',
    this.multipleOrders = false,
  });
}
