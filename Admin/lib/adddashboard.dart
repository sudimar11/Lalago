import 'package:brgy/bulk_sms_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:brgy/settings/settings_page.dart';

import 'package:brgy/services/user_statistics_service.dart';
import 'package:brgy/services/sms_service.dart';
import 'package:brgy/services/sms_background_service.dart';
import 'package:brgy/database/database_helper.dart';
import 'dart:async';

class AddDashboard extends StatefulWidget {
  @override
  _AddDashboardState createState() => _AddDashboardState();
}

class _AddDashboardState extends State<AddDashboard> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isLoading = false;
  bool _isSendingBulkSMS = false;
  List<Map<String, dynamic>> _templates = [];
  String? _selectedTemplateId;
  bool _isLoadingTemplates = false;
  List<SimCard> _simCards = [];
  SimCard? _selectedSimCard;
  bool _isLoadingSimCards = false;
  BulkSMSService _bulkSMSService = BulkSMSService();
  UserStatisticsService _userStatisticsService = UserStatisticsService();
  SMSService _smsService = SMSService();
  SMSBackgroundService _smsBackgroundService = SMSBackgroundService();
  CampaignType _activeCampaign = CampaignType.none;

  // Stream subscriptions for proper cleanup
  StreamSubscription<QuerySnapshot>? _templatesSubscription;
  StreamSubscription? _statisticsSubscription;

  // Offline users batch loading
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<Map<String, dynamic>> _allOfflineUsers = [];
  List<Map<String, dynamic>> _currentBatchUsers = [];
  int _currentBatch = 1;
  int _batchSize = 500;
  int _totalBatches = 0;
  bool _isLoadingOfflineUsers = false;
  bool _isLoadingBatch = false;
  bool _isTestingMode = false; // Add testing mode flag

  // SMS Status tracking
  int _usersNotSent = 0;
  int _usersSent = 0;
  int _usersFailed = 0;

  // Progress tracking for bulk SMS
  double _bulkSMSProgress = 0.0;
  String _bulkSMSStatus = '';
  int _bulkSMSCurrent = 0;
  int _bulkSMSTotal = 0;

  // Inbox SMS tracking
  List<Map<String, dynamic>> _inboxMessages = [];
  bool _isLoadingInbox = false;

  @override
  void initState() {
    super.initState();
    _initializeStreamListeners();
    _loadSimCards();
    _initializeSMSService();
    _loadOfflineUsers();
    _refreshInbox(); // Load initial inbox messages
  }

  @override
  void dispose() {
    // Cancel all stream subscriptions to prevent memory leaks and duplicate listeners
    _templatesSubscription?.cancel();
    _statisticsSubscription?.cancel();

    _phoneController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _bulkSMSService.dispose();
    super.dispose();
  }

  // Initialize stream listeners only once
  // This prevents duplicate listeners and ensures proper cleanup
  void _initializeStreamListeners() {
    _loadTemplatesStream();
    _loadStatisticsStream();
  }

  // Load templates using stream listener
  // This replaces the old _loadTemplates() method to prevent duplicate listeners
  // The stream automatically updates the UI when Firestore data changes
  void _loadTemplatesStream() {
    // Cancel existing subscription if any to prevent duplicates
    _templatesSubscription?.cancel();

    setState(() {
      _isLoadingTemplates = true;
    });

    try {
      print('=== TEMPLATE STREAM LISTENER START ===');
      print('Setting up stream listener for Sending_SMS collection...');

      // Add timeout to prevent infinite loading
      Timer? timeoutTimer = Timer(Duration(seconds: 10), () {
        print('=== TEMPLATE STREAM TIMEOUT ===');
        if (mounted && _isLoadingTemplates) {
          setState(() {
            _isLoadingTemplates = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Template loading timed out. Please try again.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });

      // Try without ordering first for better performance
      _templatesSubscription = FirebaseFirestore.instance
          .collection('Sending_SMS')
          .limit(50) // Limit to 50 templates maximum
          .snapshots()
          .listen(
        (QuerySnapshot snapshot) {
          // Cancel timeout timer since we got a response
          timeoutTimer?.cancel();

          print(
              'Stream listener triggered - ${snapshot.docs.length} documents');

          if (mounted) {
            final templates = snapshot.docs
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final templateName = data['templateName'];
                  final messageContent = data['messageContent'];

                  // Validate that this is actually a template document
                  if (templateName == null && messageContent == null) {
                    return null;
                  }

                  return {
                    'id': doc.id,
                    'name': templateName ?? '',
                    'message': messageContent ?? '',
                  };
                })
                .where((template) => template != null)
                .cast<Map<String, dynamic>>()
                .toList();

            setState(() {
              _templates = templates;
              _isLoadingTemplates = false;
            });

            print(
                'Successfully updated templates: ${_templates.length} templates');
          }
        },
        onError: (error) {
          // Cancel timeout timer on error
          timeoutTimer?.cancel();

          print('=== TEMPLATE STREAM ERROR ===');
          print('Error in templates stream: $error');

          if (mounted) {
            setState(() {
              _templates = [];
              _isLoadingTemplates = false;
            });

            // Show error message to user
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading templates: ${error.toString()}'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
        },
      );

      print('=== TEMPLATE STREAM LISTENER END ===');
    } catch (e) {
      print('Error setting up templates stream: $e');
      setState(() {
        _templates = [];
        _isLoadingTemplates = false;
      });

      // Show error message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error setting up template stream: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Load statistics using stream listener
  void _loadStatisticsStream() {
    // Cancel existing subscription if any
    _statisticsSubscription?.cancel();

    try {
      // Use a periodic timer to refresh statistics
      // More frequent updates during active bulk SMS operations
      _statisticsSubscription = Stream.periodic(Duration(seconds: 10)).listen(
        (_) async {
          if (mounted) {
            // If bulk SMS is active, refresh more frequently
            if (_isSendingBulkSMS) {
              await _loadAllStatistics();
              await _loadSMSStatusStatistics();
            } else {
              // Normal refresh interval when not actively sending
              await _loadAllStatistics();
            }
          }
        },
        onError: (error) {
          print('Error in statistics stream: $error');
        },
      );

      // Load initial statistics
      _loadAllStatistics();
    } catch (e) {
      print('Error setting up statistics stream: $e');
    }
  }

  // Load offline users from SQLite
  Future<void> _loadOfflineUsers() async {
    try {
      setState(() {
        _isLoadingOfflineUsers = true;
      });

      // Load all active users from SQLite
      List<Map<String, dynamic>> offlineUsers =
          await _databaseHelper.getActiveUsers();

      // Load SMS status statistics
      await _loadSMSStatusStatistics();

      setState(() {
        _allOfflineUsers = offlineUsers;
        _totalBatches = (_allOfflineUsers.length / _batchSize).ceil();
        _isLoadingOfflineUsers = false;
      });

      // Load first batch
      _loadCurrentBatch();
    } catch (e) {
      setState(() {
        _isLoadingOfflineUsers = false;
      });
      print('Error loading offline users: $e');
    }
  }

  // Load SMS status statistics
  Future<void> _loadSMSStatusStatistics() async {
    try {
      final notSent = await _databaseHelper.getCountOfUsersNotSent();
      final sent = await _databaseHelper.getCountOfUsersSent();
      final failed = await _databaseHelper.getCountOfUsersFailed();

      setState(() {
        _usersNotSent = notSent;
        _usersSent = sent;
        _usersFailed = failed;
      });
    } catch (e) {
      print('Error loading SMS status statistics: $e');
    }
  }

  // Reset all SMS statuses (for testing purposes only)
  Future<void> _resetAllSMSStatuses() async {
    try {
      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Reset SMS Statuses'),
          content: Text(
              'This will reset all users\' SMS status to "To be sent". This is for testing purposes only. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _databaseHelper.resetAllSendingStatuses();
                await _loadSMSStatusStatistics();
                _showMessage('All SMS statuses have been reset to "To be sent"',
                    isError: false);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: Text('Reset'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('Error resetting SMS statuses: $e', isError: true);
    }
  }

  // Load current batch of offline users
  void _loadCurrentBatch() {
    if (_allOfflineUsers.isEmpty) {
      setState(() {
        _currentBatchUsers = [];
        _filteredUsers = [];
        _totalBatches = 0;
      });
      return;
    }

    int startIndex = (_currentBatch - 1) * _batchSize;
    int endIndex = startIndex + _batchSize;

    if (endIndex > _allOfflineUsers.length) {
      endIndex = _allOfflineUsers.length;
    }

    setState(() {
      _currentBatchUsers = _allOfflineUsers.sublist(startIndex, endIndex);
      _filteredUsers = _currentBatchUsers;
    });
  }

  // Refresh offline users list
  Future<void> _refreshOfflineUsers() async {
    await _loadOfflineUsers();
    await _loadSMSStatusStatistics();
  }

  // Toggle testing mode
  void _toggleTestingMode() {
    setState(() {
      _isTestingMode = !_isTestingMode;
    });
    _loadCurrentBatch(); // Reload current batch with new mode
    // Refresh statistics to reflect the new mode
    _refreshStatistics();
  }

  // Bulk SMS progress callback
  void _updateBulkSMSProgress(int current, int total, String status) {
    if (mounted) {
      setState(() {
        _bulkSMSProgress = total > 0 ? current / total : 0.0;
        _bulkSMSStatus = status;
        _bulkSMSCurrent = current;
        _bulkSMSTotal = total;

        // Reset sending state when campaign is completed or cancelled
        if (status.contains('completed') ||
            status.contains('cancelled') ||
            status.contains('Operation cancelled')) {
          _isSendingBulkSMS = false;
          _activeCampaign = CampaignType.none;
        }
      });

      // Refresh statistics more frequently during bulk SMS operation
      // Refresh every 5 SMS sent or when status changes significantly
      if (current % 5 == 0 ||
          status.contains('completed') ||
          status.contains('cancelled') ||
          status.contains('Operation cancelled') ||
          status.contains('Sending SMS to') ||
          status.contains('Batch') ||
          status.contains('Starting') ||
          status.contains('Loaded')) {
        _loadAllStatistics();
      }
    }
  }

  // Bulk SMS status change callback
  void _onSMSStatusChange(String userId, String status) {
    if (mounted) {
      // Refresh statistics immediately when any SMS status changes
      _loadAllStatistics();
      _loadSMSStatusStatistics();
    }
  }

  // Get user data with testing mode support
  Map<String, dynamic> _getUserDataWithTestingMode(Map<String, dynamic> user) {
    if (_isTestingMode) {
      return {
        ...user,
        'phoneNumber': '+639652639563', // Test phone number
        'originalPhoneNumber':
            user['phoneNumber'] ?? '', // Keep original for reference
      };
    }
    return user;
  }

  // Navigate to next batch
  void _nextBatch() {
    if (_currentBatch < _totalBatches) {
      setState(() {
        _currentBatch++;
        _isLoadingBatch = true;
      });

      // Simulate loading delay
      Future.delayed(Duration(milliseconds: 300), () {
        _loadCurrentBatch();
        setState(() {
          _isLoadingBatch = false;
        });
        // Refresh statistics when changing batches
        _refreshStatistics();
      });
    }
  }

  // Navigate to previous batch
  void _previousBatch() {
    if (_currentBatch > 1) {
      setState(() {
        _currentBatch--;
        _isLoadingBatch = true;
      });

      // Simulate loading delay
      Future.delayed(Duration(milliseconds: 300), () {
        _loadCurrentBatch();
        setState(() {
          _isLoadingBatch = false;
        });
        // Refresh statistics when changing batches
        _refreshStatistics();
      });
    }
  }

  // Go to specific batch
  void _goToBatch(int batchNumber) {
    if (batchNumber >= 1 && batchNumber <= _totalBatches) {
      setState(() {
        _currentBatch = batchNumber;
        _isLoadingBatch = true;
      });

      // Simulate loading delay
      Future.delayed(Duration(milliseconds: 300), () {
        _loadCurrentBatch();
        setState(() {
          _isLoadingBatch = false;
        });
        // Refresh statistics when changing batches
        _refreshStatistics();
      });
    }
  }

  // Delete current batch
  Future<void> _deleteCurrentBatch() async {
    if (_currentBatchUsers.isEmpty) {
      _showMessage('No users in current batch to delete', isError: true);
      return;
    }

    try {
      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Current Batch'),
          content: Text(
              'Are you sure you want to delete Batch $_currentBatch with ${_currentBatchUsers.length} users?\n\nThis action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performBatchDeletion();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('Error preparing batch deletion: $e', isError: true);
    }
  }

  // Perform the actual batch deletion
  Future<void> _performBatchDeletion() async {
    try {
      setState(() {
        _isLoadingBatch = true;
      });

      // Extract firestore IDs from current batch users
      List<String> firestoreIds = _currentBatchUsers
          .map((user) => user['id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      if (firestoreIds.isEmpty) {
        _showMessage('No valid user IDs found in current batch', isError: true);
        return;
      }

      // Delete the users from database
      int deletedCount = await _databaseHelper.deleteUsersByIds(firestoreIds);

      if (deletedCount > 0) {
        _showMessage(
            'Successfully deleted $deletedCount users from Batch $_currentBatch',
            isError: false);

        // Refresh the data
        await _loadOfflineUsers();
        await _loadSMSStatusStatistics();

        // If this was the last batch, go to previous batch
        if (_currentBatch > _totalBatches && _totalBatches > 0) {
          _goToBatch(_totalBatches);
        } else if (_totalBatches == 0) {
          // No more batches, clear current batch
          setState(() {
            _currentBatchUsers = [];
            _currentBatch = 1;
          });
        }
      } else {
        _showMessage('No users were deleted from the batch', isError: true);
      }
    } catch (e) {
      _showMessage('Error deleting batch: $e', isError: true);
    } finally {
      setState(() {
        _isLoadingBatch = false;
      });
    }
  }

  // Debug function to check collection count
  Future<void> _debugCollectionCount() async {
    try {
      print('=== COLLECTION COUNT DEBUG ===');
      print('Starting collection count query...');

      // Get total count with timeout and limit for safety
      final QuerySnapshot countSnapshot = await FirebaseFirestore.instance
          .collection('Sending_SMS')
          .limit(1000) // Limit to prevent memory issues
          .get()
          .timeout(Duration(seconds: 30)); // 30 second timeout

      print('Query completed successfully');
      print(
          'Total documents in Sending_SMS collection: ${countSnapshot.docs.length}');

      if (countSnapshot.docs.length > 1000) {
        print('WARNING: Collection has more than 1000 documents!');
        print(
            'This might be the wrong collection or there are too many documents.');
      }

      // Show first 10 document IDs
      print('First 10 document IDs:');
      for (int i = 0; i < countSnapshot.docs.length && i < 10; i++) {
        final doc = countSnapshot.docs[i];
        print('  ${i + 1}. ${doc.id}');

        // Show a sample of the document data
        try {
          final data = doc.data() as Map<String, dynamic>;
          final hasTemplateName = data.containsKey('templateName');
          final hasMessageContent = data.containsKey('messageContent');
          print('     - Has templateName: $hasTemplateName');
          print('     - Has messageContent: $hasMessageContent');
          print('     - Data keys: ${data.keys.take(5).toList()}');
        } catch (e) {
          print('     - Error reading document data: $e');
        }
      }

      print('=== END COLLECTION COUNT DEBUG ===');
    } catch (e) {
      print('=== COLLECTION COUNT ERROR ===');
      print('Error getting collection count: $e');
      print('Error type: ${e.runtimeType}');

      if (e.toString().contains('timeout')) {
        print('ERROR: Query timed out - collection might be too large');
      } else if (e.toString().contains('permission-denied')) {
        print('ERROR: Permission denied - check Firebase security rules');
      } else if (e.toString().contains('network')) {
        print('ERROR: Network issue - check internet connection');
      }
    }
  }

  // Simple debug function to check if collection exists
  Future<void> _debugCollectionExists() async {
    try {
      print('=== COLLECTION EXISTS DEBUG ===');
      print('Checking if Sending_SMS collection exists...');

      // Just get one document to check if collection exists
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('Sending_SMS')
          .limit(1)
          .get()
          .timeout(Duration(seconds: 10));

      print('Collection exists: ${snapshot.docs.isNotEmpty}');
      if (snapshot.docs.isNotEmpty) {
        print('First document ID: ${snapshot.docs.first.id}');
        final data = snapshot.docs.first.data() as Map<String, dynamic>;
        print('First document keys: ${data.keys.toList()}');
      }

      print('=== END COLLECTION EXISTS DEBUG ===');
    } catch (e) {
      print('=== COLLECTION EXISTS ERROR ===');
      print('Error checking collection: $e');
    }
  }

  // Load all statistics using the service
  Future<void> _loadAllStatistics() async {
    try {
      final result = await _userStatisticsService.loadAllStatistics();

      if (result['success']) {
        setState(() {
          // Statistics are automatically updated in the service
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading statistics: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Initialize SMS service
  Future<void> _initializeSMSService() async {
    try {
      // Check actual permission status from system, not cached value
      final PermissionStatus status = await Permission.sms.status;

      if (!status.isGranted) {
        // Show permission dialog
        final bool shouldRequestPermission =
            await _showSMSPermissionDialog(context);

        if (shouldRequestPermission) {
          // Request permission
          final bool granted = await _smsService.requestPermissions();
          if (!granted) {
            // Permission denied
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SMS permission denied. Please enable it in app settings.',
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            }
            return;
          }
        } else {
          return;
        }
      }
      // Initialize service (either permission was already granted or just granted)
      await _smsService.initialize();
    } catch (e) {
      print('Error initializing SMS service: $e');
    }
  }

  // Show SMS permission dialog
  Future<bool> _showSMSPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.sms, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('SMS Permission Required'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This app needs permission to send SMS messages to notify customers about their order status.',
                    style: TextStyle(fontSize: 15),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SMS messages will be sent automatically to inform customers.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(Icons.check),
                  label: Text('Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // Load SIM cards
  Future<void> _loadSimCards() async {
    setState(() {
      _isLoadingSimCards = true;
    });

    try {
      // Get SIM cards from SMS service (now async)
      _simCards = await _smsService.getAvailableSimCards();

      if (_simCards.isNotEmpty) {
        _selectedSimCard = _simCards.first;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading SIM cards: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoadingSimCards = false;
      });
    }
  }

  // Show message
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Create bulk SMS campaign
  Future<void> _createBulkSMSCampaign() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if we have a message
    if (_messageController.text.trim().isEmpty) {
      _showMessage('Please enter a message to send', isError: true);
      return;
    }

    // Check actual permission status from system, not cached value
    final PermissionStatus status = await Permission.sms.status;

    if (!status.isGranted) {
      // Show permission dialog
      final bool shouldRequestPermission =
          await _showSMSPermissionDialog(context);

      if (!shouldRequestPermission) {
        // User declined to grant permission
        _showMessage(
          'SMS permission is required to send bulk messages',
          isError: true,
        );
        return;
      }

      // Request permission
      final bool granted = await _smsService.requestPermissions();
      if (!granted) {
        // Permission denied
        _showMessage(
          'SMS permission denied. Please enable it in app settings.',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _activeCampaign = _isTestingMode ? CampaignType.test : CampaignType.prod;
      _bulkSMSProgress = 0.0;
      _bulkSMSStatus = 'Initializing...';
    });

    try {
      // Set progress callback
      _bulkSMSService.setProgressCallback(_updateBulkSMSProgress);
      // Set status change callback for real-time statistics updates
      _bulkSMSService.setStatusChangeCallback(_onSMSStatusChange);

      final result = _isTestingMode
          ? await _bulkSMSService.createBulkTestingCampaign(
              message: _messageController.text.trim(),
              selectedSimCard: _selectedSimCard,
            )
          : await _bulkSMSService.createBulkSMSCampaign(
              message: _messageController.text.trim(),
              selectedSimCard: _selectedSimCard,
            );

      if (result['success']) {
        _showMessage(result['message'], isError: false);
        setState(() {
          _isSendingBulkSMS = true;
        });
        // Statistics will be refreshed automatically by the stream
        await _refreshOfflineUsers(); // Refresh offline users to show updated statuses
        // Immediately refresh statistics to show current state
        await _loadAllStatistics();
        await _loadSMSStatusStatistics();
        // Also refresh SMS status statistics from the refreshed offline users
        await _loadSMSStatusStatistics();
      } else {
        _showMessage(result['message'], isError: true);
        setState(() {
          _activeCampaign = CampaignType.none;
        });
      }
    } catch (e) {
      _showMessage('Error creating bulk SMS campaign: $e', isError: true);
      setState(() {
        _activeCampaign = CampaignType.none;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Create bulk SMS testing campaign
  Future<void> _createBulkTestingCampaign() async {
    setState(() {
      _isLoading = true;
      _activeCampaign = CampaignType.test;
    });

    try {
      final result = await _bulkSMSService.createBulkTestingCampaign(
        message: _messageController.text.trim(),
        selectedSimCard: _selectedSimCard,
      );

      if (result['success']) {
        _showMessage(result['message'], isError: false);
        // Statistics will be refreshed automatically by the stream
        await _refreshOfflineUsers(); // Refresh offline users to show updated statuses
        // Immediately refresh statistics to show current state
        await _loadAllStatistics();
        await _loadSMSStatusStatistics();
        // Also refresh SMS status statistics from the refreshed offline users
        await _loadSMSStatusStatistics();
      } else {
        _showMessage(result['message'], isError: true);
        setState(() {
          _activeCampaign = CampaignType.none;
        });
      }
    } catch (e) {
      _showMessage('Error creating bulk SMS testing campaign: $e',
          isError: true);
      setState(() {
        _activeCampaign = CampaignType.none;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Cancel bulk SMS campaign
  Future<void> _cancelBulkSMS() async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Bulk SMS Campaign'),
        content: Text(
            'Are you sure you want to cancel the bulk SMS campaign? This will stop all pending SMS and mark them as cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('No, Continue'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await _bulkSMSService.cancelBulkSMS();
                setState(() {
                  _activeCampaign = CampaignType.none;
                  _isSendingBulkSMS = false;
                });
                _showMessage('Bulk SMS campaign cancelled successfully!',
                    isError: false);
                // Statistics will be refreshed automatically by the stream
                await _refreshOfflineUsers(); // Refresh offline users to show updated statuses
                // Immediately refresh statistics to show current state
                await _loadAllStatistics();
                await _loadSMSStatusStatistics();
                // Also refresh SMS status statistics from the refreshed offline users
                await _loadSMSStatusStatistics();
              } catch (e) {
                _showMessage('Error cancelling bulk SMS campaign: $e',
                    isError: true);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  // Send SMS function (single SMS) - Now requires phone number parameter
  Future<void> _sendSMS({String? phoneNumber}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // For single SMS, we need a phone number
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showMessage('Please provide a phone number for single SMS',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String message = _messageController.text.trim();

      // Send SMS using the SMS service
      Map<String, dynamic> result = await _smsService.sendSingleSMS(
        phoneNumber: phoneNumber,
        message: message,
        selectedSimCard: _selectedSimCard,
        useFallback: true,
      );

      if (result['success']) {
        _showMessage(result['message'], isError: false);
        _messageController.clear();

        // Statistics will be refreshed automatically by the stream
      } else {
        _showMessage(result['message'], isError: true);

        // Statistics will be refreshed automatically by the stream
      }
    } catch (e) {
      _showMessage('Error sending SMS: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Handle template selection
  void _onTemplateChanged(String? templateId) {
    setState(() {
      _selectedTemplateId = templateId;
      if (templateId != null) {
        final template = _templates.firstWhere((t) => t['id'] == templateId);
        _messageController.text = template['message'] ?? '';
      } else {
        _messageController.clear();
      }
    });
  }

  // Debug function to test template loading
  Future<void> _debugTemplateLoading() async {
    print('=== MANUAL TEMPLATE DEBUG START ===');
    print('Current templates count: ${_templates.length}');
    print('Current templates: $_templates');
    print('Loading state: $_isLoadingTemplates');
    print('Selected template ID: $_selectedTemplateId');

    // Force reload templates by reinitializing the stream
    _loadTemplatesStream();

    print('=== MANUAL TEMPLATE DEBUG END ===');
  }

  // Debug function to check collection performance
  Future<void> _debugCollectionPerformance() async {
    print('=== COLLECTION PERFORMANCE DEBUG ===');

    try {
      // Test simple query
      final stopwatch = Stopwatch()..start();
      final simpleSnapshot = await FirebaseFirestore.instance
          .collection('Sending_SMS')
          .limit(5)
          .get();
      stopwatch.stop();

      print('Simple query (5 docs): ${stopwatch.elapsedMilliseconds}ms');
      print('Documents found: ${simpleSnapshot.docs.length}');

      // Test ordered query
      stopwatch.reset();
      stopwatch.start();
      try {
        final orderedSnapshot = await FirebaseFirestore.instance
            .collection('Sending_SMS')
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();
        stopwatch.stop();

        print('Ordered query (5 docs): ${stopwatch.elapsedMilliseconds}ms');
        print('Documents found: ${orderedSnapshot.docs.length}');
      } catch (e) {
        stopwatch.stop();
        print('Ordered query failed: $e');
        print('This suggests missing index on createdAt field');
      }
    } catch (e) {
      print('Performance test failed: $e');
    }

    print('=== END PERFORMANCE DEBUG ===');
  }

  // Manual refresh method for templates
  void _refreshTemplates() {
    _loadTemplatesStream();
  }

  // Fallback method to load templates using simple get() instead of stream
  Future<void> _loadTemplatesFallback() async {
    setState(() {
      _isLoadingTemplates = true;
    });

    try {
      print('=== TEMPLATE FALLBACK LOADING START ===');

      // Try without ordering first (faster)
      QuerySnapshot snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('Sending_SMS')
            .limit(50)
            .get()
            .timeout(Duration(seconds: 10));
      } catch (e) {
        print('Fast query failed, trying with ordering...');
        // If that fails, try with ordering
        snapshot = await FirebaseFirestore.instance
            .collection('Sending_SMS')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get()
            .timeout(Duration(seconds: 15));
      }

      final templates = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final templateName = data['templateName'];
            final messageContent = data['messageContent'];

            if (templateName == null && messageContent == null) {
              return null;
            }

            return {
              'id': doc.id,
              'name': templateName ?? '',
              'message': messageContent ?? '',
            };
          })
          .where((template) => template != null)
          .cast<Map<String, dynamic>>()
          .toList();

      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoadingTemplates = false;
        });
      }

      print(
          '=== TEMPLATE FALLBACK LOADING END - ${templates.length} templates ===');
    } catch (e) {
      print('=== TEMPLATE FALLBACK ERROR ===');
      print('Error in fallback loading: $e');

      if (mounted) {
        setState(() {
          _templates = [];
          _isLoadingTemplates = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load templates: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Manual refresh method for statistics
  Future<void> _refreshStatistics() async {
    await _loadAllStatistics();
    await _loadSMSStatusStatistics();
  }

  // Format message timestamp
  String _formatMessageTime(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      if (timestamp is String) {
        final dateTime = DateTime.parse(timestamp);
        final now = DateTime.now();
        final difference = now.difference(dateTime);

        if (difference.inDays > 0) {
          return '${difference.inDays}d ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours}h ago';
        } else if (difference.inMinutes > 0) {
          return '${difference.inMinutes}m ago';
        } else {
          return 'Just now';
        }
      } else if (timestamp is DateTime) {
        final now = DateTime.now();
        final difference = now.difference(timestamp);

        if (difference.inDays > 0) {
          return '${difference.inDays}d ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours}h ago';
        } else if (difference.inMinutes > 0) {
          return '${difference.inMinutes}m ago';
        } else {
          return 'Just now';
        }
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  // Refresh inbox messages
  Future<void> _refreshInbox() async {
    setState(() {
      _isLoadingInbox = true;
    });

    try {
      // Get messages from SMS background service
      final messages = await _smsBackgroundService.getSMSMessages();

      if (messages.isNotEmpty) {
        // Convert database messages to display format
        final displayMessages = messages
            .map((msg) => {
                  'sender': msg['sender'] ?? 'Unknown',
                  'content': msg['content'] ?? '',
                  'timestamp': msg['timestamp'] ??
                      msg['createdAt'] ??
                      DateTime.now().toIso8601String(),
                  'id': msg['id'],
                  'isRead': msg['isRead'] == 1,
                })
            .toList();

        setState(() {
          _inboxMessages = displayMessages;
          _isLoadingInbox = false;
        });
      } else {
        // If no messages in database, show sample messages for demo
        final sampleMessages = [
          {
            'sender': '+639123456789',
            'content': 'Thank you for the update!',
            'timestamp':
                DateTime.now().subtract(Duration(minutes: 5)).toIso8601String(),
          },
          {
            'sender': '+639987654321',
            'content': 'When will the next batch be sent?',
            'timestamp':
                DateTime.now().subtract(Duration(days: 1)).toIso8601String(),
          },
          {
            'sender': '+639555555555',
            'content': 'SMS received successfully',
            'timestamp':
                DateTime.now().subtract(Duration(days: 1)).toIso8601String(),
          },
        ];

        setState(() {
          _inboxMessages = sampleMessages;
          _isLoadingInbox = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingInbox = false;
      });
      _showMessage('Error loading inbox: $e', isError: true);
    }
  }

  // Add new incoming SMS message
  void _addIncomingMessage(String sender, String content) {
    final newMessage = {
      'sender': sender,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _inboxMessages.insert(0, newMessage); // Add to beginning of list

      // Keep only last 50 messages to prevent memory issues
      if (_inboxMessages.length > 50) {
        _inboxMessages = _inboxMessages.take(50).toList();
      }
    });

    // Show notification
    _showMessage('New SMS from $sender', isError: false);
  }

  // Simulate receiving SMS for testing
  void _simulateIncomingSMS() async {
    final testSenders = [
      '+639123456789',
      '+639987654321',
      '+639555555555',
      '+639111111111',
      '+639222222222',
    ];

    final testMessages = [
      'Hello! How are you?',
      'Thank you for the information',
      'When is the next update?',
      'SMS received successfully',
      'Please call me back',
      'Meeting scheduled for tomorrow',
      'Payment received, thank you',
      'Your order has been shipped',
      'Weather alert: Heavy rain expected',
      'Happy birthday!',
    ];

    final random = DateTime.now().millisecondsSinceEpoch;
    final sender = testSenders[random % testSenders.length];
    final message = testMessages[random % testMessages.length];

    // Save to database and update UI
    await _saveTestMessage(sender, message);
    _addIncomingMessage(sender, message);
  }

  // Save test message to database
  Future<void> _saveTestMessage(String sender, String content) async {
    try {
      final timestamp = DateTime.now().toIso8601String();

      // Save to SMS background service database
      await _smsBackgroundService
          .getSMSMessages(); // This will create the table if it doesn't exist

      // For now, we'll use the existing _addIncomingMessage method
      // In a full implementation, you'd call a method to save directly to the database
      print('Test SMS saved: $sender - $content');
    } catch (e) {
      print('Error saving test SMS: $e');
    }
  }

  // Clear all inbox messages
  Future<void> _clearInbox() async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Clear Inbox'),
          content: Text(
              'Are you sure you want to clear all messages? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Clear All'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Clear messages from both UI and database
        await _smsBackgroundService.clearAllSMSMessages();
        setState(() {
          _inboxMessages.clear();
        });
        _showMessage('Inbox cleared successfully', isError: false);
      }
    } catch (e) {
      _showMessage('Error clearing inbox: $e', isError: true);
    }
  }

  // Test SMS functionality
  Future<void> _testSMSFunctionality() async {
    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic> result = await _smsService.testSMSFunctionality();

      String message = 'SMS Test Results:\n';
      message +=
          'Permissions: ${result['permissions'] ? 'Granted' : 'Denied'}\n';
      message +=
          'Phone Formatting: ${result['phoneFormatting']['isValid'] ? 'Valid' : 'Invalid'}\n';
      message += 'Available SIM Cards: ${result['availableSimCards']}\n';

      _showMessage(message, isError: !result['success']);
    } catch (e) {
      _showMessage('Error testing SMS functionality: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Search functionality
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isSearching = false;

  // Get color for sending status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'sending':
        return Colors.orange;
      case 'to be sent':
      default:
        return Colors.grey;
    }
  }

  // Filter users based on search query
  void _filterUsers(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _currentBatchUsers;
        _isSearching = false;
      });
    } else {
      setState(() {
        _isSearching = true;
        _filteredUsers = _currentBatchUsers.where((user) {
          final firstName = (user['firstName'] ?? '').toString().toLowerCase();
          final lastName = (user['lastName'] ?? '').toString().toLowerCase();
          final phoneNumber =
              (user['phoneNumber'] ?? '').toString().toLowerCase();
          final role = (user['role'] ?? '').toString().toLowerCase();
          final searchQuery = query.toLowerCase();

          return firstName.contains(searchQuery) ||
              lastName.contains(searchQuery) ||
              phoneNumber.contains(searchQuery) ||
              role.contains(searchQuery) ||
              '${firstName.trim()} ${lastName.trim()}'
                  .trim()
                  .contains(searchQuery);
        }).toList();
      });
    }
  }

  // Send SMS to specific user
  Future<void> _sendSMSToUser(Map<String, dynamic> user) async {
    final phoneNumber = user['phoneNumber'] ?? '';
    if (phoneNumber.isEmpty) {
      _showMessage('This user has no phone number', isError: true);
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      _showMessage('Please enter a message first', isError: true);
      return;
    }

    // Check if this user has already received a message
    final String userId = user['id'] ?? '';
    if (userId.isNotEmpty) {
      try {
        final List<Map<String, dynamic>> users =
            await _databaseHelper.getUsers();
        final userData = users.firstWhere(
          (u) => u['firestoreId'] == userId,
          orElse: () => {},
        );

        final String currentStatus = userData['sending_status'] ?? 'To be sent';
        if (currentStatus == 'Sent') {
          _showMessage(
              'SMS has already been sent to ${user['firstName'] ?? 'this user'}',
              isError: true);
          return;
        }
      } catch (e) {
        print('Error checking user status: $e');
        // Continue with sending if we can't check the status
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String message = _messageController.text.trim();
      String userPhone = _isTestingMode ? '+639652639563' : phoneNumber;

      // Send SMS using the SMS service
      Map<String, dynamic> result = await _smsService.sendSingleSMS(
        phoneNumber: userPhone,
        message: message,
        selectedSimCard: _selectedSimCard,
        useFallback: true,
      );

      if (result['success']) {
        _showMessage('SMS sent successfully to ${user['firstName'] ?? 'User'}',
            isError: false);

        // Update user status to 'Sent' in database
        if (userId.isNotEmpty) {
          try {
            await _databaseHelper.updateSendingStatus(userId, 'Sent');
          } catch (e) {
            print('Error updating user status: $e');
          }
        }

        // Refresh statistics
        await _loadSMSStatusStatistics();
      } else {
        _showMessage('Failed to send SMS: ${result['message']}', isError: true);

        // Update user status to 'Failed' in database
        if (userId.isNotEmpty) {
          try {
            await _databaseHelper.updateSendingStatus(userId, 'Failed');
          } catch (e) {
            print('Error updating user status: $e');
          }
        }
      }
    } catch (e) {
      _showMessage('Error sending SMS: $e', isError: true);

      // Update user status to 'Failed' in database on error
      if (userId.isNotEmpty) {
        try {
          await _databaseHelper.updateSendingStatus(userId, 'Failed');
        } catch (dbError) {
          print('Error updating user status on exception: $dbError');
        }
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Settings Icon
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: Icon(Icons.settings, color: Colors.orange[800]),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsPage(),
                      ),
                    );
                  },
                ),
              ),

              // Combined SMS Status Statistics and Bulk SMS Progress Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [Colors.blue[50]!, Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with both titles
                      Row(
                        children: [
                          Icon(
                            Icons.sms,
                            color: Colors.blue[600],
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SMS Status Statistics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                          if (_activeCampaign != CampaignType.none) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.send,
                                    color: Colors.orange[700],
                                    size: 16,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Campaign Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 16),

                      // SMS Status Statistics Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Not Sent Indicator
                          Column(
                            children: [
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  value: (_usersNotSent +
                                              _usersSent +
                                              _usersFailed) >
                                          0
                                      ? (_usersNotSent /
                                              (_usersNotSent +
                                                  _usersSent +
                                                  _usersFailed))
                                          .clamp(0.0, 1.0)
                                      : 0.0,
                                  strokeWidth: 6,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.orange),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Not Sent',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange[700],
                                ),
                              ),
                              Text(
                                '$_usersNotSent',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),

                          // Sent Indicator
                          Column(
                            children: [
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  value: (_usersNotSent +
                                              _usersSent +
                                              _usersFailed) >
                                          0
                                      ? (_usersSent /
                                              (_usersNotSent +
                                                  _usersSent +
                                                  _usersFailed))
                                          .clamp(0.0, 1.0)
                                      : 0.0,
                                  strokeWidth: 6,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.green),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Sent',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green[700],
                                ),
                              ),
                              Text(
                                '$_usersSent',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),

                          // Failed Indicator
                          Column(
                            children: [
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  value: (_usersNotSent +
                                              _usersSent +
                                              _usersFailed) >
                                          0
                                      ? (_usersFailed /
                                              (_usersNotSent +
                                                  _usersSent +
                                                  _usersFailed))
                                          .clamp(0.0, 1.0)
                                      : 0.0,
                                  strokeWidth: 6,
                                  backgroundColor: Colors.grey[300],
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.red),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Failed',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.red[700],
                                ),
                              ),
                              Text(
                                '$_usersFailed',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 16),

                      // Bulk SMS Progress Section (only show when campaign is active)
                      if (_activeCampaign != CampaignType.none) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.trending_up,
                                    color: Colors.orange[600],
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Bulk SMS Progress',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      value: _bulkSMSProgress,
                                      strokeWidth: 3,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _bulkSMSStatus.contains('cancelled')
                                            ? Colors.orange
                                            : Colors.blue,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Progress: ${(_bulkSMSProgress * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          _bulkSMSStatus,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        if (_bulkSMSTotal > 0) ...[
                                          SizedBox(height: 2),
                                          Text(
                                            'SMS: $_bulkSMSCurrent/$_bulkSMSTotal',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                      ],

                      // Info and Control Section
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue[600],
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Only users with "To be sent" status will receive SMS in new campaigns',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _resetAllSMSStatuses,
                                    icon: Icon(Icons.refresh, size: 16),
                                    label: Text(
                                      'Reset All Statuses (Testing)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.orange[700],
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _refreshStatistics,
                                    icon: Icon(Icons.update, size: 16),
                                    label: Text(
                                      'Refresh Stats',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue[700],
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // Offline Users List
              if (_isLoadingOfflineUsers)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading offline users...',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_allOfflineUsers.isEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No offline users found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Users will appear here after saving from online mode',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Colors.blue[50]!, Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.storage,
                                  color: Colors.blue[600],
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Offline Users',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_allOfflineUsers.length} total',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                // Testing Mode Toggle
                                GestureDetector(
                                  onTap: _toggleTestingMode,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _isTestingMode
                                          ? Colors.orange[100]
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _isTestingMode
                                            ? Colors.orange[300]!
                                            : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isTestingMode
                                              ? Icons.science
                                              : Icons.science_outlined,
                                          size: 16,
                                          color: _isTestingMode
                                              ? Colors.orange[700]
                                              : Colors.grey[600],
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          _isTestingMode ? 'Testing' : 'Normal',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: _isTestingMode
                                                ? Colors.orange[700]
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16),

                        // Status Legend
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isTestingMode
                                ? Colors.orange[50]
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isTestingMode
                                  ? Colors.orange[200]!
                                  : Colors.blue[200]!,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      _isTestingMode
                                          ? Icons.science
                                          : Icons.info_outline,
                                      color: _isTestingMode
                                          ? Colors.orange[600]
                                          : Colors.blue[600],
                                      size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _isTestingMode
                                          ? 'Testing Mode - All SMS will be sent to +639652639563'
                                          : 'Status Legend:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _isTestingMode
                                            ? Colors.orange[700]
                                            : Colors.blue[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!_isTestingMode) ...[
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'To be sent',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Sending',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Sent',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Failed',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        // Batch Navigation
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Batch info
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Batch $_currentBatch of $_totalBatches',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[700],
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '(${_currentBatchUsers.length} users)',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Navigation buttons
                              Row(
                                children: [
                                  // Previous button
                                  IconButton(
                                    icon: Icon(Icons.chevron_left, size: 16),
                                    onPressed:
                                        _currentBatch > 1 && !_isLoadingBatch
                                            ? _previousBatch
                                            : null,
                                    color: _currentBatch > 1
                                        ? Colors.blue[600]
                                        : Colors.grey,
                                    padding: EdgeInsets.all(4),
                                    constraints: BoxConstraints(
                                        minWidth: 24, minHeight: 24),
                                  ),

                                  // Batch selector
                                  Container(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 2),
                                    child: DropdownButton<int>(
                                      value: _currentBatch,
                                      items:
                                          List.generate(_totalBatches, (index) {
                                        return DropdownMenuItem<int>(
                                          value: index + 1,
                                          child: Text(
                                            'B${index + 1}',
                                            style: TextStyle(fontSize: 11),
                                          ),
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
                                      icon:
                                          Icon(Icons.arrow_drop_down, size: 16),
                                    ),
                                  ),

                                  // Next button
                                  IconButton(
                                    icon: Icon(Icons.chevron_right, size: 16),
                                    onPressed: _currentBatch < _totalBatches &&
                                            !_isLoadingBatch
                                        ? _nextBatch
                                        : null,
                                    color: _currentBatch < _totalBatches
                                        ? Colors.blue[600]
                                        : Colors.grey,
                                    padding: EdgeInsets.all(4),
                                    constraints: BoxConstraints(
                                        minWidth: 24, minHeight: 24),
                                  ),

                                  // Delete batch button
                                  SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(4),
                                      border:
                                          Border.all(color: Colors.red[200]!),
                                    ),
                                    child: IconButton(
                                      icon:
                                          Icon(Icons.delete_outline, size: 16),
                                      onPressed:
                                          _currentBatchUsers.isNotEmpty &&
                                                  !_isLoadingBatch
                                              ? _deleteCurrentBatch
                                              : null,
                                      color: _currentBatchUsers.isNotEmpty
                                          ? Colors.red[600]
                                          : Colors.grey,
                                      padding: EdgeInsets.all(4),
                                      constraints: BoxConstraints(
                                          minWidth: 24, minHeight: 24),
                                      tooltip: 'Delete Current Batch',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        // SIM Card Selection - Icon-based Before Users List
                        if (!_isLoadingSimCards) ...[
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.sim_card,
                                      color: Colors.blue[700],
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Select SIM Card:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: _simCards.map((SimCard simCard) {
                                    final isSelected =
                                        _selectedSimCard == simCard;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _selectedSimCard = simCard;
                                          });
                                        },
                                        child: Container(
                                          margin: EdgeInsets.symmetric(
                                              horizontal: 4),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.blue[100]
                                                : Colors.grey[50],
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.blue[600]!
                                                  : Colors.grey[300]!,
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.sim_card,
                                                color: isSelected
                                                    ? Colors.blue[700]
                                                    : Colors.grey[600],
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                simCard.displayName,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? Colors.blue[700]
                                                      : Colors.grey[700],
                                                ),
                                              ),
                                              if (isSelected) ...[
                                                SizedBox(width: 6),
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.blue[600],
                                                  size: 16,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                        ],

                        // SMS Form Card - Compact design
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [Colors.white, Colors.orange[50]!],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send SMS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                  SizedBox(height: 16),

                                  // Template Selection from Sending_SMS collection
                                  Text(
                                    'Select Template:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  if (_isLoadingTemplates)
                                    Container(
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.grey[300]!),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                          SizedBox(width: 12),
                                          Text('Loading templates...',
                                              style: TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      value: _selectedTemplateId,
                                      decoration: InputDecoration(
                                        labelText: _templates.isEmpty
                                            ? 'No templates available'
                                            : 'Choose a template',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                        prefixIcon: Icon(Icons.description,
                                            color: Colors.blue[600]),
                                      ),
                                      items: [
                                        DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('No Template',
                                              style: TextStyle(fontSize: 14)),
                                        ),
                                        ..._templates.map((template) {
                                          return DropdownMenuItem<String>(
                                            value: template['id'],
                                            child: Text(template['name'],
                                                style: TextStyle(fontSize: 14)),
                                          );
                                        }).toList(),
                                      ],
                                      onChanged: _templates.isEmpty
                                          ? null
                                          : _onTemplateChanged,
                                    ),

                                  // Debug: Show template count and reload button
                                  if (_templates.isNotEmpty)
                                    Container(
                                      margin: EdgeInsets.only(top: 8),
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.green[200]!),
                                      ),
                                    )
                                  else if (!_isLoadingTemplates)
                                    Container(
                                      margin: EdgeInsets.only(top: 8),
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.orange[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.warning,
                                              color: Colors.orange[600],
                                              size: 16),
                                          SizedBox(width: 8),
                                          Text(
                                            'No templates found',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Spacer(),
                                          TextButton(
                                            onPressed: _refreshTemplates,
                                            child: Text(
                                              'Retry',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          TextButton(
                                            onPressed: _loadTemplatesFallback,
                                            child: Text(
                                              'Fallback',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(height: 16),

                                  // Message Input
                                  Text(
                                    'Message:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextFormField(
                                    controller: _messageController,
                                    decoration: InputDecoration(
                                      labelText: 'Enter your message',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      prefixIcon: Icon(Icons.message,
                                          color: Colors.orange[600]),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 12),
                                    ),
                                    maxLines: 4,
                                    style: TextStyle(fontSize: 14),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter a message';
                                      }
                                      return null;
                                    },
                                    onChanged: (value) {
                                      setState(() {
                                        // Trigger rebuild to update character count
                                      });
                                    },
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_messageController.text.length} characters',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _messageController
                                                      .text.length >
                                                  160
                                              ? Colors.red[600]
                                              : _messageController.text.length >
                                                      140
                                                  ? Colors.orange[600]
                                                  : Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (_messageController.text.length >
                                          160) ...[
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.warning,
                                          size: 14,
                                          color: Colors.red[600],
                                        ),
                                        Text(
                                          ' (${(_messageController.text.length / 160).ceil()} SMS)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Receive SMS Card
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.inbox,
                                    color: Colors.green[700],
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Receive SMS:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  Spacer(),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: Colors.green[300]!),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sms,
                                          color: Colors.green[700],
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Inbox',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green[200]!),
                                ),
                                child: _isLoadingInbox
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                            Color>(
                                                        Colors.green[600]!),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Loading inbox...',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : _inboxMessages.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.inbox_outlined,
                                                  size: 32,
                                                  color: Colors.green[300],
                                                ),
                                                SizedBox(height: 8),
                                                Text(
                                                  'No messages',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.green[600],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  'Incoming SMS will appear here',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green[500],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: _inboxMessages.length,
                                            itemBuilder: (context, index) {
                                              final message =
                                                  _inboxMessages[index];
                                              return Container(
                                                margin: EdgeInsets.symmetric(
                                                    vertical: 2, horizontal: 4),
                                                padding: EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.green[50],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color:
                                                          Colors.green[100]!),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.person,
                                                          size: 14,
                                                          color:
                                                              Colors.green[700],
                                                        ),
                                                        SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            message['sender'] ??
                                                                'Unknown',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors
                                                                  .green[800],
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          _formatMessageTime(
                                                              message[
                                                                  'timestamp']),
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors
                                                                .green[600],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      message['content'] ?? '',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            Colors.green[700],
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: _refreshInbox,
                                      icon: Icon(Icons.refresh, size: 14),
                                      label: Text(
                                        'Refresh',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.green[700],
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: _simulateIncomingSMS,
                                      icon: Icon(Icons.add, size: 14),
                                      label: Text(
                                        'Test SMS',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue[600],
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: _clearInbox,
                                      icon: Icon(Icons.clear_all, size: 14),
                                      label: Text(
                                        'Clear',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red[600],
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        // Search Box
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: Colors.blue[600],
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Search Users:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  if (_isSearching) ...[
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_filteredUsers.length} found',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText:
                                      'Search by name, phone number, or role...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  prefixIcon: Icon(Icons.person_search,
                                      color: Colors.blue[600]),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.clear,
                                              color: Colors.grey[600]),
                                          onPressed: () {
                                            _searchController.clear();
                                            _filterUsers('');
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: _filterUsers,
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),

                        // Users List
                        if (_isLoadingBatch)
                          Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 8),
                                Text(
                                  'Loading batch $_currentBatch...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: _filteredUsers.isEmpty
                                ? Center(
                                    child: Column(
                                      children: [
                                        Icon(
                                          _isSearching
                                              ? Icons.search_off
                                              : Icons.people_outline,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          _isSearching
                                              ? 'No users found'
                                              : 'No users in this batch',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        if (_isSearching) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            'Try a different search term',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _filteredUsers.length,
                                    itemBuilder: (context, index) {
                                      final originalUser =
                                          _filteredUsers[index];
                                      final user = _getUserDataWithTestingMode(
                                          originalUser);
                                      final firstName = user['firstName'] ?? '';
                                      final lastName = user['lastName'] ?? '';
                                      final phoneNumber =
                                          user['phoneNumber'] ?? '';
                                      final originalPhoneNumber =
                                          user['originalPhoneNumber'] ??
                                              phoneNumber;
                                      final role = user['role'] ?? '';
                                      final active = user['active'] ?? false;
                                      final sendingStatus =
                                          user['sending_status'] ??
                                              'To be sent';

                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.blue[100]!,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: active
                                                ? Colors.green[100]
                                                : Colors.grey[100],
                                            child: Icon(
                                              active
                                                  ? Icons.person
                                                  : Icons.person_off,
                                              color: active
                                                  ? Colors.green[600]
                                                  : Colors.grey[600],
                                              size: 20,
                                            ),
                                          ),
                                          title: Text(
                                            '${firstName.trim()} ${lastName.trim()}'
                                                    .trim()
                                                    .isEmpty
                                                ? 'Unknown User'
                                                : '${firstName.trim()} ${lastName.trim()}'
                                                    .trim(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: active
                                                  ? Colors.black87
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                phoneNumber.isEmpty
                                                    ? 'No phone number'
                                                    : phoneNumber,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: _isTestingMode
                                                      ? Colors.orange[700]
                                                      : Colors.grey[600],
                                                  fontWeight: _isTestingMode
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                              if (_isTestingMode &&
                                                  originalPhoneNumber !=
                                                      phoneNumber)
                                                Text(
                                                  'Original: $originalPhoneNumber',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[500],
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              if (role.isNotEmpty)
                                                Text(
                                                  'Role: $role',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.blue[600],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Individual SMS Button
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.green[50],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color:
                                                          Colors.green[200]!),
                                                ),
                                                child: IconButton(
                                                  icon:
                                                      Icon(Icons.sms, size: 16),
                                                  onPressed: _isLoading
                                                      ? null
                                                      : () => _sendSMSToUser(
                                                          originalUser),
                                                  color: Colors.green[600],
                                                  padding: EdgeInsets.all(4),
                                                  constraints: BoxConstraints(
                                                      minWidth: 24,
                                                      minHeight: 24),
                                                  tooltip:
                                                      'Send SMS to ${user['firstName'] ?? 'User'}',
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              // Status indicators
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  // Status indicator
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: _getStatusColor(
                                                          sendingStatus),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      sendingStatus,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  // Active/Inactive indicator
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: active
                                                          ? Colors.green[100]
                                                          : Colors.grey[100],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Text(
                                                      active
                                                          ? 'Active'
                                                          : 'Inactive',
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: active
                                                            ? Colors.green[700]
                                                            : Colors.grey[600],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Bulk SMS Button below users list
              if (_currentBatchUsers.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(top: 16),
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading ||
                            _isSendingBulkSMS ||
                            _activeCampaign != CampaignType.none)
                        ? null
                        : _createBulkSMSCampaign,
                    icon: (_activeCampaign == CampaignType.prod ||
                            _activeCampaign == CampaignType.test)
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.send, size: 20),
                    label: (_activeCampaign == CampaignType.prod ||
                            _activeCampaign == CampaignType.test)
                        ? Text('Sending Bulk SMS...')
                        : Text(_isTestingMode
                            ? 'Send Bulk SMS to Test Number'
                            : 'Send Bulk SMS to All Users'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
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
