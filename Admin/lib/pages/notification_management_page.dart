import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

class NotificationManagementPage extends StatefulWidget {
  const NotificationManagementPage({super.key});

  @override
  State<NotificationManagementPage> createState() =>
      _NotificationManagementPageState();
}

class _NotificationManagementPageState
    extends State<NotificationManagementPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _deepLinkController = TextEditingController();

  String _notificationType = 'announcement';
  String? _targetScreen;
  bool _isSending = false;

  final List<String> _targetScreenOptions = [
    'home',
    'orders',
    'profile',
    'restaurants',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _deepLinkController.dispose();
    super.dispose();
  }

  Future<String> _getRegion() async {
    try {
      // Try to fetch region from Firestore settings
      final regionDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('cloudFunctionsRegion')
          .get()
          .timeout(const Duration(seconds: 5));

      if (regionDoc.exists && regionDoc.data() != null) {
        final region = regionDoc.data()!['region'] as String?;
        if (region != null && region.isNotEmpty) {
          print('[BroadcastNotification] Using region from Firestore settings: $region');
          return region;
        }
      }
    } catch (e) {
      print('[BroadcastNotification] Error fetching region from Firestore: $e');
      // Continue to fallback
    }

    // Fallback: Based on DEPLOY_NOW.md, database is in asia-southeast1
    // Functions are typically deployed to the same region as the database
    print('[BroadcastNotification] Using default region: us-central1');
    return 'us-central1';
  }

  Future<void> _handleSendNotification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Show confirmation dialog with preview
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Broadcast Notification'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will send a notification to all active customers. Continue?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildPreviewCard(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    // Prevent double-send
    if (_isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // Get Firebase project ID
      final projectId = Firebase.app().options.projectId;

      // Get region dynamically from Firestore or use default
      final region = await _getRegion();

      // Construct Cloud Function URL
      final functionUrl =
          'https://$region-$projectId.cloudfunctions.net/sendBroadcastNotifications';

      // Build request payload
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'type': _notificationType,
      };

      // Add optional fields
      if (_imageUrlController.text.trim().isNotEmpty) {
        payload['imageUrl'] = _imageUrlController.text.trim();
      }

      if (_deepLinkController.text.trim().isNotEmpty) {
        payload['deepLink'] = _deepLinkController.text.trim();
      }

      if (_targetScreen != null && _targetScreen!.isNotEmpty) {
        payload['targetScreen'] = _targetScreen;
      }

      print('[BroadcastNotification] Calling function URL: $functionUrl');
      print('[BroadcastNotification] Payload: ${jsonEncode(payload)}');

      // Call Cloud Function
      final response = await http
          .post(
            Uri.parse(functionUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      // Close loading indicator
      if (mounted) {
        Navigator.of(context).pop();
      }

      print('[BroadcastNotification] Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final responseData =
              jsonDecode(response.body) as Map<String, dynamic>;
          final sentCount = responseData['sentCount'] ?? 0;
          final errorCount = responseData['errorCount'] ?? 0;
          final totalUsers = responseData['totalUsers'] ?? 0;

          print(
              '[BroadcastNotification] Response: sentCount=$sentCount, errorCount=$errorCount, totalUsers=$totalUsers');

          if (errorCount > 0 && responseData.containsKey('errors')) {
            print(
                '[BroadcastNotification] First 10 errors: ${responseData['errors']}');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Notifications sent successfully! Sent to $sentCount/$totalUsers users${errorCount > 0 ? ' ($errorCount failed)' : ''}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );

            // Clear form after successful send
            _titleController.clear();
            _bodyController.clear();
            _imageUrlController.clear();
            _deepLinkController.clear();
            setState(() {
              _targetScreen = null;
            });
          }
        } catch (parseError) {
          print(
              '[BroadcastNotification] Error parsing response JSON: $parseError');
          print('[BroadcastNotification] Response body: ${response.body}');
          throw Exception('Failed to parse response: $parseError');
        }
      } else {
        print('[BroadcastNotification] HTTP error status: ${response.statusCode}');
        print('[BroadcastNotification] Response body: ${response.body}');
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(
              errorData['error'] ?? 'Failed to send notifications');
        } catch (parseError) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Enhanced error logging
      print('[BroadcastNotification] HTTP Error: $e');
      print('[BroadcastNotification] Error type: ${e.runtimeType}');

      if (e is TimeoutException) {
        print('[BroadcastNotification] Request timed out after 60 seconds');
      } else if (e is SocketException) {
        print(
            '[BroadcastNotification] Network connection error: ${e.message}');
      } else if (e is HttpException) {
        print('[BroadcastNotification] HTTP exception: ${e.message}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send notifications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Widget _buildPreviewCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getTypeIcon(),
                  color: _getTypeColor(),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getTypeLabel(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _getTypeColor(),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_titleController.text.trim().isNotEmpty)
              Text(
                _titleController.text.trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            if (_titleController.text.trim().isNotEmpty &&
                _bodyController.text.trim().isNotEmpty)
              const SizedBox(height: 4),
            if (_bodyController.text.trim().isNotEmpty)
              Text(
                _bodyController.text.trim(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            if (_imageUrlController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.image, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Image included',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
            if ((_deepLinkController.text.trim().isNotEmpty) ||
                (_targetScreen != null && _targetScreen!.isNotEmpty)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    _deepLinkController.text.trim().isNotEmpty
                        ? 'Deep link: ${_deepLinkController.text.trim()}'
                        : 'Target: $_targetScreen',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (_notificationType) {
      case 'announcement':
        return Icons.campaign;
      case 'information':
        return Icons.info;
      case 'general':
        return Icons.notifications;
      default:
        return Icons.notifications;
    }
  }

  Color _getTypeColor() {
    switch (_notificationType) {
      case 'announcement':
        return Colors.orange;
      case 'information':
        return Colors.blue;
      case 'general':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getTypeLabel() {
    switch (_notificationType) {
      case 'announcement':
        return 'Announcement';
      case 'information':
        return 'Information';
      case 'general':
        return 'General';
      default:
        return 'General';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Management'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Preview Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPreviewCard(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Notification Type
              DropdownButtonFormField<String>(
                value: _notificationType,
                decoration: const InputDecoration(
                  labelText: 'Notification Type *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'announcement',
                    child: Text('Announcement'),
                  ),
                  DropdownMenuItem(
                    value: 'information',
                    child: Text('Information'),
                  ),
                  DropdownMenuItem(
                    value: 'general',
                    child: Text('General'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _notificationType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Enter notification title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Message Body
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Message Body *',
                  hintText: 'Enter notification message',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                  alignLabelWithHint: true,
                ),
                maxLength: 500,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a message';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Image URL (Optional)
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (Optional)',
                  hintText: 'https://example.com/image.jpg',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.image),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.hasScheme) {
                      return 'Please enter a valid URL';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Deep Link (Optional)
              TextFormField(
                controller: _deepLinkController,
                decoration: const InputDecoration(
                  labelText: 'Deep Link (Optional)',
                  hintText: 'URL or screen identifier',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Target Screen (Optional)
              DropdownButtonFormField<String>(
                value: _targetScreen,
                decoration: const InputDecoration(
                  labelText: 'Target Screen (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.navigation),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('None'),
                  ),
                  ..._targetScreenOptions.map((screen) => DropdownMenuItem(
                        value: screen,
                        child: Text(screen[0].toUpperCase() +
                            screen.substring(1)),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _targetScreen = value;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Send Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _handleSendNotification,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSending ? 'Sending...' : 'Send Notification'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    disabledBackgroundColor: Colors.grey[300],
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

