import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:intl/intl.dart';

const List<({String id, String label, IconData icon})> _issueTypes = [
  (id: 'late_delivery', label: 'Late delivery', icon: Icons.access_time),
  (id: 'wrong_items', label: 'Wrong items', icon: Icons.wrong_location),
  (id: 'missing_items', label: 'Missing items', icon: Icons.inventory_2_outlined),
  (id: 'cold_food', label: 'Cold food', icon: Icons.ac_unit),
  (id: 'spilled_damaged', label: 'Spilled/damaged', icon: Icons.water_drop),
  (id: 'driver_issue', label: 'Driver issue', icon: Icons.delivery_dining),
  (id: 'payment_issue', label: 'Payment issue', icon: Icons.payment),
  (id: 'other', label: 'Other', icon: Icons.more_horiz),
];

class ReportIssueScreen extends StatefulWidget {
  final OrderModel order;

  const ReportIssueScreen({Key? key, required this.order}) : super(key: key);

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedIssueTypes = {};
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    if (_selectedIssueTypes.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one issue type.';
        _isSubmitting = false;
      });
      return;
    }

    final user = MyAppState.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'Please sign in again.';
        _isSubmitting = false;
      });
      return;
    }

    try {
      final ticket = <String, dynamic>{
        'order_id': widget.order.id,
        'order_total': widget.order.totalAmount,
        'restaurant_name': widget.order.vendor.title,
        'restaurant_id': widget.order.vendorID,
        'order_date': widget.order.createdAt,
        'customer_id': user.userID,
        'customer_name': user.fullName(),
        'customer_email': user.email,
        'customer_phone': user.phoneNumber,
        'issue_types': _selectedIssueTypes.toList(),
        'description': _descriptionController.text.trim(),
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('support_tickets')
          .add(ticket);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. We will look into this shortly.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Report issue error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to submit. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(widget.order.createdAt.toDate());

    return Scaffold(
      backgroundColor: isDarkMode(context)
          ? const Color(DARK_BG_COLOR)
          : Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Report an Issue'),
        foregroundColor: Color(COLOR_PRIMARY),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: isDarkMode(context)
                    ? const Color(DARK_CARD_BG_COLOR)
                    : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order summary',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Order ID: ${widget.order.id}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDarkMode(context)
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.order.vendor.title,
                        style: TextStyle(
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Select issue type(s)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode(context)
                      ? Colors.grey.shade200
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _issueTypes.map((t) {
                  final selected = _selectedIssueTypes.contains(t.id);
                  return FilterChip(
                    selected: selected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 18, color: selected ? Colors.white : null),
                        const SizedBox(width: 6),
                        Text(t.label),
                      ],
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedIssueTypes.add(t.id);
                        } else {
                          _selectedIssueTypes.remove(t.id);
                        }
                      });
                    },
                    selectedColor: Color(COLOR_PRIMARY).withOpacity(0.8),
                    checkmarkColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Add more details about the issue...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: isDarkMode(context)
                      ? const Color(DARK_BG_COLOR)
                      : Colors.white,
                ),
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                SelectableText.rich(
                  TextSpan(
                    text: _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
