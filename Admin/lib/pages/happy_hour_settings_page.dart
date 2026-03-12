import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/HappyHourConfig.dart';
import 'package:brgy/services/happy_hour_service.dart';

class HappyHourSettingsPage extends StatefulWidget {
  const HappyHourSettingsPage({super.key});

  @override
  State<HappyHourSettingsPage> createState() => _HappyHourSettingsPageState();
}

class _HappyHourSettingsPageState extends State<HappyHourSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Happy Hour Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<HappyHourSettings>(
        stream: HappyHourService.getHappyHourSettingsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading settings: ${snapshot.error}'),
                ],
              ),
            );
          }

          final settings = snapshot.data ?? HappyHourSettings.empty();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Master Toggle Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.local_offer, color: Colors.orange, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Happy Hour',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                settings.enabled
                                    ? 'Enabled - Promos will activate automatically'
                                    : 'Disabled - All Happy Hour promos are inactive',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: settings.enabled,
                          onChanged: (value) async {
                            try {
                              await HappyHourService.updateMasterToggle(value);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'Happy Hour enabled'
                                          : 'Happy Hour disabled',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to update: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          activeColor: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Automation Settings
                _AutomationSettingsCard(settings: settings),

                const SizedBox(height: 24),

                // Auto Monitor
                _HappyHourAutoMonitorCard(settings: settings),

                const SizedBox(height: 24),

                // Configurations Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Happy Hour Configurations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddEditDialog(context, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add New'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Configurations List
                if (settings.configs.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.local_offer_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No Happy Hour configurations',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add your first configuration to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...settings.configs.map((config) => _buildConfigCard(config)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfigCard(HappyHourConfig config) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: const Icon(Icons.local_offer, color: Colors.orange),
        title: Text(
          config.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${config.startTime} - ${config.endTime} • ${config.activeDaysDisplay}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Promo Type', config.promoTypeDisplay),
                _buildInfoRow('Promo Value', _formatPromoValue(config)),
                _buildInfoRow('Min Order', '₱${config.minOrderAmount.toStringAsFixed(2)}'),
                if (config.minItems != null)
                  _buildInfoRow(
                    'Min Items',
                    '${config.minItems} items required',
                  ),
                _buildInfoRow(
                  'Restaurants',
                  config.restaurantScope == 'all'
                      ? 'All Restaurants'
                      : '${config.restaurantIds.length} Selected',
                ),
                _buildInfoRow('User Eligibility', config.userEligibilityDisplay),
                if (config.maxUsagePerUserPerDay != null)
                  _buildInfoRow(
                    'Max Usage/Day',
                    '${config.maxUsagePerUserPerDay} times per user',
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showAddEditDialog(context, config),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _handleDelete(config),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _formatPromoValue(HappyHourConfig config) {
    switch (config.promoType) {
      case 'fixed_amount':
        return '₱${config.promoValue.toStringAsFixed(2)}';
      case 'percentage':
        return '${config.promoValue.toStringAsFixed(0)}%';
      case 'free_delivery':
        return 'Free';
      case 'reduced_delivery':
        return '₱${config.promoValue.toStringAsFixed(2)} reduction';
      default:
        return config.promoValue.toString();
    }
  }

  Future<void> _handleDelete(HappyHourConfig config) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Configuration'),
        content: Text('Are you sure you want to delete "${config.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await HappyHourService.deleteHappyHourConfig(config.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuration deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAddEditDialog(
      BuildContext context, HappyHourConfig? existingConfig) async {
    await showDialog(
      context: context,
      builder: (context) => _HappyHourConfigDialog(config: existingConfig),
    );
  }
}

class _AutomationSettingsCard extends StatefulWidget {
  const _AutomationSettingsCard({required this.settings});

  final HappyHourSettings settings;

  @override
  State<_AutomationSettingsCard> createState() => _AutomationSettingsCardState();
}

class _HappyHourAutoMonitorCard extends StatelessWidget {
  const _HappyHourAutoMonitorCard({required this.settings});

  final HappyHourSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Happy Hour Auto Monitor',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Manual button sends now (triggeredBy: manual). '
              'Auto scheduler sends on configured window '
              '(triggeredBy: auto_schedule).',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 14),
            _buildStatusRows(context),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            _buildLatestAutoJob(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRows(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusRow(
          'Enabled',
          settings.enabled ? 'Yes' : 'No',
          settings.enabled ? Colors.green : Colors.grey,
        ),
        _statusRow(
          'Auto-create notification',
          settings.autoCreateNotification ? 'Yes' : 'No',
          settings.autoCreateNotification ? Colors.green : Colors.grey,
        ),
        _statusRow(
          'Last auto trigger',
          _formatTimestamp(settings.lastTriggeredAt),
          Colors.black87,
        ),
        _statusRow(
          'Last triggered config',
          settings.lastTriggeredConfigId?.isNotEmpty == true
              ? settings.lastTriggeredConfigId!
              : 'N/A',
          Colors.black87,
        ),
        _statusRow(
          'Next active window',
          _computeNextActiveWindow(settings.configs),
          Colors.black87,
        ),
      ],
    );
  }

  Widget _statusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestAutoJob(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notification_jobs')
          .where('kind', isEqualTo: 'happy_hour')
          .where('triggeredBy', isEqualTo: 'auto_schedule')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Unable to load auto job status. If this is a Firestore index '
              'error, create the suggested composite index and refresh.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _statusBanner(
            color: Colors.grey,
            text: 'No auto send yet today',
          );
        }

        final data = docs.first.data();
        final status = (data['status'] ?? 'unknown').toString();
        final stats = (data['stats'] is Map<String, dynamic>)
            ? data['stats'] as Map<String, dynamic>
            : <String, dynamic>{};
        final sent = (stats['successfulDeliveries'] as num?)?.toInt() ?? 0;
        final failed = (stats['failedDeliveries'] as num?)?.toInt() ?? 0;
        final progress = (stats['percentComplete'] as num?)?.toDouble() ?? 0;
        final error = data['error']?.toString();
        final createdAt = data['createdAt'] as Timestamp?;

        final banner = _bannerForStatus(status, sent, createdAt);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusBanner(color: banner.$1, text: banner.$2),
            const SizedBox(height: 10),
            _statusRow('Job status', status, Colors.black87),
            _statusRow('Sent', '$sent', Colors.green),
            _statusRow('Failed', '$failed', failed > 0 ? Colors.red : Colors.black87),
            _statusRow('Progress', '${progress.toStringAsFixed(0)}%', Colors.black87),
            _statusRow('Triggered at', _formatTimestamp(createdAt), Colors.black87),
            if (status == 'failed' && error != null && error.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Error: $error',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _statusBanner({required Color color, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color, String) _bannerForStatus(
    String status,
    int sent,
    Timestamp? createdAt,
  ) {
    final nowLocal = DateTime.now();
    final startOfTodayLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    );
    final createdLocal = createdAt?.toDate();
    final isToday = createdLocal != null &&
        !createdLocal.isBefore(startOfTodayLocal);

    if (!isToday) {
      return (Colors.grey, 'No auto send yet today');
    }
    if (status == 'failed') {
      return (Colors.red, 'Auto Happy Hour failed');
    }
    if (status == 'queued' || status == 'in_progress') {
      return (Colors.orange, 'Auto Happy Hour in progress');
    }
    if (status == 'completed' && sent > 0) {
      return (Colors.green, 'Auto Happy Hour sent successfully');
    }
    return (Colors.grey, 'No auto send yet today');
  }

  String _computeNextActiveWindow(List<HappyHourConfig> configs) {
    if (configs.isEmpty) return 'N/A';

    final now = DateTime.now();
    DateTime? best;
    HappyHourConfig? bestConfig;

    for (final config in configs) {
      final time = _parseTime(config.startTime);
      if (time == null) continue;

      for (int delta = 0; delta <= 7; delta++) {
        final day = now.add(Duration(days: delta));
        final weekday = day.weekday % 7; // convert to 0=Sun..6=Sat
        if (!config.activeDays.contains(weekday)) continue;

        final candidate = DateTime(
          day.year,
          day.month,
          day.day,
          time.$1,
          time.$2,
        );
        if (!candidate.isAfter(now)) continue;

        if (best == null || candidate.isBefore(best)) {
          best = candidate;
          bestConfig = config;
        }
      }
    }

    if (best == null) return 'N/A';
    final dayLabel = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        [best.weekday % 7];
    final hh = best.hour % 12 == 0 ? 12 : best.hour % 12;
    final mm = best.minute.toString().padLeft(2, '0');
    final ampm = best.hour >= 12 ? 'PM' : 'AM';
    final name = bestConfig?.name ?? 'Config';
    return '$dayLabel $hh:$mm $ampm ($name)';
  }

  (int, int)? _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return (h, m);
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'N/A';
    final d = ts.toDate();
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} $hh:$mm $ampm';
  }
}

