import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';

class OrderRecoveryCard extends StatelessWidget {
  final Map<String, dynamic> notificationData;
  final VoidCallback onRecover;
  final VoidCallback onDismiss;

  const OrderRecoveryCard({
    Key? key,
    required this.notificationData,
    required this.onRecover,
    required this.onDismiss,
  }) : super(key: key);

  Map<String, dynamic>? _parseAlternatives() {
    final data = notificationData['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    final raw = data['alternatives'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'payment_failed':
        return Colors.orange;
      case 'out_of_stock':
      case 'item_not_available':
        return Colors.red;
      case 'restaurant_closed':
        return Colors.purple;
      case 'too_busy':
        return Colors.amber;
      case 'distance_too_far':
        return Colors.blue;
      case 'timeout':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'payment_failed':
        return Icons.payment;
      case 'out_of_stock':
      case 'item_not_available':
        return Icons.inventory;
      case 'restaurant_closed':
        return Icons.restaurant;
      case 'too_busy':
        return Icons.timer;
      case 'distance_too_far':
        return Icons.place;
      case 'timeout':
        return Icons.timer_off;
      default:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtype =
        (notificationData['subtype'] ?? notificationData['data']?['failureType'])
            ?.toString() ??
        'unknown';
    final title = notificationData['title'] ?? 'Order Issue';
    final body = notificationData['body'] ?? '';
    final alternatives = _parseAlternatives();
    final color = _colorForType(subtype);
    final icon = _iconForType(subtype);

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),
                if (alternatives != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Alternatives',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSection(
                    context,
                    'Same Restaurant',
                    alternatives['sameRestaurant'] as List?,
                    isProduct: true,
                  ),
                  _buildSection(
                    context,
                    'Similar Items',
                    alternatives['similarProducts'] as List?,
                    isProduct: true,
                  ),
                  _buildSection(
                    context,
                    'Similar Restaurants',
                    alternatives['similarRestaurants'] as List?,
                    isProduct: false,
                  ),
                  if (alternatives['paymentMethods'] != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ((alternatives['paymentMethods'] as List?) ?? [])
                          .map<Widget>((m) {
                        final map = m is Map ? m : null;
                        final label =
                            map?['label'] ?? map?['type'] ?? 'Payment';
                        return Chip(
                          label: Text('$label'),
                          avatar: const Icon(Icons.payment, size: 16),
                        );
                      }).toList(),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Not Now'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: onRecover,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                      ),
                      child: const Text('Try Alternatives'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String sectionTitle,
    List? items, {
    required bool isProduct,
  }) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i] is Map ? items[i] as Map : null;
                if (item == null) return const SizedBox.shrink();
                final name = (item['name'] ?? item['title'] ?? '') as String;
                final photo = (item['photo'] ?? '') as String;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                height: 60,
                                width: 60,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 80,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 60,
      width: 60,
      color: Colors.grey[200],
      child: Icon(Icons.restaurant, color: Colors.grey[400]),
    );
  }
}
