import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/customer_suggestion.dart';
import 'package:brgy/services/customer_suggestion_service.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/main.dart';
import 'package:intl/intl.dart';

class CustomerSuggestionDetailPage extends StatefulWidget {
  final CustomerSuggestion suggestion;

  const CustomerSuggestionDetailPage({
    super.key,
    required this.suggestion,
  });

  @override
  State<CustomerSuggestionDetailPage> createState() =>
      _CustomerSuggestionDetailPageState();
}

class _CustomerSuggestionDetailPageState
    extends State<CustomerSuggestionDetailPage> {
  late CustomerSuggestion _suggestion;
  bool _isUpdating = false;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _suggestion = widget.suggestion;
    _loadSuggestion();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    final updatedSuggestion =
        await CustomerSuggestionService.getSuggestionById(_suggestion.id);
    if (updatedSuggestion != null && mounted) {
      setState(() {
        _suggestion = updatedSuggestion;
      });
    }
  }

  Future<void> _updateStatus(SuggestionStatus newStatus) async {
    if (_isUpdating) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Status Update'),
        content: Text(
          'Are you sure you want to change the status to "${newStatus.displayName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (MyAppState.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await CustomerSuggestionService.updateSuggestionStatus(
        _suggestion.id,
        newStatus,
        MyAppState.currentUser!.userID,
        MyAppState.currentUser!.fullName(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${newStatus.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadSuggestion();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _addAdminNote() async {
    if (_noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a note')),
      );
      return;
    }

    if (MyAppState.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    try {
      await CustomerSuggestionService.addAdminNote(
        _suggestion.id,
        _noteController.text.trim(),
        MyAppState.currentUser!.userID,
        MyAppState.currentUser!.fullName(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _noteController.clear();
        await _loadSuggestion();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add note: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Fetch customer name from Firestore
  Future<String> _fetchCustomerName(String userId) async {
    if (userId.isEmpty) return 'Unknown Customer';
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(USERS)
          .doc(userId)
          .get();
      
      if (!userDoc.exists) {
        return 'Unknown Customer';
      }
      
      final userData = userDoc.data();
      if (userData == null) {
        return 'Unknown Customer';
      }
      
      final firstName = userData['firstName'] ?? '';
      final lastName = userData['lastName'] ?? '';
      final fullName = '$firstName $lastName'.trim();
      
      return fullName.isEmpty ? 'Unknown Customer' : fullName;
    } catch (e) {
      print('Error fetching customer name: $e');
      return 'Unknown Customer';
    }
  }

  Color _getStatusColor(SuggestionStatus status) {
    switch (status) {
      case SuggestionStatus.new_:
        return Colors.orange;
      case SuggestionStatus.under_review:
        return Colors.blue;
      case SuggestionStatus.acknowledged:
        return Colors.green;
      case SuggestionStatus.archived:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suggestion Details'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(_suggestion.status)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getStatusColor(_suggestion.status),
                        ),
                      ),
                      child: Text(
                        _suggestion.status.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(_suggestion.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Customer Information (Read-Only)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<String>(
                      future: _suggestion.customerName.isNotEmpty
                          ? Future.value(_suggestion.customerName)
                          : _fetchCustomerName(_suggestion.customerId),
                      builder: (context, snapshot) {
                        String displayName;
                        if (_suggestion.customerName.isNotEmpty) {
                          displayName = _suggestion.customerName;
                        } else if (snapshot.connectionState == ConnectionState.waiting) {
                          displayName = 'Loading...';
                        } else if (snapshot.hasData) {
                          displayName = snapshot.data!;
                        } else {
                          displayName = 'Unknown Customer';
                        }
                        return _buildInfoRow('Customer Name', displayName);
                      },
                    ),
                    _buildInfoRow('Customer ID', _suggestion.customerId),
                    if (_suggestion.customerEmail != null)
                      _buildInfoRow('Email', _suggestion.customerEmail!),
                    if (_suggestion.customerPhone != null)
                      _buildInfoRow('Phone', _suggestion.customerPhone!),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.amber[800]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Customer information is read-only. No actions can be taken on customer accounts.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Suggestion Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Suggestion Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Suggestion ID', _suggestion.id),
                    if (_suggestion.category != null)
                      _buildInfoRow('Category', _suggestion.category!),
                    if (_suggestion.priority != null)
                      _buildInfoRow('Priority', _suggestion.priority!),
                    _buildInfoRow(
                      'Created At',
                      dateFormat.format(_suggestion.createdAt.toDate()),
                    ),
                    if (_suggestion.updatedAt != null)
                      _buildInfoRow(
                        'Last Updated',
                        dateFormat.format(_suggestion.updatedAt!.toDate()),
                      ),
                    if (_suggestion.reviewedByName != null)
                      _buildInfoRow(
                        'Reviewed By',
                        _suggestion.reviewedByName!,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Suggestion Text
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Suggestion',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _suggestion.suggestion,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Admin Notes
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Admin Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_suggestion.adminNotes.length} note(s)',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              size: 16, color: Colors.blue[800]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Admin notes are internal-only and not visible to customers.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_suggestion.adminNotes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'No admin notes yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ..._suggestion.adminNotes.map((note) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      note.adminName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      dateFormat.format(note.createdAt.toDate()),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  note.note,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          )),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        hintText: 'Add a note...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _addAdminNote,
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status Update Actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Update Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isUpdating)
                      const Center(child: CircularProgressIndicator())
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_suggestion.status != SuggestionStatus.new_)
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _updateStatus(SuggestionStatus.new_),
                              icon: const Icon(Icons.new_releases),
                              label: const Text('Set New'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          if (_suggestion.status !=
                              SuggestionStatus.under_review)
                            ElevatedButton.icon(
                              onPressed: () => _updateStatus(
                                SuggestionStatus.under_review,
                              ),
                              icon: const Icon(Icons.visibility),
                              label: const Text('Under Review'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          if (_suggestion.status !=
                              SuggestionStatus.acknowledged)
                            ElevatedButton.icon(
                              onPressed: () => _updateStatus(
                                SuggestionStatus.acknowledged,
                              ),
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Acknowledge'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          if (_suggestion.status != SuggestionStatus.archived)
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _updateStatus(SuggestionStatus.archived),
                              icon: const Icon(Icons.archive),
                              label: const Text('Archive'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

