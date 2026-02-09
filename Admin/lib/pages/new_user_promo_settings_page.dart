import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/NewUserPromoConfig.dart';
import 'package:brgy/services/new_user_promo_service.dart';
import 'package:brgy/pages/new_user_promo_usage_page.dart';
import 'package:intl/intl.dart';

class NewUserPromoSettingsPage extends StatefulWidget {
  const NewUserPromoSettingsPage({super.key});

  @override
  State<NewUserPromoSettingsPage> createState() =>
      _NewUserPromoSettingsPageState();
}

class _NewUserPromoSettingsPageState extends State<NewUserPromoSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New User Promo Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<NewUserPromoConfig>(
        stream: NewUserPromoService.getPromoConfigStream(),
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

          final config = snapshot.data ??
              NewUserPromoConfig(
                discountType: 'fixed_amount',
                discountValue: 0.0,
                minOrderAmount: 0.0,
                validFrom: Timestamp.now(),
                validTo: Timestamp.fromDate(
                  DateTime.now().add(const Duration(days: 365)),
                ),
              );

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
                        const Icon(Icons.local_offer,
                            color: Colors.orange, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'New User Promo',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                config.enabled
                                    ? 'Enabled - Promo valid only for first completed order'
                                    : 'Disabled - Promo is inactive',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: config.enabled,
                          onChanged: (value) async {
                            try {
                              await NewUserPromoService.updateMasterToggle(
                                  value);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'New User Promo enabled'
                                          : 'New User Promo disabled',
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

                // View Usage Statistics Button
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Usage Statistics',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'View detailed statistics about promo usage',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const NewUserPromoUsagePage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.analytics),
                            label: const Text('View Usage Statistics'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Configuration Form
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Promo Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _PromoConfigForm(config: config),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PromoConfigForm extends StatefulWidget {
  final NewUserPromoConfig config;

  const _PromoConfigForm({required this.config});

  @override
  State<_PromoConfigForm> createState() => _PromoConfigFormState();
}

class _PromoConfigFormState extends State<_PromoConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _discountValueController;
  late TextEditingController _minOrderAmountController;
  late String _discountType;
  late DateTime _validFrom;
  late DateTime _validTo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _discountValueController =
        TextEditingController(text: config.discountValue.toString());
    _minOrderAmountController =
        TextEditingController(text: config.minOrderAmount.toString());
    _discountType = config.discountType;
    _validFrom = config.validFrom.toDate();
    _validTo = config.validTo.toDate();
  }

  @override
  void dispose() {
    _discountValueController.dispose();
    _minOrderAmountController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _validFrom : _validTo,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _validFrom = picked;
        } else {
          _validTo = picked;
        }
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_validTo.isBefore(_validFrom) ||
        _validTo.isAtSameMomentAs(_validFrom)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valid To date must be after Valid From date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final discountValue = double.parse(_discountValueController.text.trim());
      final minOrderAmount =
          double.parse(_minOrderAmountController.text.trim());

      if (discountValue <= 0) {
        throw Exception('Discount value must be greater than 0');
      }

      if (_discountType == 'percentage' &&
          (discountValue < 0 || discountValue > 100)) {
        throw Exception('Percentage must be between 0 and 100');
      }

      if (minOrderAmount < 0) {
        throw Exception('Minimum order amount cannot be negative');
      }

      final config = NewUserPromoConfig(
        enabled: widget.config.enabled,
        discountType: _discountType,
        discountValue: discountValue,
        minOrderAmount: minOrderAmount,
        validFrom: Timestamp.fromDate(_validFrom),
        validTo: Timestamp.fromDate(_validTo),
      );

      await NewUserPromoService.updatePromoConfig(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration saved successfully'),
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
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discount Type
          DropdownButtonFormField<String>(
            value: _discountType,
            decoration: const InputDecoration(
              labelText: 'Discount Type *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            items: const [
              DropdownMenuItem(
                value: 'fixed_amount',
                child: Text('Fixed Amount'),
              ),
              DropdownMenuItem(
                value: 'percentage',
                child: Text('Percentage'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _discountType = value!;
              });
            },
          ),
          const SizedBox(height: 16),

          // Discount Value
          TextFormField(
            controller: _discountValueController,
            decoration: InputDecoration(
              labelText: _discountType == 'percentage'
                  ? 'Discount Percentage (%) *'
                  : 'Discount Amount (₱) *',
              hintText: _discountType == 'percentage' ? 'e.g., 10' : 'e.g., 50.00',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.attach_money),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a discount value';
              }
              final numValue = double.tryParse(value.trim());
              if (numValue == null || numValue <= 0) {
                return 'Please enter a valid positive number';
              }
              if (_discountType == 'percentage' &&
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

          // Valid From Date
          InkWell(
            onTap: () => _selectDate(true),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Valid From *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(
                DateFormat('MMM dd, yyyy').format(_validFrom),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Valid To Date
          InkWell(
            onTap: () => _selectDate(false),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Valid To *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event),
              ),
              child: Text(
                DateFormat('MMM dd, yyyy').format(_validTo),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Configuration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

