import 'package:flutter/material.dart';
import 'package:brgy/model/ReferralConfig.dart';
import 'package:brgy/services/referral_service.dart';
import 'package:brgy/pages/referral_relationships_page.dart';
import 'package:brgy/pages/referral_wallet_balances_page.dart';

class ReferralSettingsPage extends StatefulWidget {
  const ReferralSettingsPage({super.key});

  @override
  State<ReferralSettingsPage> createState() => _ReferralSettingsPageState();
}

class _ReferralSettingsPageState extends State<ReferralSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral System Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<ReferralConfig>(
        stream: ReferralService.getReferralConfigStream(),
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
              ReferralConfig(
                rewardAmount: 0.0,
                minOrderAmount: 0.0,
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
                        const Icon(Icons.people,
                            color: Colors.orange, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Referral System',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                config.enabled
                                    ? 'Enabled - Rewards credited after first successful order'
                                    : 'Disabled - Referral system is inactive',
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
                              await ReferralService.updateMasterToggle(value);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'Referral System enabled'
                                          : 'Referral System disabled',
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

                // Quick Actions
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        elevation: 4,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ReferralRelationshipsPage(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(Icons.link, color: Colors.orange, size: 32),
                                const SizedBox(height: 8),
                                const Text(
                                  'View Relationships',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        elevation: 4,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ReferralWalletBalancesPage(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(Icons.account_balance_wallet,
                                    color: Colors.orange, size: 32),
                                const SizedBox(height: 8),
                                const Text(
                                  'View Wallets',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                          'Referral Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ReferralConfigForm(config: config),
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

class _ReferralConfigForm extends StatefulWidget {
  final ReferralConfig config;

  const _ReferralConfigForm({required this.config});

  @override
  State<_ReferralConfigForm> createState() => _ReferralConfigFormState();
}

class _ReferralConfigFormState extends State<_ReferralConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _rewardAmountController;
  late TextEditingController _minOrderAmountController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _rewardAmountController =
        TextEditingController(text: config.rewardAmount.toString());
    _minOrderAmountController =
        TextEditingController(text: config.minOrderAmount.toString());
  }

  @override
  void dispose() {
    _rewardAmountController.dispose();
    _minOrderAmountController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final rewardAmount = double.parse(_rewardAmountController.text.trim());
      final minOrderAmount =
          double.parse(_minOrderAmountController.text.trim());

      if (rewardAmount <= 0) {
        throw Exception('Reward amount must be greater than 0');
      }

      if (minOrderAmount < 0) {
        throw Exception('Minimum order amount cannot be negative');
      }

      final config = ReferralConfig(
        enabled: widget.config.enabled,
        rewardAmount: rewardAmount,
        minOrderAmount: minOrderAmount,
      );

      await ReferralService.updateReferralConfig(config);

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
          // Reward Amount
          TextFormField(
            controller: _rewardAmountController,
            decoration: const InputDecoration(
              labelText: 'Reward Amount (₱) *',
              hintText: 'e.g., 50.00',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a reward amount';
              }
              final numValue = double.tryParse(value.trim());
              if (numValue == null || numValue <= 0) {
                return 'Please enter a valid positive number';
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

