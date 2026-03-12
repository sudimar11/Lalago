import 'package:flutter/material.dart';
import 'package:brgy/services/zone_capacity_service.dart';

class CapacityDashboardWidget extends StatelessWidget {
  final Stream<List<ZoneCapacity>> capacityStream;

  const CapacityDashboardWidget({
    super.key,
    required this.capacityStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ZoneCapacity>>(
      stream: capacityStream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final zones = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              child: Text(
                'Zone Capacity',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                itemCount: zones.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  return _CapacityCard(capacity: zones[i]);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CapacityCard extends StatelessWidget {
  final ZoneCapacity capacity;

  const _CapacityCard({required this.capacity});

  @override
  Widget build(BuildContext context) {
    final isUnlimited = capacity.maxRiders == null;
    final label = isUnlimited
        ? '${capacity.currentActiveRiders} riders'
        : '${capacity.currentActiveRiders} / '
            '${capacity.maxRiders}';
    final isFull = capacity.capacityStatus == 'full';

    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFull
              ? Colors.red.shade200
              : Colors.grey.shade200,
        ),
        boxShadow: [
          if (isFull)
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  capacity.zone.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFull)
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Colors.red,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isUnlimited
                  ? 0
                  : (capacity.utilizationPercentage / 100)
                      .clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                capacity.statusColor,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!isUnlimited)
            Text(
              capacity.capacityStatus.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: capacity.statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isUnlimited)
            Text(
              'UNLIMITED',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