class _AutomationSettingsCardState extends State<_AutomationSettingsCard> {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  late TextEditingController _imageUrlController;
  late TextEditingController _deepLinkController;
  String? _selectedConfigId;
  bool _isSaving = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    final t = widget.settings.notificationTemplate;
    _titleController = TextEditingController(text: t.title);
    _bodyController = TextEditingController(text: t.body);
    _imageUrlController = TextEditingController(text: t.imageUrl ?? '');
    _deepLinkController = TextEditingController(text: t.deepLink ?? '');
    _selectedConfigId =
        widget.settings.configs.isNotEmpty
            ? widget.settings.configs.first.id
            : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _deepLinkController.dispose();
    super.dispose();
  }

  Future<void> _saveTemplate() async {
    final template = NotificationTemplate(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      deepLink: _deepLinkController.text.trim().isEmpty
          ? null
          : _deepLinkController.text.trim(),
    );
    if (!template.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Title and body are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    setState(() => _isSaving = true);
    try {
      await HappyHourService.updateAutoCreateSettings(
        widget.settings.autoCreateNotification,
        template,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onAutoCreateChanged(bool value) async {
    final template = NotificationTemplate(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      deepLink: _deepLinkController.text.trim().isEmpty
          ? null
          : _deepLinkController.text.trim(),
    );
    setState(() => _isSaving = true);
    try {
      await HappyHourService.updateAutoCreateSettings(value, template);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Auto-create enabled'
                : 'Auto-create disabled'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createJobNow() async {
    if (widget.settings.configs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one Happy Hour configuration first'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final configId = _selectedConfigId;
    if (configId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a configuration'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final config = widget.settings.configs
        .where((c) => c.id == configId)
        .firstOrNull;
    if (config == null) return;

    final template = NotificationTemplate(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      deepLink: _deepLinkController.text.trim().isEmpty
          ? null
          : _deepLinkController.text.trim(),
    );
    if (!template.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Title and body are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isCreating = true);
    try {
      await HappyHourService.createHappyHourNotificationJob(
        config,
        template,
        triggeredBy: 'manual',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification job created. View progress in Notification '
              'Management.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create job: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoOn = widget.settings.autoCreateNotification;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Automation Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Automatically create notification when Happy Hour '
                        'starts',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        autoOn
                            ? 'A job will be created when a Happy Hour window '
                                'starts'
                            : 'Notifications must be created manually',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: autoOn,
                  onChanged: _isSaving ? null : _onAutoCreateChanged,
                  activeColor: Colors.orange,
                ),
              ],
            ),
            if (autoOn) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Notification Title *',
                  hintText: 'e.g., Happy Hour is Live!',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Notification Body *',
                  hintText: 'e.g., 20% OFF for a limited time',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                  alignLabelWithHint: true,
                ),
                maxLength: 500,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (Optional)',
                  hintText: 'https://example.com/image.jpg',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.image),
                ),
                keyboardType: TextInputType.url,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deepLinkController,
                decoration: const InputDecoration(
                  labelText: 'Deep Link (Optional)',
                  hintText: 'URL or screen identifier',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _saveTemplate,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Template'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Create Happy Hour Notification Now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manually create a notification job using the template above',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            if (widget.settings.configs.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedConfigId,
                decoration: const InputDecoration(
                  labelText: 'Select Config',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_offer),
                ),
                items: widget.settings.configs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.startTime}-${c.endTime})'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedConfigId = v),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreating ||
                        widget.settings.configs.isEmpty ||
                        _selectedConfigId == null
                    ? null
                    : _createJobNow,
                icon: _isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.notifications_active),
                label: const Text('Create Happy Hour Notification Now'),
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
    );
  }
}

