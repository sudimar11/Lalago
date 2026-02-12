import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

// Avoid Dart record types here for compatibility with older SDKs.
class _SendingDialogController {
  final VoidCallback close;
  final void Function(int seconds) setElapsedSeconds;
  final void Function(String text) setStatus;
  final void Function({required int sent, required int failed, required int total})
      setCounts;

  const _SendingDialogController({
    required this.close,
    required this.setElapsedSeconds,
    required this.setStatus,
    required this.setCounts,
  });
}

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

  Future<void> _showErrorDialog({
    required String title,
    required Object error,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(
          error.toString(),
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<_SendingDialogController> _showSendingDialog({
    required String title,
  }) async {
    final elapsedSeconds = ValueNotifier<int>(0);
    final statusText = ValueNotifier<String>('Sending...');
    final sentCount = ValueNotifier<int?>(null);
    final failedCount = ValueNotifier<int?>(null);
    final totalUsers = ValueNotifier<int?>(null);

    bool isOpen = true;

    void close() {
      if (!mounted || !isOpen) return;
      isOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    void setElapsedSecondsValue(int seconds) {
      if (!isOpen) return;
      elapsedSeconds.value = seconds;
    }

    void setStatusValue(String text) {
      if (!isOpen) return;
      statusText.value = text;
    }

    void setCountsValue({required int sent, required int failed, required int total}) {
      if (!isOpen) return;
      sentCount.value = sent;
      failedCount.value = failed;
      totalUsers.value = total;
    }

    if (!mounted) {
      return _SendingDialogController(
        close: () {},
        setElapsedSeconds: (_) {},
        setStatus: (_) {},
        setCounts: ({required sent, required failed, required total}) {},
      );
    }

    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ValueListenableBuilder<String>(
                              valueListenable: statusText,
                              builder: (context, value, _) => Text(value),
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder<int>(
                              valueListenable: elapsedSeconds,
                              builder: (context, value, _) => Text(
                                'Elapsed: ${value}s',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ValueListenableBuilder<int?>(
                              valueListenable: sentCount,
                              builder: (context, sent, _) {
                                final failed = failedCount.value;
                                final total = totalUsers.value;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sent: ${sent ?? '-'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Failed: ${failed ?? '-'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Total: ${total ?? '-'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      isOpen = false;
      elapsedSeconds.dispose();
      statusText.dispose();
      sentCount.dispose();
      failedCount.dispose();
      totalUsers.dispose();
    });

    return _SendingDialogController(
      close: close,
      setElapsedSeconds: setElapsedSecondsValue,
      setStatus: setStatusValue,
      setCounts: setCountsValue,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _deepLinkController.dispose();
    super.dispose();
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

    final dialog = await _showSendingDialog(
      title: 'Sending broadcast notification',
    );
    final stopwatch = Stopwatch()..start();
    final tick = Timer.periodic(const Duration(seconds: 1), (_) {
      dialog.setElapsedSeconds(stopwatch.elapsed.inSeconds);
    });

    try {
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'type': _notificationType,
      };
      if (_imageUrlController.text.trim().isNotEmpty) {
        payload['imageUrl'] = _imageUrlController.text.trim();
      }
      if (_deepLinkController.text.trim().isNotEmpty) {
        payload['deepLink'] = _deepLinkController.text.trim();
      }
      if (_targetScreen != null && _targetScreen!.isNotEmpty) {
        payload['targetScreen'] = _targetScreen;
      }

      final projectId = Firebase.app().options.projectId;
      const region = 'us-central1';
      final url = Uri.parse(
        'https://$region-$projectId.cloudfunctions.net/sendBroadcastNotifications',
      );

      dialog.setStatus('Sending...');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 10));

      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      final sent = (body?['sentCount'] is num)
          ? (body!['sentCount'] as num).toInt()
          : 0;
      final failed = (body?['errorCount'] is num)
          ? (body!['errorCount'] as num).toInt()
          : 0;
      final total = (body?['totalUsers'] is num)
          ? (body!['totalUsers'] as num).toInt()
          : 0;

      dialog.setCounts(sent: sent, failed: failed, total: total);

      if (response.statusCode == 200 && (body?['success'] == true)) {
        dialog.setStatus('Completed');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        dialog.close();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Notifications sent successfully! Sent to $sent/$total'
                ' users${failed > 0 ? ' ($failed failed)' : ''}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          _titleController.clear();
          _bodyController.clear();
          _imageUrlController.clear();
          _deepLinkController.clear();
          setState(() => _targetScreen = null);
        }
      } else {
        final errorMsg = body?['error']?.toString() ??
            body?['message']?.toString() ??
            'HTTP ${response.statusCode}';
        dialog.setStatus('Failed');
        tick.cancel();
        stopwatch.stop();
        dialog.close();
        if (mounted) {
          await _showErrorDialog(
            title: 'Failed to send notifications',
            error: errorMsg,
          );
        }
      }
    } catch (e) {
      print('[BroadcastNotification] Error: $e');
      dialog.setStatus('Failed');
      tick.cancel();
      stopwatch.stop();
      dialog.close();
      if (mounted) {
        await _showErrorDialog(
          title: 'Failed to send notifications',
          error: e,
        );
      }
    } finally {
      tick.cancel();
      stopwatch.stop();
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

