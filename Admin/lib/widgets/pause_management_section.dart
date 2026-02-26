import 'package:flutter/material.dart';
import 'package:brgy/services/restaurant_performance_service.dart';

/// Reusable widget for admin pause/unpause controls.
class PauseManagementSection extends StatefulWidget {
  const PauseManagementSection({
    super.key,
    required this.vendorId,
    required this.currentPauseStatus,
    required this.onStatusChanged,
  });

  final String vendorId;
  final Map<String, dynamic> currentPauseStatus;
  final VoidCallback onStatusChanged;

  @override
  State<PauseManagementSection> createState() => _PauseManagementSectionState();
}

class _PauseManagementSectionState extends State<PauseManagementSection> {
  bool _isUpdating = false;
  String _selectedReason = 'manual';
  bool _enableAutoUnpause = false;
  DateTime _autoUnpauseTime = DateTime.now().add(const Duration(hours: 1));

  static const _pauseReasons = [
    ('manual', 'Manual pause'),
    ('performance', 'Performance review'),
    ('technical', 'Technical issue'),
    ('emergency', 'Emergency'),
  ];

  bool get _isPaused =>
      widget.currentPauseStatus['isPaused'] == true;

  Future<void> _unpause() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume Receiving Orders?'),
        content: const Text(
          'This restaurant will start receiving orders again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isUpdating = true);
    try {
      await RestaurantPerformanceService.setRestaurantPauseStatus(
        vendorId: widget.vendorId,
        isPaused: false,
        reason: 'admin_unpause',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restaurant is now online'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onStatusChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _pause() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pause Restaurant?'),
        content: const Text(
          'This restaurant will stop receiving orders until you resume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Pause'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isUpdating = true);
    try {
      await RestaurantPerformanceService.setRestaurantPauseStatus(
        vendorId: widget.vendorId,
        isPaused: true,
        reason: _selectedReason,
        autoUnpauseAt: _enableAutoUnpause ? _autoUnpauseTime : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restaurant has been paused'),
          backgroundColor: Colors.orange,
        ),
      );
      widget.onStatusChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _selectAutoUnpauseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_autoUnpauseTime),
    );
    if (picked != null) {
      setState(() {
        _autoUnpauseTime = DateTime(
          _autoUnpauseTime.year,
          _autoUnpauseTime.month,
          _autoUnpauseTime.day,
          picked.hour,
          picked.minute,
        );
        if (_autoUnpauseTime.isBefore(DateTime.now())) {
          _autoUnpauseTime = _autoUnpauseTime.add(const Duration(days: 1));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pause Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusIndicator(),
            const SizedBox(height: 16),
            if (_isPaused) _buildUnpauseSection(),
            if (!_isPaused) _buildPauseSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isPaused ? Colors.red : Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _isPaused ? 'Paused' : 'Active',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildUnpauseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _isUpdating ? null : _unpause,
          icon: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Resume Restaurant'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildPauseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedReason,
          decoration: const InputDecoration(
            labelText: 'Pause reason',
            border: OutlineInputBorder(),
          ),
          items: _pauseReasons
              .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedReason = v);
          },
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          title: const Text('Set auto-unpause time'),
          value: _enableAutoUnpause,
          onChanged: (v) => setState(() => _enableAutoUnpause = v ?? false),
          contentPadding: EdgeInsets.zero,
        ),
        if (_enableAutoUnpause) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                const Text('Auto-unpause at: '),
                TextButton(
                  onPressed: _selectAutoUnpauseTime,
                  child: Text(
                    '${_autoUnpauseTime.hour.toString().padLeft(2, '0')}:'
                    '${_autoUnpauseTime.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isUpdating ? null : _pause,
          icon: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.pause),
          label: const Text('Pause Restaurant'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