class _HappyHourConfigDialog extends StatefulWidget {
  final HappyHourConfig? config;

  const _HappyHourConfigDialog({this.config});

  @override
  State<_HappyHourConfigDialog> createState() => _HappyHourConfigDialogState();
}

class _HappyHourConfigDialogState extends State<_HappyHourConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _promoValueController = TextEditingController();
  final _minOrderAmountController = TextEditingController();
  final _minItemsController = TextEditingController();
  final _maxUsageController = TextEditingController();

  TimeOfDay _startTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  List<int> _activeDays = [];
  String _promoType = 'fixed_amount';
  String _restaurantScope = 'all';
  List<String> _selectedRestaurantIds = [];
  String _userEligibility = 'all';
  bool _hasMaxUsage = false;
  bool _isLoading = false;
  bool _isLoadingRestaurants = false;
  List<Map<String, String>> _restaurants = [];
  String _restaurantSearchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      final config = widget.config!;
      _nameController.text = config.name;
      _promoValueController.text = config.promoValue.toString();
      _minOrderAmountController.text = config.minOrderAmount.toString();
      if (config.minItems != null) {
        _minItemsController.text = config.minItems.toString();
      }
      _startTime = _parseTimeOfDay(config.startTime);
      _endTime = _parseTimeOfDay(config.endTime);
      _activeDays = List.from(config.activeDays);
      _promoType = config.promoType;
      _restaurantScope = config.restaurantScope;
      _selectedRestaurantIds = List.from(config.restaurantIds);
      _userEligibility = config.userEligibility;
      _hasMaxUsage = config.maxUsagePerUserPerDay != null;
      if (_hasMaxUsage) {
        _maxUsageController.text = config.maxUsagePerUserPerDay.toString();
      }
    }
    _loadRestaurants();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promoValueController.dispose();
    _minOrderAmountController.dispose();
    _minItemsController.dispose();
    _maxUsageController.dispose();
    super.dispose();
  }

  TimeOfDay _parseTimeOfDay(String time) {
    try {
      final parts = time.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (e) {
      return const TimeOfDay(hour: 14, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoadingRestaurants = true;
    });

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('vendors').get();
      setState(() {
        _restaurants = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': (data['title'] ?? data['authorName'] ?? 'Restaurant')
                .toString(),
          };
        }).toList();
        _isLoadingRestaurants = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingRestaurants = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load restaurants: $e')),
        );
      }
    }
  }

  Future<void> _selectTime(bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_activeDays.contains(day)) {
        _activeDays.remove(day);
      } else {
        _activeDays.add(day);
        _activeDays.sort();
      }
    });
  }

  Future<void> _showRestaurantSelector() async {
    await showDialog(
      context: context,
      builder: (context) => _RestaurantSelectorDialog(
        restaurants: _restaurants,
        selectedIds: _selectedRestaurantIds,
        searchQuery: _restaurantSearchQuery,
        onSelectionChanged: (selectedIds, searchQuery) {
          setState(() {
            _selectedRestaurantIds = selectedIds;
            _restaurantSearchQuery = searchQuery;
          });
        },
      ),
    );
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_activeDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one active day'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_restaurantScope == 'selected' && _selectedRestaurantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one restaurant'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate time range
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final config = HappyHourConfig(
        id: widget.config?.id ?? '',
        name: _nameController.text.trim(),
        startTime: _formatTimeOfDay(_startTime),
        endTime: _formatTimeOfDay(_endTime),
        activeDays: _activeDays,
        promoType: _promoType,
        promoValue: double.parse(_promoValueController.text.trim()),
        minOrderAmount: double.parse(_minOrderAmountController.text.trim()),
        restaurantScope: _restaurantScope,
        restaurantIds: _restaurantScope == 'all' ? [] : _selectedRestaurantIds,
        userEligibility: _userEligibility,
        maxUsagePerUserPerDay:
            _hasMaxUsage ? int.tryParse(_maxUsageController.text.trim()) : null,
        minItems: _minItemsController.text.trim().isEmpty
            ? null
            : int.tryParse(_minItemsController.text.trim()),
      );

      if (widget.config == null) {
        await HappyHourService.addHappyHourConfig(config);
      } else {
        await HappyHourService.updateHappyHourConfig(config.id, config);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.config == null
                  ? 'Configuration added successfully'
                  : 'Configuration updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.config == null
                            ? 'Add Happy Hour Configuration'
                            : 'Edit Happy Hour Configuration',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Promo Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Promo Name *',
                          hintText: 'Enter promo name or label',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a promo name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Time Range
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectTime(true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Start Time *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.access_time),
                                ),
                                child: Text(
                                  _startTime.format(context),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectTime(false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'End Time *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.access_time),
                                ),
                                child: Text(
                                  _endTime.format(context),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Active Days
                      const Text(
                        'Active Days *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (int i = 0; i < 7; i++)
                            FilterChip(
                              label: Text(['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i]),
                              selected: _activeDays.contains(i),
                              onSelected: (_) => _toggleDay(i),
                              selectedColor: Colors.orange.withValues(alpha: 0.3),
                              checkmarkColor: Colors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Promo Type
                      DropdownButtonFormField<String>(
                        value: _promoType,
                        decoration: const InputDecoration(
                          labelText: 'Promo Type *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'fixed_amount',
                            child: Text('Fixed Amount Discount'),
                          ),
                          DropdownMenuItem(
                            value: 'percentage',
                            child: Text('Percentage Discount'),
                          ),
                          DropdownMenuItem(
                            value: 'free_delivery',
                            child: Text('Free Delivery'),
                          ),
                          DropdownMenuItem(
                            value: 'reduced_delivery',
                            child: Text('Reduced Delivery'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _promoType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Promo Value
                      TextFormField(
                        controller: _promoValueController,
                        decoration: InputDecoration(
                          labelText: _getPromoValueLabel(),
                          hintText: _getPromoValueHint(),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a promo value';
                          }
                          final numValue = double.tryParse(value.trim());
                          if (numValue == null || numValue <= 0) {
                            return 'Please enter a valid positive number';
                          }
                          if (_promoType == 'percentage' &&
                              (numValue < 0 || numValue > 100)) {
                            return 'Percentage must be between 0 and 100';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Minimum Order Amount
                      TextFormField(
                        controller: _minOrderAmountController,
                        decoration: const InputDecoration(
                          labelText: 'Minimum Order Amount (₱) *',
                          hintText: '0.00',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shopping_cart),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter minimum order amount';
                          }
                          final numValue = double.tryParse(value.trim());
                          if (numValue == null || numValue < 0) {
                            return 'Please enter a valid non-negative number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Minimum Items
                      TextFormField(
                        controller: _minItemsController,
                        decoration: const InputDecoration(
                          labelText: 'Minimum Items (Optional)',
                          hintText: 'e.g., 1, 2, 3 (leave empty for no restriction)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shopping_bag),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final intValue = int.tryParse(value.trim());
                            if (intValue == null || intValue < 1) {
                              return 'Please enter a valid positive integer (≥ 1)';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Restaurant Scope
                      const Text(
                        'Restaurant Scope *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('All Restaurants'),
                              value: 'all',
                              groupValue: _restaurantScope,
                              onChanged: (value) {
                                setState(() {
                                  _restaurantScope = value!;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Selected Restaurants'),
                              value: 'selected',
                              groupValue: _restaurantScope,
                              onChanged: (value) {
                                setState(() {
                                  _restaurantScope = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      // Restaurant Selector
                      if (_restaurantScope == 'selected') ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _isLoadingRestaurants
                              ? null
                              : _showRestaurantSelector,
                          icon: _isLoadingRestaurants
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.restaurant),
                          label: Text(
                            _selectedRestaurantIds.isEmpty
                                ? 'Select Restaurants'
                                : '${_selectedRestaurantIds.length} Selected',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // User Eligibility
                      DropdownButtonFormField<String>(
                        value: _userEligibility,
                        decoration: const InputDecoration(
                          labelText: 'User Eligibility *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.people),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All Users'),
                          ),
                          DropdownMenuItem(
                            value: 'new',
                            child: Text('New Users Only (0 orders)'),
                          ),
                          DropdownMenuItem(
                            value: 'returning',
                            child: Text('Returning Users Only (1+ orders)'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _userEligibility = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Max Usage Per User Per Day
                      Row(
                        children: [
                          Checkbox(
                            value: _hasMaxUsage,
                            onChanged: (value) {
                              setState(() {
                                _hasMaxUsage = value ?? false;
                                if (!_hasMaxUsage) {
                                  _maxUsageController.clear();
                                }
                              });
                            },
                          ),
                          const Expanded(
                            child: Text('Set maximum usage per user per day'),
                          ),
                        ],
                      ),
                      if (_hasMaxUsage) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _maxUsageController,
                          decoration: const InputDecoration(
                            labelText: 'Max Usage Per User Per Day',
                            hintText: 'e.g., 1, 2, 3',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.repeat),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (_hasMaxUsage) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter max usage limit';
                              }
                              final intValue = int.tryParse(value.trim());
                              if (intValue == null || intValue <= 0) {
                                return 'Please enter a valid positive integer';
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer Buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPromoValueLabel() {
    switch (_promoType) {
      case 'fixed_amount':
        return 'Discount Amount (₱) *';
      case 'percentage':
        return 'Discount Percentage (%) *';
      case 'free_delivery':
        return 'Free Delivery (N/A)';
      case 'reduced_delivery':
        return 'Delivery Reduction Amount (₱) *';
      default:
        return 'Promo Value *';
    }
  }

  String _getPromoValueHint() {
    switch (_promoType) {
      case 'fixed_amount':
        return 'e.g., 20.00';
      case 'percentage':
        return 'e.g., 10';
      case 'free_delivery':
        return 'Automatically set to 0';
      case 'reduced_delivery':
        return 'e.g., 15.00';
      default:
        return 'Enter value';
    }
  }
}

class _RestaurantSelectorDialog extends StatefulWidget {
  final List<Map<String, String>> restaurants;
  final List<String> selectedIds;
  final String searchQuery;
  final Function(List<String>, String) onSelectionChanged;

  const _RestaurantSelectorDialog({
    required this.restaurants,
    required this.selectedIds,
    required this.searchQuery,
    required this.onSelectionChanged,
  });

  @override
  State<_RestaurantSelectorDialog> createState() =>
      _RestaurantSelectorDialogState();
}

class _RestaurantSelectorDialogState
    extends State<_RestaurantSelectorDialog> {
  late List<String> _selectedIds;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.selectedIds);
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(String restaurantId) {
    setState(() {
      if (_selectedIds.contains(restaurantId)) {
        _selectedIds.remove(restaurantId);
      } else {
        _selectedIds.add(restaurantId);
      }
    });
  }

  void _saveSelection() {
    widget.onSelectionChanged(_selectedIds, _searchController.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filteredRestaurants = widget.restaurants.where((r) {
      return r['name']!.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.restaurant, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select Restaurants (${_selectedIds.length} selected)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search restaurants...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Restaurant List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredRestaurants.length,
                itemBuilder: (context, index) {
                  final restaurant = filteredRestaurants[index];
                  final isSelected = _selectedIds.contains(restaurant['id']);

                  return CheckboxListTile(
                    title: Text(restaurant['name']!),
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(restaurant['id']!),
                  );
                },
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveSelection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

