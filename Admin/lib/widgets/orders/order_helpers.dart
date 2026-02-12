import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// =================== ORDER PLACED TIMER ===================

class OrderPlacedTimer extends StatefulWidget {
  final Timestamp orderCreatedAt;
  final String? status;
  final Timestamp? deliveredAt;
  const OrderPlacedTimer({
    super.key,
    required this.orderCreatedAt,
    this.status,
    this.deliveredAt,
  });

  @override
  State<OrderPlacedTimer> createState() => _OrderPlacedTimerState();
}

class _OrderPlacedTimerState extends State<OrderPlacedTimer> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _isCompleted = widget.status == 'Order Completed' ||
        widget.status == 'completed' ||
        widget.status == 'Order Rejected' ||
        widget.status == 'order rejected';
    _updateElapsed();

    // Only start timer for non-completed and non-rejected orders
    if (!_isCompleted) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _updateElapsed();
          });
        }
      });
    }
  }

  void _updateElapsed() {
    final now = DateTime.now();
    if (_isCompleted && widget.deliveredAt != null) {
      // For completed orders, show time since delivery
      final delivered = widget.deliveredAt!.toDate();
      _elapsed = now.difference(delivered);
    } else {
      // For active orders, show time since creation
      final created = widget.orderCreatedAt.toDate();
      _elapsed = now.difference(created);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _getTimerColor() {
    if (_isCompleted) {
      if (widget.status == 'Order Rejected' ||
          widget.status == 'order rejected') {
        return Colors.red; // Red for rejected orders
      }
      return Colors.green; // Green for completed orders
    }

    // Special color logic for "Order Placed" status with auto-accept countdown
    if (widget.status == 'Order Placed') {
      final minutes = _elapsed.inMinutes;
      if (minutes >= 4) {
        return Colors.orange; // Orange when auto-accepting
      } else if (minutes >= 3) {
        return Colors.red; // Red when close to auto-accept
      } else if (minutes >= 2) {
        return Colors.orange; // Orange when getting close
      } else {
        return Colors.green; // Green for first 2 minutes
      }
    }

    // Default color logic for other statuses
    final minutes = _elapsed.inMinutes;
    if (minutes < 3) return Colors.green;
    if (minutes < 6) return Colors.orange;
    return Colors.red;
  }

  String _formatDuration([Duration? duration]) {
    final d = duration ?? _elapsed;
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    final parts = <String>[];

    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}mins');
    if (seconds > 0 || parts.isEmpty) parts.add('${seconds}sec');

    return parts.join(' ');
  }

  String _getDisplayText() {
    if (_isCompleted) {
      if (widget.status == 'Order Rejected' ||
          widget.status == 'order rejected') {
        return 'Rejected after ${_formatDuration()}';
      }
      return 'Completed in ${_formatDuration()}';
    }

    // Show auto-accept countdown for "Order Placed" status
    if (widget.status == 'Order Placed') {
      final autoAcceptDuration = const Duration(minutes: 4);
      final remainingDuration = autoAcceptDuration - _elapsed;

      if (remainingDuration.isNegative) {
        return 'Auto-accept in ${_formatDuration(Duration.zero)}';
      } else {
        return 'Auto-accept in ${_formatDuration(remainingDuration)}';
      }
    }

    return _formatDuration();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _getTimerColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _getTimerColor(), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isCompleted
                ? (widget.status == 'Order Rejected' ||
                        widget.status == 'order rejected'
                    ? Icons.cancel
                    : Icons.check_circle)
                : (widget.status == 'Order Placed' && _elapsed.inMinutes >= 4
                    ? Icons.auto_awesome
                    : Icons.timer),
            size: 12,
            color: _getTimerColor(),
          ),
          const SizedBox(width: 4),
          Text(
            _getDisplayText(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _getTimerColor(),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// =================== UI HELPER WIDGETS ===================

class OrderChip extends StatelessWidget {
  final String label;
  final String value;
  const OrderChip(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class DriverNameChip extends StatelessWidget {
  final String driverId;
  const DriverNameChip({super.key, required this.driverId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: fetchDriverInfo(driverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Chip(
            avatar: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text('Driver: Loading...'),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return OrderChip('Driver', driverId); // Fallback to ID
        }

        final driverInfo = snapshot.data!;
        final driverName = driverInfo['name']!;
        final driverPhone = driverInfo['phone'] ?? '';

        return Chip(
          avatar: Icon(Icons.person, size: 16),
          label: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Driver: $driverName'),
              if (driverPhone.isNotEmpty)
                Text(
                  driverPhone,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.blue.shade50,
        );
      },
    );
  }
}

class RestaurantOwnerChip extends StatelessWidget {
  final Map<String, dynamic> orderData;
  const RestaurantOwnerChip({super.key, required this.orderData});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: fetchRestaurantOwnerInfo(orderData),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Chip(
            avatar: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text('Owner: Loading...'),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return OrderChip('Owner', 'Unknown'); // Fallback
        }

        final ownerInfo = snapshot.data!;
        final ownerName = ownerInfo['name']!;
        final ownerPhone = ownerInfo['phone'] ?? '';

        return Chip(
          avatar: Icon(Icons.restaurant, size: 16),
          label: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Owner: $ownerName'),
              if (ownerPhone.isNotEmpty)
                Text(
                  ownerPhone,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.purple.shade50,
        );
      },
    );
  }
}

class CenteredMessage extends StatelessWidget {
  final String text;
  const CenteredMessage(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
  }
}

class CenteredLoading extends StatelessWidget {
  const CenteredLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

// =================== DATA HELPER FUNCTIONS ===================

/// Convert dynamic value to int
int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final n = int.tryParse(v);
    return n;
  }
  return null;
}

/// Convert dynamic value to double
double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) {
    final n = double.tryParse(v);
    return n;
  }
  return null;
}

/// Convert dynamic value to Timestamp
Timestamp? asTimestamp(dynamic v) {
  if (v is Timestamp) return v;
  // If saved as Date in admin SDK, it might arrive as Timestamp already.
  // If saved as milliseconds, you can add a conversion here.
  return null;
}

/// Fetch driver name and phone from Firestore
Future<Map<String, String>> fetchDriverInfo(String driverId) async {
  try {
    final driverDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .get();

    if (!driverDoc.exists) {
      return {'name': 'Unknown Driver', 'phone': ''};
    }

    final driverData = driverDoc.data();
    if (driverData == null) {
      return {'name': 'Unknown Driver', 'phone': ''};
    }

    final firstName = driverData['firstName'] ?? '';
    final lastName = driverData['lastName'] ?? '';
    final driverName = '$firstName $lastName'.trim();
    final driverPhone = driverData['phoneNumber'] as String? ?? '';

    return {
      'name': driverName.isEmpty ? 'Unknown Driver' : driverName,
      'phone': driverPhone,
    };
  } catch (e) {
    print('Error fetching driver info: $e');
    return {'name': 'Unknown Driver', 'phone': ''};
  }
}

/// Fetch restaurant owner name and phone from Firestore
Future<Map<String, String>> fetchRestaurantOwnerInfo(
    Map<String, dynamic> orderData) async {
  try {
    final vendor = (orderData['vendor'] ?? {}) as Map<String, dynamic>;
    final vendorId = vendor['id'] as String? ?? '';

    if (vendorId.isEmpty) {
      return {'name': 'Unknown Owner', 'phone': ''};
    }

    final vendorDoc = await FirebaseFirestore.instance
        .collection('vendors')
        .doc(vendorId)
        .get();

    if (!vendorDoc.exists) {
      return {'name': 'Unknown Owner', 'phone': ''};
    }

    final vendorData = vendorDoc.data();
    if (vendorData == null) {
      return {'name': 'Unknown Owner', 'phone': ''};
    }

    final ownerName = 'Unknown Owner';
    final ownerPhone = vendorData['phonenumber'] as String? ?? '';

    return {
      'name': ownerName,
      'phone': ownerPhone,
    };
  } catch (e) {
    print('Error fetching restaurant owner info: $e');
    return {'name': 'Unknown Owner', 'phone': ''};
  }
}
