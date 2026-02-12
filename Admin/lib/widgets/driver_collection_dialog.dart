import 'package:flutter/material.dart';
import 'package:brgy/services/driver_collection_service.dart';
import 'package:brgy/main.dart';

class DriverCollectionDialog extends StatefulWidget {
  final String driverId;
  final String driverName;
  final double currentBalance;

  const DriverCollectionDialog({
    Key? key,
    required this.driverId,
    required this.driverName,
    required this.currentBalance,
  }) : super(key: key);

  @override
  State<DriverCollectionDialog> createState() =>
      _DriverCollectionDialogState();
}

class _DriverCollectionDialogState extends State<DriverCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '50.00');
  final _reasonController = TextEditingController();
  final _collectionService = DriverCollectionService();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid amount';
      });
      return;
    }

    if (amount > widget.currentBalance) {
      setState(() {
        _errorMessage =
            'Insufficient balance. Available: ₱${widget.currentBalance.toStringAsFixed(2)}';
      });
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a reason for collection';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final currentUser = MyAppState.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await _collectionService.collectFromDriver(
        driverId: widget.driverId,
        driverName: widget.driverName,
        amount: amount,
        reason: reason,
        collectedBy: currentUser.userID,
        collectedByName: currentUser.fullName(),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully collected ₱${amount.toStringAsFixed(2)} from ${widget.driverName}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Enhanced error messages for better user feedback
      String userMessage;
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('collection already in progress')) {
        userMessage = 'Another collection is in progress. Please wait a moment and try again.';
      } else if (errorString.contains('insufficient')) {
        userMessage = 'Insufficient wallet balance. The driver does not have enough funds.';
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        userMessage = 'Network error. Please check your connection and try again.';
      } else if (errorString.contains('driver not found')) {
        userMessage = 'Driver not found. Please refresh and try again.';
      } else if (errorString.contains('amount must be greater')) {
        userMessage = 'Collection amount must be greater than zero.';
      } else if (errorString.contains('exceeds maximum')) {
        userMessage = 'Collection amount exceeds the maximum limit.';
      } else {
        userMessage = e.toString().replaceAll('Exception: ', '');
        if (userMessage.isEmpty) {
          userMessage = 'Collection failed. Please try again.';
        }
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.money_off, color: Colors.red, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Collect from Driver',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver: ${widget.driverName}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Current Balance: ₱${widget.currentBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Collection Amount',
                    hintText: 'Enter amount',
                    prefixText: '₱',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an amount';
                    }
                    final amount = double.tryParse(value.trim());
                    if (amount == null || amount <= 0) {
                      return 'Please enter a valid amount';
                    }
                    if (amount > widget.currentBalance) {
                      return 'Amount exceeds available balance';
                    }
                    return null;
                  },
                  enabled: !_isSubmitting,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason for Collection *',
                    hintText: 'Enter reason for collection',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  minLines: 2,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Reason is required';
                    }
                    return null;
                  },
                  enabled: !_isSubmitting,
                  onFieldSubmitted: (_) => _handleSubmit(),
                ),
                if (_errorMessage != null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Confirm Collection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

