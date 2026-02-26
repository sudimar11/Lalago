import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/restaurant_settings_service.dart';

class RestaurantSettingsPage extends StatefulWidget {
  const RestaurantSettingsPage({
    super.key,
    required this.vendorId,
    this.restaurantName,
  });

  final String vendorId;
  final String? restaurantName;

  @override
  State<RestaurantSettingsPage> createState() => _RestaurantSettingsPageState();
}

class _RestaurantSettingsPageState extends State<RestaurantSettingsPage> {
  final _service = RestaurantSettingsService();
  final _contactController = TextEditingController();
  final _timeoutController = TextEditingController(text: '5');
  final _consecutiveController = TextEditingController(text: '2');
  final _timerController = TextEditingController(text: '180');

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasDevice = true;
  String _deviceType = 'mobile_app';
  bool _allowAdminOverride = false;
  bool _autoPauseEnabled = true;
  int _consecutiveMissesThreshold = 2;
  int _timerSeconds = 180;

  static const _deviceTypes = [
    ('mobile_app', 'Mobile App'),
    ('web_portal', 'Web Portal'),
    ('tablet', 'Dedicated Tablet'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _contactController.dispose();
    _timeoutController.dispose();
    _consecutiveController.dispose();
    _timerController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final s = await _service.getSettings(widget.vendorId);
      final vendorDoc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(widget.vendorId)
          .get();
      if (!mounted) return;
      final acceptance = vendorDoc.data()?['acceptanceSettings']
          as Map<String, dynamic>?;
      setState(() {
        _hasDevice = s.hasDevice;
        _deviceType = s.deviceType ?? 'mobile_app';
        _allowAdminOverride = s.allowAdminOverride;
        _contactController.text = s.contactNumber ?? '';
        _timeoutController.text = s.smsTimeoutMinutes.toString();
        _autoPauseEnabled =
            acceptance?['autoPauseEnabled'] as bool? ?? true;
        _consecutiveMissesThreshold =
            (acceptance?['consecutiveMissesThreshold'] as num?)?.toInt() ?? 2;
        _timerSeconds =
            (acceptance?['timerSeconds'] as num?)?.toInt() ?? 180;
        _consecutiveController.text =
            _consecutiveMissesThreshold.toString();
        _timerController.text = _timerSeconds.toString();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String? _validate() {
    if (!_hasDevice) {
      final contact = _contactController.text.trim();
      if (contact.isEmpty) {
        return 'Contact number is required when restaurant has no device.';
      }
      if (!RegExp(r'^\+?639\d{9}$|^09\d{9}$').hasMatch(contact.replaceAll(' ', ''))) {
        return 'Enter a valid Philippine mobile number (e.g. 09171234567 or +639171234567).';
      }
    }
    final timeout = int.tryParse(_timeoutController.text.trim());
    if (timeout == null || timeout < 1 || timeout > 60) {
      return 'SMS timeout must be between 1 and 60 minutes.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final timeout = int.parse(_timeoutController.text.trim());
      final contact = _hasDevice ? null : _contactController.text.trim();
      final allowOverride = _hasDevice ? _allowAdminOverride : true;
      final settings = RestaurantOrderSettings(
        hasDevice: _hasDevice,
        deviceType: _hasDevice ? _deviceType : null,
        contactNumber: contact,
        smsTimeoutMinutes: timeout,
        allowAdminOverride: allowOverride,
      );
      await _service.saveSettings(widget.vendorId, settings);
      final consecutive = int.tryParse(_consecutiveController.text) ?? 2;
      final timer = int.tryParse(_timerController.text) ?? 180;
      await _service.updateAcceptanceSettings(
        widget.vendorId,
        autoPauseEnabled: _autoPauseEnabled,
        consecutiveMissesThreshold: consecutive.clamp(1, 10),
        timerSeconds: timer.clamp(60, 600),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.restaurantName ?? 'Restaurant Settings'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurantName ?? 'Restaurant Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Device Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Does this restaurant have a device (tablet, smartphone, or computer)?',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Has device')),
                        ButtonSegment(value: false, label: Text('No device')),
                      ],
                      selected: {_hasDevice},
                      onSelectionChanged: (v) {
                        setState(() {
                          _hasDevice = v.first;
                          if (!_hasDevice) _allowAdminOverride = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_hasDevice) ...[
              const Text(
                'Device Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _deviceType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _deviceTypes
                    .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _deviceType = v);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Allow Admin Override'),
                subtitle: const Text(
                  'Admin can accept or reject orders even when restaurant has a device (e.g. when busy).',
                ),
                value: _allowAdminOverride,
                onChanged: (v) => setState(() => _allowAdminOverride = v),
              ),
            ] else ...[
              const Text(
                'Contact Number',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  hintText: 'e.g. 09171234567 or +639171234567',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                'SMS notifications will be sent to this number for new orders. Admin will accept/reject on behalf of the restaurant.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Order Acceptance (Auto-Pause)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Enable Auto-Pause'),
              subtitle: const Text(
                'Automatically pause restaurant after consecutive missed orders.',
              ),
              value: _autoPauseEnabled,
              onChanged: (v) => setState(() => _autoPauseEnabled = v),
            ),
            if (_autoPauseEnabled) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _consecutiveController,
                decoration: const InputDecoration(
                  labelText: 'Consecutive Misses Threshold',
                  suffixText: 'misses',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) setState(() => _consecutiveMissesThreshold = n);
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _timerController,
                decoration: const InputDecoration(
                  labelText: 'Acceptance Timer',
                  suffixText: 'seconds',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) setState(() => _timerSeconds = n);
                },
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'SMS Timeout',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _timeoutController,
              decoration: const InputDecoration(
                hintText: '5',
                suffixText: 'minutes',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              'Minutes to wait for admin action before auto-cancelling (for restaurants without device).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
