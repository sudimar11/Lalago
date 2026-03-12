// Admin/lib/pages/change_order_status_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/utils/order_status_helper.dart';

class ChangeOrderStatusPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final String orderId;

  const ChangeOrderStatusPage({
    super.key,
    required this.order,
    required this.orderId,
  });

  @override
  State<ChangeOrderStatusPage> createState() => _ChangeOrderStatusPageState();
}

class _ChangeOrderStatusPageState extends State<ChangeOrderStatusPage> {
  late String _selectedStatus;
  late List<String> _availableStatuses;
  bool _isUpdating = false;
  String? _warningMessage;

  @override
  void initState() {
    super.initState();
    _availableStatuses = OrderStatusHelper.manualAssignableStatuses;
    final currentStatus = widget.order['status'] ?? '';
    _selectedStatus = OrderStatusHelper.getValidStatusOrDefault(currentStatus);

    if (currentStatus != _selectedStatus) {
      _warningMessage = 'Note: Current status "$currentStatus" cannot be '
          'manually set. It has been changed to "$_selectedStatus".';
    }
    final restriction =
        OrderStatusHelper.getStatusRestrictionReason(currentStatus);
    if (restriction != null) {
      _warningMessage = restriction;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Order Status'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${widget.orderId.substring(0, 8)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current Status: ${widget.order['status'] ?? 'Unknown'}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_warningMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _warningMessage!,
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Select New Status',
                border: OutlineInputBorder(),
                helperText: 'Choose the new status for this order',
              ),
              items: _availableStatuses.map((status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(status),
                );
              }).toList(),
              onChanged: _isUpdating
                  ? null
                  : (value) {
                      setState(() {
                        _selectedStatus = value!;
                        _warningMessage = null;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Some statuses (like Driver Rejected) are automatic '
              'and cannot be manually set.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isUpdating ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('CANCEL'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isUpdating ? null : _updateOrderStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isUpdating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('UPDATE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateOrderStatus() async {
    if (!OrderStatusHelper.isManualAssignable(_selectedStatus)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot set status to "$_selectedStatus" manually',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderId)
          .update({
        'status': _selectedStatus,
        'statusChangedAt': FieldValue.serverTimestamp(),
        'lastUpdatedBy': 'admin',
        'statusChangeNotes': 'Manually changed by admin',
      });

      await FirebaseFirestore.instance.collection('order_activity_log').add({
        'orderId': widget.orderId,
        'action': 'status_changed',
        'oldStatus': widget.order['status'],
        'newStatus': _selectedStatus,
        'changedBy': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order status updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}
