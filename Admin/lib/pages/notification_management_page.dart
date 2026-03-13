import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:brgy/pages/notification_actions_dashboard.dart';
import 'package:brgy/pages/notification_progress_page.dart';
import 'package:brgy/services/user_segment_service.dart';

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
  final _smartHungerLunchController = TextEditingController();
  final _smartHungerSnackController = TextEditingController();
  final _smartHungerDinnerController = TextEditingController();

  String _notificationType = 'announcement';
  String? _targetScreen;
  String _selectedSegment = 'all';
  Map<String, int> _segmentCounts = {};
  bool _loadingSegmentCounts = true;
  bool _isSending = false;
  String _campaignFilter = 'all';
  bool _loadingSmartHunger = true;
  bool _smartHungerEnabled = true;
  String _smartHungerFrequencyMode = 'recommended';
  Map<String, bool> _smartHungerWindows = const {
    'lunch': true,
    'snack': true,
    'dinner': true,
  };
  bool _scheduleEnabled = false;
  DateTime? _scheduledDateTime;

  final List<String> _targetScreenOptions = [
    'home',
    'orders',
    'profile',
    'restaurants',
  ];

  @override
  void initState() {
    super.initState();
    _loadSegmentCounts();
    _loadSmartHungerSettings();
  }

  Future<void> _loadSmartHungerSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('smart_hunger_settings')
          .get();
      final data = doc.data() ?? {};
      final windowsRaw = data['windows'];
      final customMessagesRaw = data['customMessages'];
      final windows = windowsRaw is Map
          ? <String, bool>{
              'lunch': windowsRaw['lunch'] is bool
                  ? windowsRaw['lunch'] as bool
                  : true,
              'snack': windowsRaw['snack'] is bool
                  ? windowsRaw['snack'] as bool
                  : true,
              'dinner': windowsRaw['dinner'] is bool
                  ? windowsRaw['dinner'] as bool
                  : true,
            }
          : <String, bool>{
              'lunch': true,
              'snack': true,
              'dinner': true,
            };
      final customMessages = customMessagesRaw is Map
          ? <String, String>{
              'lunch': (customMessagesRaw['lunch'] ?? '').toString(),
              'snack': (customMessagesRaw['snack'] ?? '').toString(),
              'dinner': (customMessagesRaw['dinner'] ?? '').toString(),
            }
          : <String, String>{
              'lunch': '',
              'snack': '',
              'dinner': '',
            };
      _smartHungerLunchController.text = customMessages['lunch'] ?? '';
      _smartHungerSnackController.text = customMessages['snack'] ?? '';
      _smartHungerDinnerController.text = customMessages['dinner'] ?? '';
      if (!mounted) return;
      setState(() {
        _smartHungerEnabled = data['enabled'] != false;
        _smartHungerFrequencyMode =
            (data['frequencyMode'] as String?) == 'less'
                ? 'less'
                : 'recommended';
        _smartHungerWindows = windows;
        _loadingSmartHunger = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSmartHunger = false;
      });
    }
  }

  Future<void> _saveSmartHungerSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('smart_hunger_settings')
          .set({
        'enabled': _smartHungerEnabled,
        'frequencyMode': _smartHungerFrequencyMode,
        'windows': _smartHungerWindows,
        'customMessages': {
          'lunch': _smartHungerLunchController.text.trim(),
          'snack': _smartHungerSnackController.text.trim(),
          'dinner': _smartHungerDinnerController.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Smart Hunger settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(
        title: 'Failed to save Smart Hunger settings',
        error: e,
      );
    }
  }

  Future<void> _loadSegmentCounts() async {
    try {
      final counts = await UserSegmentService.getSegmentCounts();
      if (mounted) {
        setState(() {
          _segmentCounts = counts;
          _loadingSegmentCounts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSegmentCounts = false);
      }
    }
  }

  Future<void> _cancelJob(BuildContext context, String jobId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel notification job?'),
        content: const Text(
          'This will stop the job from processing further. '
          'Already sent notifications cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel job'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('notification_jobs')
          .doc(jobId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'admin_manual',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job cancelled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleCancel() {
    _titleController.clear();
    _bodyController.clear();
    _imageUrlController.clear();
    _deepLinkController.clear();
    setState(() {
      _targetScreen = null;
      _selectedSegment = 'all';
      _scheduleEnabled = false;
      _scheduledDateTime = null;
    });
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _scheduledDateTime ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledDateTime != null
          ? TimeOfDay.fromDateTime(_scheduledDateTime!)
          : const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

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

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _deepLinkController.dispose();
    _smartHungerLunchController.dispose();
    _smartHungerSnackController.dispose();
    _smartHungerDinnerController.dispose();
    super.dispose();
  }

  Future<void> _handleSendNotification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Schedule validation
    if (_scheduleEnabled && _scheduledDateTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please pick a date and time'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (_scheduleEnabled &&
        _scheduledDateTime != null &&
        _scheduledDateTime!.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please pick a future date and time'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final segmentName = _getSegmentDisplayName();
    final isScheduled = _scheduleEnabled && _scheduledDateTime != null;
    final scheduledLabel = isScheduled
        ? DateFormat.yMd().add_Hm().format(_scheduledDateTime!)
        : null;

    // Show confirmation dialog with preview
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isScheduled
              ? 'Schedule Segment Notification'
              : 'Queue Segment Notification',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isScheduled
                    ? 'This will schedule a notification to $segmentName '
                        'to be sent at $scheduledLabel. Continue?'
                    : 'This will queue a notification to $segmentName. '
                        'It will be sent in the background. Continue?',
                style: const TextStyle(fontWeight: FontWeight.bold),
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
            child: Text(isScheduled ? 'Schedule' : 'Queue'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    if (_isSending) {
      return;
    }

    setState(() {
      _isSending = true;
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
      if (_selectedSegment != 'all') {
        payload['segment'] = _selectedSegment;
      }

      final docData = <String, dynamic>{
        'kind': 'segment',
        'createdAt': FieldValue.serverTimestamp(),
        'payload': payload,
        'stats': {
          'totalRecipients': 0,
          'processedCount': 0,
          'successfulDeliveries': 0,
          'failedDeliveries': 0,
          'currentBatchNumber': 0,
          'totalBatches': 0,
          'percentComplete': 0.0,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
      };

      if (isScheduled) {
        docData['status'] = 'scheduled';
        docData['scheduledFor'] = Timestamp.fromDate(_scheduledDateTime!);
      } else {
        docData['status'] = 'queued';
      }

      final ref = await FirebaseFirestore.instance
          .collection('notification_jobs')
          .add(docData);

      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        _imageUrlController.clear();
        _deepLinkController.clear();
        setState(() {
          _targetScreen = null;
          _selectedSegment = 'all';
          _scheduleEnabled = false;
          _scheduledDateTime = null;
        });

        final jobId = ref.id;
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              isScheduled ? 'Notification scheduled' : 'Notification queued',
            ),
            content: Text(
              isScheduled
                  ? 'Your notification to $segmentName has been scheduled '
                      'for $scheduledLabel and will be sent automatically.'
                  : 'Your notification to $segmentName has been queued '
                      'and will be sent in the background.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    ctx,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          NotificationProgressPage(jobId: jobId),
                    ),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('View progress'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await _showErrorDialog(
          title: 'Failed to queue notification',
          error: e,
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

  Widget _buildSmartHungerControls() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Hunger Controls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Central admin controls for automatic lunch, snack, and '
              'dinner reminders.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_loadingSmartHunger)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Smart Hunger Notifications'),
                value: _smartHungerEnabled,
                onChanged: (v) {
                  setState(() => _smartHungerEnabled = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Frequency mode'),
                subtitle: const Text(
                  'Recommended: up to 2/day, Less: max 1/day',
                ),
                trailing: DropdownButton<String>(
                  value: _smartHungerFrequencyMode,
                  items: const [
                    DropdownMenuItem(
                      value: 'recommended',
                      child: Text('Recommended'),
                    ),
                    DropdownMenuItem(
                      value: 'less',
                      child: Text('Less'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _smartHungerFrequencyMode = v);
                  },
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lunch window'),
                value: _smartHungerWindows['lunch'] ?? true,
                onChanged: (v) {
                  setState(() {
                    _smartHungerWindows = {
                      ..._smartHungerWindows,
                      'lunch': v,
                    };
                  });
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Afternoon snack window'),
                value: _smartHungerWindows['snack'] ?? true,
                onChanged: (v) {
                  setState(() {
                    _smartHungerWindows = {
                      ..._smartHungerWindows,
                      'snack': v,
                    };
                  });
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dinner window'),
                value: _smartHungerWindows['dinner'] ?? true,
                onChanged: (v) {
                  setState(() {
                    _smartHungerWindows = {
                      ..._smartHungerWindows,
                      'dinner': v,
                    };
                  });
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _smartHungerLunchController,
                decoration: const InputDecoration(
                  labelText: 'Lunch message (optional)',
                  hintText: 'Custom lunch notification message',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _smartHungerSnackController,
                decoration: const InputDecoration(
                  labelText: 'Snack message (optional)',
                  hintText: 'Custom snack notification message',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _smartHungerDinnerController,
                decoration: const InputDecoration(
                  labelText: 'Dinner message (optional)',
                  hintText: 'Custom dinner notification message',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _saveSmartHungerSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Smart Hunger Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
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

  int _getTotalCount() {
    return _segmentCounts.values.fold<int>(0, (acc, c) => acc + c);
  }

  String _getSegmentHelperText() {
    if (_selectedSegment == 'all') {
      return 'Every active customer';
    }
    return UserSegmentService.getSegmentDescription(_selectedSegment);
  }

  String _getSegmentDisplayName() {
    if (_selectedSegment == 'all') {
      return 'All Customers';
    }
    return UserSegmentService.getSegmentDisplayName(_selectedSegment);
  }

  void _showSegmentHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Segment Definitions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _segmentHelpRow('All Customers', 'Every active customer'),
              ...UserSegmentService.segments.map(
                (s) => _segmentHelpRow(
                  UserSegmentService.getSegmentDisplayName(s),
                  UserSegmentService.getSegmentDescription(s),
                ),
              ),
            ],
          ),
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

  Widget _segmentHelpRow(String name, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
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
        title: const Text('Notification Management'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Action Performance',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationActionsDashboard(),
                ),
              );
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Preview Card
              _buildSmartHungerControls(),
              const SizedBox(height: 24),

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
              const SizedBox(height: 16),

              // Target Segment
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedSegment,
                      decoration: InputDecoration(
                        labelText: 'Target Segment *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.people),
                        helperText: _loadingSegmentCounts
                            ? 'Loading counts...'
                            : _getSegmentHelperText(),
                      ),
                items: [
                  DropdownMenuItem<String>(
                    value: 'all',
                    child: Text(
                      'All Customers'
                      '${_segmentCounts.isNotEmpty ? " (~${_getTotalCount()} users)" : ""}',
                    ),
                  ),
                  ...UserSegmentService.segments.map((segment) {
                    final count = _segmentCounts[segment] ?? 0;
                    return DropdownMenuItem<String>(
                      value: segment,
                      child: Tooltip(
                        message:
                            UserSegmentService.getSegmentDescription(segment),
                        child: Text(
                          '${UserSegmentService.getSegmentDisplayName(segment)} (~$count)',
                        ),
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSegment = value ?? 'all';
                  });
                },
              ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'Segment definitions',
                    onPressed: () => _showSegmentHelpDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Schedule for later
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule for later'),
                value: _scheduleEnabled,
                onChanged: (v) {
                  setState(() {
                    _scheduleEnabled = v;
                    if (!v) _scheduledDateTime = null;
                  });
                },
              ),
              if (_scheduleEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSending ? null : _pickScheduleDateTime,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _scheduledDateTime != null
                            ? DateFormat.yMd().add_Hm().format(_scheduledDateTime!)
                            : 'Pick date and time',
                      ),
                    ),
                    if (_scheduledDateTime != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() => _scheduledDateTime = null);
                        },
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 24),

              // Cancel and Send Buttons
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _isSending ? null : _handleCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
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
                      label: Text(
                        _isSending
                            ? (_scheduleEnabled ? 'Scheduling...' : 'Queuing...')
                            : 'Send Notification',
                      ),
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
              const SizedBox(height: 32),
              _buildRecentJobsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentJobsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notification_jobs')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        var docs = snapshot.data!.docs;
        if (_campaignFilter == 'segment') {
          docs = docs.where((d) => (d.data()['kind'] ?? '') == 'segment').toList();
        } else if (_campaignFilter == 'happy_hour') {
          docs = docs.where((d) => (d.data()['kind'] ?? '') == 'happy_hour').toList();
        }
        if (docs.isEmpty) {
          return Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent notification jobs',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      DropdownButton<String>(
                        value: _campaignFilter,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Campaigns')),
                          DropdownMenuItem(value: 'segment', child: Text('Segment Sends')),
                          DropdownMenuItem(value: 'happy_hour', child: Text('Happy Hour Auto')),
                        ],
                        onChanged: (v) => setState(() => _campaignFilter = v ?? 'all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'No jobs match the selected filter',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent notification jobs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    DropdownButton<String>(
                      value: _campaignFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Campaigns')),
                        DropdownMenuItem(value: 'segment', child: Text('Segment Sends')),
                        DropdownMenuItem(value: 'happy_hour', child: Text('Happy Hour Auto')),
                      ],
                      onChanged: (v) => setState(() => _campaignFilter = v ?? 'all'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...docs.map((doc) {
                  final data = doc.data();
                  final kind = data['kind'] as String? ?? 'unknown';
                  final status = data['status'] as String? ?? 'unknown';
                  final payload = data['payload'] as Map<String, dynamic>? ?? {};
                  final segment = payload['segment'] as String? ?? 'all';
                  final stats = data['stats'] as Map<String, dynamic>?;
                  final sentCount = (stats?['successfulDeliveries'] as int?) ??
                      data['sentCount'] as int? ??
                      0;
                  final errorCount =
                      (stats?['failedDeliveries'] as int?) ??
                      data['errorCount'] as int? ??
                      0;
                  final totalUsers =
                      (stats?['totalRecipients'] as int?) ??
                      data['totalUsers'] as int? ??
                      0;
                  final percentComplete =
                      (stats?['percentComplete'] as num?)?.toInt();
                  final error = data['error'] as String?;
                  final segmentLabel = segment == 'all'
                      ? 'All'
                      : UserSegmentService.getSegmentDisplayName(segment);
                  final configName = payload['configName'] as String? ?? 'Promo';

                  Color statusColor = Colors.grey;
                  if (status == 'completed') {
                    statusColor = Colors.green;
                  } else if (status == 'failed') {
                    statusColor = Colors.red;
                  } else if (status == 'in_progress') {
                    statusColor = Colors.orange;
                  } else if (status == 'cancelled') {
                    statusColor = Colors.amber;
                  } else if (status == 'scheduled') {
                    statusColor = Colors.blue;
                  }

                  String progressText;
                  if (status == 'scheduled') {
                    final sf = data['scheduledFor'] as Timestamp?;
                    progressText = sf != null
                        ? ' (${DateFormat.yMd().add_Hm().format(sf.toDate())})'
                        : '';
                  } else if (status == 'in_progress' &&
                      percentComplete != null &&
                      totalUsers > 0) {
                    progressText = ' $percentComplete%';
                  } else if (status == 'completed' && totalUsers > 0) {
                    progressText =
                        ' $sentCount/$totalUsers sent${errorCount > 0 ? ", $errorCount failed" : ""}';
                  } else if (status == 'failed' && error != null) {
                    progressText =
                        ' ${error.length > 40 ? "${error.substring(0, 40)}..." : error}';
                  } else if (status == 'cancelled' && sentCount > 0) {
                    progressText = ' (partial: $sentCount sent)';
                  } else {
                    progressText = '';
                  }

                  final canCancel = status == 'queued' ||
                      status == 'in_progress' ||
                      status == 'scheduled';

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NotificationProgressPage(jobId: doc.id),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            kind == 'happy_hour'
                                ? Icons.local_offer
                                : _statusIcon(status),
                            size: 20,
                            color: kind == 'happy_hour'
                                ? Colors.orange
                                : statusColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              kind == 'happy_hour'
                                  ? 'Happy Hour: $configName — $status$progressText'
                                  : '$kind / $segmentLabel: $status$progressText',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (canCancel)
                            IconButton(
                              icon: const Icon(Icons.cancel),
                              iconSize: 20,
                              color: Colors.grey[600],
                              tooltip: 'Cancel job',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: () => _cancelJob(context, doc.id),
                            ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'in_progress':
        return Icons.hourglass_empty;
      case 'cancelled':
        return Icons.cancel;
      case 'scheduled':
        return Icons.schedule_send;
      default:
        return Icons.schedule;
    }
  }

}

