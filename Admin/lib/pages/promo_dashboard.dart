import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PromoDashboard extends StatelessWidget {
  const PromoDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promo Impact'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('promo_impact')
            .orderBy('analysisDate', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No promo impact data yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Impact is calculated weekly on Monday.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              return _PromoImpactCard(data: doc.data(), promoId: doc.id.split('_').first);
            },
          );
        },
      ),
    );
  }
}

class _PromoImpactCard extends StatelessWidget {
  const _PromoImpactCard({required this.data, required this.promoId});

  final Map<String, dynamic> data;
  final String promoId;

  Color _roiColor() {
    final roi = (data['roi'] as num?)?.toDouble() ?? 0;
    if (roi > 0) return Colors.green;
    if (roi >= -0.1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final incrementalOrders = (data['incrementalOrders'] as num?)?.toInt() ?? 0;
    final incrementalRevenue = (data['incrementalRevenue'] as num?)?.toDouble() ?? 0;
    final roi = (data['roi'] as num?)?.toDouble() ?? 0;
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0;
    final treatmentSize = (data['treatmentGroupSize'] as num?)?.toInt() ?? 0;
    final analysisDate = data['analysisDate'] as String? ?? '-';

    final roiColor = _roiColor();
    String roiLabel;
    if (roi > 0) {
      roiLabel = 'Positive lift';
    } else if (roi >= -0.1) {
      roiLabel = 'Break-even';
    } else {
      roiLabel = 'Subsidy';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    promoId,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: roiColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    roiLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: roiColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Analysis: $analysisDate', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricCell('Incremental Orders', '$incrementalOrders'),
                ),
                Expanded(
                  child: _metricCell('Incremental Revenue', '₱${incrementalRevenue.toStringAsFixed(2)}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _metricCell('ROI', '${(roi * 100).toStringAsFixed(1)}%'),
                ),
                Expanded(
                  child: _metricCell('Confidence', '${(confidence * 100).toInt()}%'),
                ),
                Expanded(
                  child: _metricCell('Sample', '$treatmentSize users'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
