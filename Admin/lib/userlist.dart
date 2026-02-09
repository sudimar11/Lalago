import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/database/database_helper.dart';

class UserListPage extends StatefulWidget {
  @override
  _UserListPageState createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  List<UserData> _users = [];
  List<UserData> _allUsers = []; // Store all users for batch processing
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;
  bool _isOfflineMode = false;
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  // Batch pagination variables
  int _currentBatch = 1;
  int _batchSize = 500;
  int _totalBatches = 0;
  bool _isLoadingBatch = false;
  DocumentSnapshot? _lastDocument; // For Firestore pagination

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    // Cancel any ongoing operations
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
        _currentBatch = 1;
        _lastDocument = null;
      });

      List<UserData> users = [];

      if (_isOfflineMode) {
        // Load from SQLite database
        List<Map<String, dynamic>> offlineUsers =
            await _databaseHelper.getActiveUsers();

        for (Map<String, dynamic> userData in offlineUsers) {
          String firstName = userData['firstName'] ?? '';
          String lastName = userData['lastName'] ?? '';
          String phoneNumber = userData['phoneNumber'] ?? '';
          bool active = userData['active'] ?? false;
          String role = userData['role'] ?? '';

          // Create full name
          String fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
          if (fullName.isEmpty) {
            fullName = 'Unknown User';
          }

          // Create status based on active field
          String status = active ? 'Active' : 'Inactive';

          // Assign batch number (1-500 per batch)
          int userIndex = users.length;
          int batchNumber = (userIndex ~/ _batchSize) + 1;
          String batch = 'Batch $batchNumber';

          users.add(UserData(
            name: fullName,
            number: phoneNumber,
            status: status,
            batch: batch,
          ));
        }

        _allUsers = users;
        _totalBatches = (_allUsers.length / _batchSize).ceil();
        _loadCurrentBatch();
      } else {
        // Load from Firestore with pagination
        await _loadUsersFromFirestore();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading users: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUsersFromFirestore() async {
    try {
      List<UserData> allUsers = [];
      DocumentSnapshot? lastDoc = null;
      int pageCount = 0;

      while (true) {
        // Check if widget is still mounted
        if (!mounted) return;

        // Build query
        Query query = FirebaseFirestore.instance
            .collection(USERS)
            .where('active', isEqualTo: true);

        // Apply pagination
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }
        query = query.limit(500); // Load 500 users per page

        // Execute query
        QuerySnapshot querySnapshot = await query.get();

        if (querySnapshot.docs.isEmpty) {
          break; // No more documents
        }

        // Process documents
        for (QueryDocumentSnapshot doc in querySnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          // Extract user data from Firestore document
          String firstName = data['firstName'] ?? '';
          String lastName = data['lastName'] ?? '';
          String phoneNumber = data['phoneNumber'] ?? '';
          bool active = data['active'] ?? false;
          String role = data['role'] ?? '';

          // Create full name
          String fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
          if (fullName.isEmpty) {
            fullName = 'Unknown User';
          }

          // Create status based on active field
          String status = active ? 'Active' : 'Inactive';

          // Assign batch number (1-500 per batch)
          int userIndex = allUsers.length;
          int batchNumber = (userIndex ~/ _batchSize) + 1;
          String batch = 'Batch $batchNumber';

          allUsers.add(UserData(
            name: fullName,
            number: phoneNumber,
            status: status,
            batch: batch,
          ));
        }

        lastDoc = querySnapshot.docs.last;
        pageCount++;

        // Update progress
        if (mounted) {
          setState(() {
            _error = 'Loading page $pageCount...';
          });
        }

        // Small delay to prevent overwhelming Firestore
        await Future.delayed(Duration(milliseconds: 100));
      }

      _allUsers = allUsers;
      _totalBatches = (_allUsers.length / _batchSize).ceil();
      _loadCurrentBatch();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading users from Firestore: $e';
        });
      }
    }
  }

  void _loadCurrentBatch() {
    if (!mounted) return;

    if (_allUsers.isEmpty) {
      setState(() {
        _users = [];
        _totalBatches = 0;
      });
      return;
    }

    int startIndex = (_currentBatch - 1) * _batchSize;
    int endIndex = startIndex + _batchSize;

    if (endIndex > _allUsers.length) {
      endIndex = _allUsers.length;
    }

    setState(() {
      _users = _allUsers.sublist(startIndex, endIndex);
      _totalBatches = (_allUsers.length / _batchSize).ceil();
    });
  }

  void _nextBatch() {
    if (_currentBatch < _totalBatches) {
      setState(() {
        _currentBatch++;
        _isLoadingBatch = true;
      });

      // Simulate loading delay
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

      // Simulate loading delay
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

      // Simulate loading delay
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

  // Toggle between online and offline mode
  void _toggleMode() {
    setState(() {
      _isOfflineMode = !_isOfflineMode;
    });
    _loadUsers(); // Reload data with new mode
  }

  // Save users to offline database
  Future<void> _saveToOffline() async {
    try {
      if (!mounted) return;
      setState(() {
        _isSaving = true;
      });

      // Check if database needs migration
      bool needsMigration = await _databaseHelper.needsMigration();
      if (needsMigration) {
        // Force migration before saving
        await _databaseHelper.forceMigration();
      }

      // Get the raw Firestore data for saving
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('active', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> usersData = [];
      for (QueryDocumentSnapshot doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add the document ID
        // Ensure sending_status is included with default value
        data['sending_status'] = data['sending_status'] ?? 'To be sent';
        usersData.add(data);
      }

      // Save to SQLite database
      await _databaseHelper.saveUsers(usersData);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Users saved to offline storage successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving to offline: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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
            // Header with refresh button
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
                          Icons.people,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User List',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _isOfflineMode ? Icons.storage : Icons.cloud,
                                color: Colors.grey[300],
                                size: 12,
                              ),
                              SizedBox(width: 3),
                              Text(
                                _isOfflineMode ? 'Offline Mode' : 'Online Mode',
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Online/Offline toggle
                      Container(
                        margin: EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Text(
                              'Online',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 4),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _isOfflineMode,
                                onChanged: (value) => _toggleMode(),
                                activeColor: Colors.orange,
                                activeTrackColor:
                                    Colors.orange.withOpacity(0.3),
                                inactiveThumbColor: Colors.grey[400],
                                inactiveTrackColor: Colors.grey[600],
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Offline',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Save to offline button (only show in online mode)
                      if (!_isOfflineMode)
                        Container(
                          margin: EdgeInsets.only(right: 4),
                          child: ElevatedButton.icon(
                            onPressed:
                                _isSaving || _isLoading ? null : _saveToOffline,
                            icon: _isSaving
                                ? SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Icon(Icons.download,
                                    color: Colors.white, size: 12),
                            label: Text(
                              'Save',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              minimumSize: Size(0, 28),
                            ),
                          ),
                        ),
                      // Refresh button
                      IconButton(
                        icon:
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: _isLoading ? null : _loadUsers,
                        tooltip: 'Refresh',
                        padding: EdgeInsets.all(8),
                        constraints:
                            BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      // Reset Database button
                      IconButton(
                        icon: Icon(Icons.delete_sweep,
                            color: Colors.red[300], size: 20),
                        onPressed: _isLoading ? null : _showResetConfirmation,
                        tooltip: 'Reset Database',
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

            // Batch Navigation
            if (!_isLoading && _error == null && _totalBatches > 0)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Batch info
                    Row(
                      children: [
                        Icon(Icons.list, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Batch $_currentBatch of $_totalBatches',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '(${_users.length} users)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    // Navigation buttons
                    Row(
                      children: [
                        // Previous button
                        IconButton(
                          icon: Icon(Icons.chevron_left),
                          onPressed: _currentBatch > 1 && !_isLoadingBatch
                              ? _previousBatch
                              : null,
                          color:
                              _currentBatch > 1 ? Colors.orange : Colors.grey,
                        ),

                        // Batch selector
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: DropdownButton<int>(
                            value: _currentBatch,
                            items: List.generate(_totalBatches, (index) {
                              return DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text('Batch ${index + 1}'),
                              );
                            }),
                            onChanged: _isLoadingBatch
                                ? null
                                : (value) {
                                    if (value != null) {
                                      _goToBatch(value);
                                    }
                                  },
                            underline: Container(),
                          ),
                        ),

                        // Next button
                        IconButton(
                          icon: Icon(Icons.chevron_right),
                          onPressed:
                              _currentBatch < _totalBatches && !_isLoadingBatch
                                  ? _nextBatch
                                  : null,
                          color: _currentBatch < _totalBatches
                              ? Colors.orange
                              : Colors.grey,
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
                        _isOfflineMode
                            ? 'Loading offline users...'
                            : 'Loading online users...',
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
                        onPressed: _loadUsers,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Content
              Expanded(
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Table(
                        columnWidths: {
                          0: FlexColumnWidth(0.8), // No.
                          1: FlexColumnWidth(2.2), // Name
                          2: FlexColumnWidth(2.2), // Number
                          3: FlexColumnWidth(1.3), // Status
                          4: FlexColumnWidth(1.3), // Batch
                        },
                        children: [
                          TableRow(
                            children: [
                              _buildHeaderCell('No.'),
                              _buildHeaderCell('Name'),
                              _buildHeaderCell('Number'),
                              _buildHeaderCell('Status'),
                              _buildHeaderCell('Batch'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 8),

                    // User List
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isLoadingBatch
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                            : _users.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.people_outline,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          _isOfflineMode
                                              ? 'No offline users found'
                                              : 'No users found',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _users.length,
                                    itemBuilder: (context, index) {
                                      final user = _users[index];
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
                                            0: FlexColumnWidth(0.8), // No.
                                            1: FlexColumnWidth(2.2), // Name
                                            2: FlexColumnWidth(2.2), // Number
                                            3: FlexColumnWidth(1.3), // Status
                                            4: FlexColumnWidth(1.3), // Batch
                                          },
                                          children: [
                                            TableRow(
                                              children: [
                                                _buildDataCell('${index + 1}'),
                                                _buildDataCell(user.name),
                                                _buildDataCell(user.number),
                                                _buildDataCell(user.status),
                                                _buildDataCell(user.batch),
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
          fontSize: 12,
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
          fontSize: 11,
          color: text.isEmpty ? Colors.grey : Colors.black87,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  // Show reset confirmation dialog
  void _showResetConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('Reset Database'),
            ],
          ),
          content: Text(
            'Are you sure you want to reset all database records? This action will:\n\n'
            '• Delete all user records\n'
            '• Reset all counters to 0\n'
            '• This action cannot be undone\n\n'
            'This will only affect offline mode data.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetDatabase();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Reset Database'),
            ),
          ],
        );
      },
    );
  }

  // Reset database function
  Future<void> _resetDatabase() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Reset the database
      await _databaseHelper.resetAllDatabaseRecords();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database reset successfully! All records cleared.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Reload users to show empty state
      await _loadUsers();
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error resetting database: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

// User data model
class UserData {
  final String name;
  final String number;
  final String status;
  final String batch;

  UserData({
    required this.name,
    required this.number,
    required this.status,
    required this.batch,
  });
}
