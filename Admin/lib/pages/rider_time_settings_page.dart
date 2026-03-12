import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RiderTimeSettingsPage extends StatefulWidget {
  const RiderTimeSettingsPage({super.key});

  @override
  State<RiderTimeSettingsPage> createState() => _RiderTimeSettingsPageState();
}

class _RiderTimeSettingsPageState extends State<RiderTimeSettingsPage> {
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  int _inactivityTimeoutMinutes = 15;
  int _checkIntervalMinutes = 5;
  bool _excludeWithActiveOrders = true;

  late final TextEditingController _timeoutController;
  late final TextEditingController _intervalController;

  @override
  void initState() {
    super.initState();
    _timeoutController = TextEditingController(text: '15');
    _intervalController = TextEditingController(text: '5');
    _loadConfig();
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    final doc = await _firestore
        .collection('config')
        .doc('rider_time_settings')
        .get();

    final data = doc.data();

    final timeout = (data?['inactivityTimeoutMinutes'] as num?)?.toInt() ?? 15;
    final interval = (data?['checkIntervalMinutes'] as num?)?.toInt() ?? 5;
    setState(() {
      _inactivityTimeoutMinutes = timeout;
      _checkIntervalMinutes = interval;
      _excludeWithActiveOrders =
          data?['excludeWithActiveOrders'] as bool? ?? true;
      _isLoading = false;
    });
    _timeoutController.text = timeout.toString();
    _intervalController.text = interval.toString();
  }

  Future<void> _save() async {
    final timeout = int.tryParse(_timeoutController.text);
    final interval = int.tryParse(_intervalController.text);
    if (timeout != null && timeout >= 1 && timeout <= 60) {
      _inactivityTimeoutMinutes = timeout;
    }
    if (interval != null && interval >= 1 && interval <= 30) {
      _checkIntervalMinutes = interval;
    }

    setState(() => _isSaving = true);

    await _firestore
        .collection('config')
        .doc('rider_time_settings')
        .set({
      'inactivityTimeoutMinutes': _inactivityTimeoutMinutes,
      'checkIntervalMinutes': _checkIntervalMinutes,
      'excludeWithActiveOrders': _excludeWithActiveOrders,
    }, SetOptions(merge: true));

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider time settings saved'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Rider Time Settings'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Time Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inactivity Auto-Logout',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Riders with no location update or order activity '
                      'within the timeout are automatically logged out.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Inactivity timeout (minutes)',
                hintText: '15',
                helperText:
                    '1-60. Riders idle longer than this are auto-logged out.',
                border: OutlineInputBorder(),
              ),
              controller: _timeoutController,
            ),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Check interval (minutes)',
                hintText: '5',
                helperText:
                    '1-30. Cloud Function runs this often. (Schedule may differ.)',
                border: OutlineInputBorder(),
              ),
              controller: _intervalController,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Exclude riders with active orders'),
              subtitle: Text(
                'If on, riders delivering orders are never auto-logged out.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              value: _excludeWithActiveOrders,
              onChanged: (v) {
                setState(() => _excludeWithActiveOrders = v);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
