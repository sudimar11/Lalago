import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class DriverSuspensionPage extends StatefulWidget {
  @override
  _DriverSuspensionPageState createState() => _DriverSuspensionPageState();
}

class _DriverSuspensionPageState extends State<DriverSuspensionPage> {
  List<DriverSuspensionData> _drivers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .get();

      final List<DriverSuspensionData> drivers = [];
      for (QueryDocumentSnapshot doc in querySnapshot.docs) {
        final Map<String, dynamic> data =
            doc.data() as Map<String, dynamic>;

        final String firstName = data['firstName'] ?? '';
        final String lastName = data['lastName'] ?? '';
        final String fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
        final String name = fullName.isEmpty ? 'Unknown Driver' : fullName;
        final String phoneNumber = data['phoneNumber'] ?? '';
        final bool suspended = data['suspended'] ?? false;
        final int suspensionDate = data['suspensionDate'] ?? 0;
        final Timestamp? suspensionStartDate =
            data['suspensionStartDate'] as Timestamp?;
        final int suspensionWarningCount = data['suspensionWarningCount'] ?? 0;

        drivers.add(DriverSuspensionData(
          driverId: doc.id,
          name: name,
          phoneNumber: phoneNumber,
          suspended: suspended,
          suspensionDate: suspensionDate,
          suspensionStartDate: suspensionStartDate,
          suspensionWarningCount: suspensionWarningCount,
        ));
      }

      drivers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _drivers = drivers;
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

  Future<void> _suspendDriver(String driverId, String driverName) async {
    int? selectedDays;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final TextEditingController daysController =
            TextEditingController(text: '2');
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Suspend Driver'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Driver: $driverName'),
                  SizedBox(height: 16),
                  Text('Select number of days:'),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.remove_circle),
                        onPressed: () {
                          final current = int.tryParse(daysController.text) ?? 1;
                          if (current > 1) {
                            daysController.text = (current - 1).toString();
                            setDialogState(() {});
                          }
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: daysController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Days',
                          ),
                          onChanged: (value) {
                            setDialogState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.add_circle),
                        onPressed: () {
                          final current = int.tryParse(daysController.text) ?? 1;
                          daysController.text = (current + 1).toString();
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Selected: ${daysController.text} day(s)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final days = int.tryParse(daysController.text);
                    if (days != null && days > 0) {
                      selectedDays = days;
                      Navigator.of(context).pop(true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please enter a valid number of days'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Suspend'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true || selectedDays == null) return;

    try {
      await FirebaseFirestore.instance
          .collection(USERS)
          .doc(driverId)
          .update({
        'suspended': true,
        'suspensionDate': selectedDays,
        'suspensionStartDate': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Driver suspended successfully for $selectedDays day(s)'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDrivers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to suspend driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unsuspendDriver(String driverId, String driverName) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unsuspend Driver'),
        content: Text('Are you sure you want to unsuspend $driverName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Unsuspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection(USERS)
          .doc(driverId)
          .update({
        'suspended': false,
        'suspensionDate': 0,
        'suspensionStartDate': FieldValue.delete(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver unsuspended successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDrivers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unsuspend driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addSuspensionWarning(String driverId, String driverName) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Suspension Warning'),
        content: Text('Add a suspension warning to $driverName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Add Warning'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final driverRef =
          FirebaseFirestore.instance.collection(USERS).doc(driverId);
      final driverDoc = await driverRef.get();
      final currentCount = (driverDoc.data()?['suspensionWarningCount'] ?? 0) as int;

      await driverRef.update({
        'suspensionWarningCount': currentCount + 1,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Suspension warning added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDrivers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add suspension warning: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Suspension'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDrivers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(_error!),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDrivers,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _drivers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.drive_eta, size: 64, color: Colors.grey),
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
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDrivers,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _drivers.length,
                        itemBuilder: (context, index) {
                          final driver = _drivers[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: driver.suspended
                                    ? Colors.red
                                    : Colors.green,
                                child: Icon(
                                  Icons.drive_eta,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                driver.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: driver.suspended
                                      ? Colors.red
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => _addSuspensionWarning(
                                          driver.driverId,
                                          driver.name,
                                        ),
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 4,
                                      children: [
                                        Icon(
                                          Icons.warning,
                                          size: 16,
                                          color: Colors.orange,
                                        ),
                                        Text(
                                          'Suspension Warning',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontSize: 12,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        if (driver.suspensionWarningCount > 0)
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${driver.suspensionWarningCount}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (driver.suspended) ...[
                                    SizedBox(height: 4),
                                    Text(
                                      'Suspended for ${driver.suspensionDate} day(s)',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (driver.suspensionStartDate != null) ...[
                                      SizedBox(height: 2),
                                      Text(
                                        'Started: ${_formatDate(driver.suspensionStartDate!.toDate())}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                              trailing: driver.suspended
                                  ? ElevatedButton(
                                      onPressed: () => _unsuspendDriver(
                                            driver.driverId,
                                            driver.name,
                                          ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text('Unsuspend'),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _suspendDriver(
                                            driver.driverId,
                                            driver.name,
                                          ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text('Suspend'),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class DriverSuspensionData {
  final String driverId;
  final String name;
  final String phoneNumber;
  final bool suspended;
  final int suspensionDate;
  final Timestamp? suspensionStartDate;
  final int suspensionWarningCount;

  DriverSuspensionData({
    required this.driverId,
    required this.name,
    required this.phoneNumber,
    required this.suspended,
    required this.suspensionDate,
    this.suspensionStartDate,
    required this.suspensionWarningCount,
  });
}

