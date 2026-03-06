import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

/// Debug page to inspect why a rider may not be available for dispatch precheck.
class RiderDebugPage extends StatelessWidget {
  final String riderId;

  const RiderDebugPage({Key? key, required this.riderId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dispatch Debug'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection(USERS)
            .doc(riderId)
            .snapshots(),
        builder: (context, riderSnapshot) {
          if (riderSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (riderSnapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${riderSnapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          final doc = riderSnapshot.data;
          if (doc == null || !doc.exists) {
            return const Center(child: Text('Rider not found'));
          }
          final d = doc.data() as Map<String, dynamic>? ?? {};
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _RiderDebugContent(riderId: riderId, data: d),
          );
        },
      ),
    );
  }
}

class _RiderDebugContent extends StatelessWidget {
  final String riderId;
  final Map<String, dynamic> data;

  const _RiderDebugContent({
    required this.riderId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = data['isOnline'] == true;
    final riderAvailability =
        data['riderAvailability'] as String? ?? 'null';
    final checkedOutToday = data['checkedOutToday'] == true;
    final loc = data['location'];
    final locTs = data['locationUpdatedAt'] as Timestamp?;
    final locAgeMins = locTs != null
        ? DateTime.now().difference(locTs.toDate()).inMinutes
        : null;
    final inProgress = data['inProgressOrderID'];
    final currentOrders = (inProgress is List) ? inProgress.length : 0;
    final maxOrders = (data['maxOrders'] as num?)?.toInt() ?? 3;
    final selectedPresetId =
        data['selectedPresetLocationId'] as String? ?? '';

    final passFail = _computePrecheckEligibility(
      isOnline,
      riderAvailability,
      checkedOutToday,
      loc,
      locTs,
      locAgeMins,
      currentOrders,
      maxOrders,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Rider ID', riderId),
        _row('isOnline', isOnline.toString(),
            color: isOnline ? Colors.green : Colors.red),
        _row('riderAvailability', riderAvailability),
        _row('checkedOutToday', checkedOutToday.toString(),
            color: checkedOutToday ? Colors.red : Colors.green),
        _row('checkedInToday', '${data['checkedInToday'] == true}'),
        _section('Location', ''),
        _row('location', loc != null && loc is Map ? 'yes' : 'null',
            color: loc != null && loc is Map ? Colors.green : Colors.red),
        _row(
          'locationUpdatedAt',
          locTs != null
              ? '${locAgeMins}m ago'
              : 'null',
          color: locAgeMins != null && locAgeMins <= 15
              ? Colors.green
              : Colors.red,
        ),
        _section('Orders', ''),
        _row('currentOrders', '$currentOrders'),
        _row('maxOrders', '$maxOrders',
            color: currentOrders < maxOrders ? Colors.green : Colors.red),
        _section('Zone', ''),
        _row('selectedPresetLocationId',
            selectedPresetId.isEmpty ? 'null' : selectedPresetId),
        const Divider(height: 24),
        _section('Precheck eligibility', ''),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: passFail.pass
                ? Colors.green.shade50
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: passFail.pass ? Colors.green : Colors.red,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passFail.pass ? 'PASS' : 'FAIL',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: passFail.pass ? Colors.green.shade800 : Colors.red.shade800,
                ),
              ),
              if (passFail.reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...passFail.reasons
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '• $r',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 14,
                            ),
                          ),
                        )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({bool pass, List<String> reasons}) _computePrecheckEligibility(
    bool isOnline,
    String riderAvailability,
    bool checkedOutToday,
    dynamic loc,
    Timestamp? locTs,
    int? locAgeMins,
    int currentOrders,
    int maxOrders,
  ) {
    final reasons = <String>[];

    if (checkedOutToday) {
      reasons.add('checkedOutToday=true');
    }
    if (riderAvailability == 'offline' ||
        riderAvailability == 'checked_out' ||
        riderAvailability == 'suspended') {
      reasons.add('riderAvailability=$riderAvailability');
    }
    if (!isOnline) {
      reasons.add('isOnline != true');
    }
    if (loc == null || loc is! Map) {
      reasons.add('no location data');
    } else {
      final lat = (loc['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (loc['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lng == 0.0) {
        reasons.add('location is 0,0');
      }
    }
    if (locTs == null) {
      reasons.add('locationUpdatedAt is null');
    } else if (locAgeMins != null && locAgeMins > 15) {
      reasons.add('stale location (${locAgeMins}m > 15m)');
    }
    if (currentOrders >= maxOrders) {
      reasons.add('at capacity ($currentOrders >= $maxOrders)');
    }

    return (
      pass: reasons.isEmpty,
      reasons: reasons.isEmpty ? ['All checks passed'] : reasons,
    );
  }
}
