import 'package:flutter/material.dart';
import 'package:brgy/model/pautos_config.dart';
import 'package:brgy/services/pautos_config_service.dart';

class PautosSettingsPage extends StatefulWidget {
  const PautosSettingsPage({super.key});

  @override
  State<PautosSettingsPage> createState() => _PautosSettingsPageState();
}

class _PautosSettingsPageState extends State<PautosSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAUTOS Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<PautosConfig>(
        stream: PautosConfigService.getPautosConfigStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: SelectableText.rich(
                TextSpan(
                  text: 'Error: ',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          }
          final config = snapshot.data ?? PautosConfig();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _PautosConfigForm(config: config),
          );
        },
      ),
    );
  }
}

class _PautosConfigForm extends StatefulWidget {
  final PautosConfig config;

  const _PautosConfigForm({required this.config});

  @override
  State<_PautosConfigForm> createState() => _PautosConfigFormState();
}

class _PautosConfigFormState extends State<_PautosConfigForm> {
  late TextEditingController _serviceFeeController;
  late TextEditingController _flatDeliveryFeeController;
  late TextEditingController _deliveryBaseFeeController;
  late TextEditingController _deliveryPerKmController;
  late TextEditingController _minimumDistanceKmController;
  late TextEditingController _riderCommissionController;
  late bool _useDistanceDeliveryFee;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initFromConfig(widget.config);
  }

  void _initFromConfig(PautosConfig c) {
    _serviceFeeController = TextEditingController(
      text: c.serviceFeePercent.toString(),
    );
    _flatDeliveryFeeController = TextEditingController(
      text: c.flatDeliveryFee.toString(),
    );
    _deliveryBaseFeeController = TextEditingController(
      text: c.deliveryBaseFee.toString(),
    );
    _deliveryPerKmController = TextEditingController(
      text: c.deliveryPerKm.toString(),
    );
    _minimumDistanceKmController = TextEditingController(
      text: c.minimumDistanceKm.toString(),
    );
    _riderCommissionController = TextEditingController(
      text: c.riderCommissionPercent?.toString() ?? '',
    );
    _useDistanceDeliveryFee = c.useDistanceDeliveryFee;
  }

  @override
  void dispose() {
    _serviceFeeController.dispose();
    _flatDeliveryFeeController.dispose();
    _deliveryBaseFeeController.dispose();
    _deliveryPerKmController.dispose();
    _minimumDistanceKmController.dispose();
    _riderCommissionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final riderComm = _riderCommissionController.text.trim();
      final config = PautosConfig(
        serviceFeePercent: double.tryParse(
          _serviceFeeController.text.trim(),
        ) ??
            10,
        useDistanceDeliveryFee: _useDistanceDeliveryFee,
        flatDeliveryFee: double.tryParse(
          _flatDeliveryFeeController.text.trim(),
        ) ??
            0,
        deliveryBaseFee: double.tryParse(
          _deliveryBaseFeeController.text.trim(),
        ) ??
            0,
        deliveryPerKm: double.tryParse(
          _deliveryPerKmController.text.trim(),
        ) ??
            0,
        minimumDistanceKm: double.tryParse(
          _minimumDistanceKmController.text.trim(),
        ) ??
            1,
        riderCommissionPercent:
            riderComm.isEmpty ? null : double.tryParse(riderComm),
      );
      await PautosConfigService.updatePautosConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PAUTOS settings saved'),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Service Fee',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serviceFeeController,
                  decoration: const InputDecoration(
                    labelText: 'Service fee % (of actual item cost)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Fee',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Use distance-based delivery fee'),
                  value: _useDistanceDeliveryFee,
                  onChanged: (v) => setState(() => _useDistanceDeliveryFee = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_useDistanceDeliveryFee) ...[
                  TextField(
                    controller: _deliveryBaseFeeController,
                    decoration: const InputDecoration(
                      labelText: 'Base delivery fee (₱)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _deliveryPerKmController,
                    decoration: const InputDecoration(
                      labelText: 'Per km (₱)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minimumDistanceKmController,
                    decoration: const InputDecoration(
                      labelText: 'Minimum distance (km)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                ] else
                  TextField(
                    controller: _flatDeliveryFeeController,
                    decoration: const InputDecoration(
                      labelText: 'Flat delivery fee (₱)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rider Commission',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _riderCommissionController,
                  decoration: const InputDecoration(
                    labelText: 'Override % (leave empty for tier-based)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
        ),
      ],
    );
  }
}
