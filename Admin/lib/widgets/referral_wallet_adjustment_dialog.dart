import 'package:flutter/material.dart';
import 'package:brgy/services/referral_service.dart';
import 'package:brgy/main.dart';

class ReferralWalletAdjustmentDialog extends StatefulWidget {
  final String userId;
  final double currentBalance;

  const ReferralWalletAdjustmentDialog({
    required this.userId,
    required this.currentBalance,
    super.key,
  });

  @override
  State<ReferralWalletAdjustmentDialog> createState() =>
      _ReferralWalletAdjustmentDialogState();
}

class _ReferralWalletAdjustmentDialogState
    extends State<ReferralWalletAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  String _adjustmentType = 'add';
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double get _newBalance {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (_adjustmentType == 'add') {
      return widget.currentBalance + amount;
    } else {
      return widget.currentBalance - amount;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    final reason = _reasonController.text.trim();

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amount must be greater than 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_adjustmentType == 'deduct' && amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient balance for deduction'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final adminId = MyAppState.currentUser?.userID ?? '';
      final adminName =
          '${MyAppState.currentUser?.firstName ?? ''} ${MyAppState.currentUser?.lastName ?? ''}'
              .trim();

      if (adminId.isEmpty || adminName.isEmpty) {
        throw Exception('Admin information not available');
      }

      await ReferralService.adjustReferralWallet(
        widget.userId,
        _adjustmentType,
        amount,
        reason,
        adminId,
        adminName,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wallet ${_adjustmentType == 'add' ? 'credited' : 'deducted'} successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to adjust wallet: $e'),
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
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adjust Referral Wallet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current Balance: ₱${widget.currentBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // Adjustment Type
                DropdownButtonFormField<String>(
                  value: _adjustmentType,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment Type *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'add',
                      child: Text('Add Credit'),
                    ),
                    DropdownMenuItem(
                      value: 'deduct',
                      child: Text('Deduct Credit'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _adjustmentType = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₱) *',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an amount';
                    }
                    final numValue = double.tryParse(value.trim());
                    if (numValue == null || numValue <= 0) {
                      return 'Please enter a valid positive number';
                    }
                    if (_adjustmentType == 'deduct' &&
                        numValue > widget.currentBalance) {
                      return 'Amount exceeds current balance';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // New Balance Preview
                if (_amountController.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'New Balance: ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '₱${_newBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _newBalance < 0 ? Colors.red : Colors.green,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Reason
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason *',
                    hintText: 'Enter reason for adjustment',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a reason';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
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
                          : const Text('Submit'),
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

