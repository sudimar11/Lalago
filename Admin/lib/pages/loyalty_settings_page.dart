import 'package:flutter/material.dart';
import 'package:brgy/model/LoyaltyConfig.dart';
import 'package:brgy/services/loyalty_service.dart';

class LoyaltySettingsPage extends StatefulWidget {
  const LoyaltySettingsPage({super.key});

  @override
  State<LoyaltySettingsPage> createState() => _LoyaltySettingsPageState();
}

class _LoyaltySettingsPageState extends State<LoyaltySettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Program Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<LoyaltyConfig>(
        stream: LoyaltyService.getConfigStream(),
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

          final config = snapshot.data ?? LoyaltyConfig();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events,
                            color: Colors.orange, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Loyalty Program',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                config.enabled
                                    ? 'Enabled - Tokens awarded on order completion'
                                    : 'Disabled - Loyalty program inactive',
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
                              await LoyaltyService.updateMasterToggle(value);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'Loyalty Program enabled'
                                          : 'Loyalty Program disabled',
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
                _buildSection(
                  'Tokens Per Order',
                  Text(
                    '${config.tokensPerOrder} token(s) per completed order',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  'Cycle Configuration',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quarterly cycles (Jan, Apr, Jul, Oct)',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Timezone: ${config.cycles['timezone'] ?? 'Asia/Manila'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  'Tier Thresholds',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _tierRow('Bronze', config.tiers['bronze']),
                      _tierRow('Silver', config.tiers['silver']),
                      _tierRow('Gold', config.tiers['gold']),
                      _tierRow('Diamond', config.tiers['diamond']),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  'Benefits',
                  Text(
                    'Configured per tier: free delivery (Silver), '
                    'wallet credit (Gold, Diamond), VIP badge (Diamond)',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }

  Widget _tierRow(String name, dynamic tierData) {
    if (tierData == null || tierData is! Map) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('$name: N/A', style: TextStyle(fontSize: 14)),
      );
    }
    final min = tierData['minTokens'];
    final max = tierData['maxTokens'];
    final range = max == null
        ? '$min+ tokens'
        : '$min - $max tokens';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$name: $range', style: const TextStyle(fontSize: 14)),
    );
  }
}
