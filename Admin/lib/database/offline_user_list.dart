import 'package:flutter/material.dart';
import 'package:brgy/database/database_helper.dart';

class OfflineUserListPage extends StatefulWidget {
  @override
  _OfflineUserListPageState createState() => _OfflineUserListPageState();
}

class _OfflineUserListPageState extends State<OfflineUserListPage> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadOfflineUsers();
  }

  Future<void> _loadOfflineUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load users from SQLite database
      List<Map<String, dynamic>> users = await _databaseHelper.getActiveUsers();

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading offline users: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _clearOfflineData() async {
    try {
      await _databaseHelper.clearUsers();
      setState(() {
        _users = [];
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Offline data cleared successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing offline data: $e'),
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
      appBar: AppBar(
        title: Text('Offline Users'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadOfflineUsers,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(Icons.delete_forever),
            onPressed: _users.isEmpty ? null : _clearOfflineData,
            tooltip: 'Clear offline data',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20.0),
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
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storage,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline User List',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${_users.length} users stored locally',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

            // Content
            if (_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Loading offline users...',
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
                        onPressed: _loadOfflineUsers,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_users.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No offline users found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Save users from the main User List first',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Table(
                        columnWidths: {
                          0: FlexColumnWidth(0.8), // No.
                          1: FlexColumnWidth(2.2), // Name
                          2: FlexColumnWidth(2.2), // Number
                          3: FlexColumnWidth(1.3), // Status
                          4: FlexColumnWidth(1.3), // Role
                        },
                        children: [
                          TableRow(
                            children: [
                              _buildHeaderCell('No.'),
                              _buildHeaderCell('Name'),
                              _buildHeaderCell('Number'),
                              _buildHeaderCell('Status'),
                              _buildHeaderCell('Role'),
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
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.builder(
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            String fullName = '${user['firstName']?.trim() ?? ''} ${user['lastName']?.trim() ?? ''}'.trim();
                            if (fullName.isEmpty) {
                              fullName = 'Unknown User';
                            }
                            
                            return Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.orange.withOpacity(0.1),
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
                                  4: FlexColumnWidth(1.3), // Role
                                },
                                children: [
                                  TableRow(
                                    children: [
                                      _buildDataCell('${index + 1}'),
                                      _buildDataCell(fullName),
                                      _buildDataCell(user['phoneNumber'] ?? ''),
                                      _buildDataCell(user['active'] ? 'Active' : 'Inactive'),
                                      _buildDataCell(user['role'] ?? ''),
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
}
