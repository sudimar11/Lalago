import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/auto_accept_service.dart';
import 'package:brgy/services/order_acceptance_service.dart';
import 'package:brgy/services/order_rejection_service.dart';
import 'package:brgy/services/manual_dispatch_service.dart';
import 'package:brgy/services/driver_change_service.dart';
import 'package:brgy/services/auto_redispatch_service.dart';
import 'package:brgy/services/driver_assignment_service.dart';
import 'package:brgy/services/driver_response_tracking_service.dart';
import 'package:brgy/widgets/orders/assignments_log_list.dart';
import 'package:brgy/widgets/orders/order_helpers.dart';
import 'package:brgy/widgets/orders/order_preparation_dialog.dart';
import 'package:brgy/widgets/orders/order_rejection_dialog.dart';
import 'package:brgy/widgets/orders/change_driver_dialog.dart';
import 'package:brgy/widgets/orders/order_info_section.dart';
import 'package:brgy/services/sms_service.dart';

class OrderDispatcherPage extends StatefulWidget {
  final int initialTabIndex;
  const OrderDispatcherPage({super.key, this.initialTabIndex = 0});

  @override
  State<OrderDispatcherPage> createState() => _OrderDispatcherPageState();
}

class _OrderDispatcherPageState extends State<OrderDispatcherPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  // Used to force a rebuild on pull-to-refresh without altering streams.
  int _refreshBump = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pullToRefresh() async {
    // Just bump a counter to rebuild widgets; streams will fetch fresh snapshots.
    setState(() => _refreshBump++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabBarView(
        controller: _tab,
        children: [
          // --- TAB 1: assignments_log stream ---
          RefreshIndicator(
            onRefresh: _pullToRefresh,
            child:
                AssignmentsLogList(key: ValueKey('assignments$_refreshBump')),
          ),

          // --- TAB 2: restaurant_orders stream ---
          RefreshIndicator(
            onRefresh: _pullToRefresh,
            child: _RecentOrdersList(key: ValueKey('orders$_refreshBump')),
          ),
        ],
      ),
    );
  }
}

// =================== RECENT ORDERS LIST ===================

class _RecentOrdersList extends StatefulWidget {
  const _RecentOrdersList({super.key});

  @override
  State<_RecentOrdersList> createState() => _RecentOrdersListState();
}

class _RecentOrdersListState extends State<_RecentOrdersList> {
  final Set<String> _dispatching = {};
  final Set<String> _sendingSMS = {}; // Track orders currently sending SMS
  final Map<String, StreamSubscription<QuerySnapshot>> _driverListeners = {};
  final Map<String, StreamSubscription<DocumentSnapshot>>
      _orderStatusListeners = {};
  final Set<String> _trackedOrders =
      {}; // Track which orders we've already logged

  // Auto-accept service
  final AutoAcceptService _autoAcceptService = AutoAcceptService();

  // Order acceptance service
  final OrderAcceptanceService _orderAcceptanceService =
      OrderAcceptanceService();

  // Order rejection service
  final OrderRejectionService _orderRejectionService = OrderRejectionService();

  // Manual dispatch service
  final ManualDispatchService _manualDispatchService = ManualDispatchService();

  // Driver change service
  final DriverChangeService _driverChangeService = DriverChangeService();

  // Auto re-dispatch service
  final AutoRedispatchService _autoRedispatchService = AutoRedispatchService();

  // Driver assignment service
  final DriverAssignmentService _driverAssignmentService =
      DriverAssignmentService();

  // Driver response tracking service
  final DriverResponseTrackingService _driverResponseTrackingService =
      DriverResponseTrackingService();

  @override
  void dispose() {
    // Cancel all active listeners when widget is disposed
    for (var listener in _driverListeners.values) {
      listener.cancel();
    }
    _driverListeners.clear();

    for (var listener in _orderStatusListeners.values) {
      listener.cancel();
    }
    _orderStatusListeners.clear();

    // Dispose auto-accept service
    _autoAcceptService.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return CenteredMessage('Error: ${snap.error}');
        }
        if (!snap.hasData) {
          return const CenteredLoading();
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const CenteredMessage('No recent orders.');
        }

        // Filter out orders with "Order Completed" status
        // Show "Order Rejected" orders from today
        final filteredDocs = docs.where((doc) {
          final data = doc.data();
          final statusRaw = data['status'];
          final status = _statusToText(statusRaw);

          // Filter out completed orders - use exact string 'Order Completed'
          if (status == 'Order Completed') {
            return false;
          }

          // For "Order Rejected" orders, only show if they're from today
          if (status == 'Order Rejected') {
            final createdAt = data['createdAt'];
            if (createdAt != null) {
              final now = DateTime.now();
              final orderTime = createdAt is Timestamp
                  ? createdAt.toDate()
                  : DateTime.parse(createdAt.toString());

              // Check if order is from today (same date)
              final today = DateTime(now.year, now.month, now.day);
              final orderDate = DateTime(
                orderTime.year,
                orderTime.month,
                orderTime.day,
              );

              // Only show rejected orders from today
              if (orderDate.isBefore(today)) {
                return false;
              }
            }
          }

          // Filter scheduled orders: only show if scheduleTime has passed or is null
          final scheduleTime = data['scheduleTime'];
          if (scheduleTime != null) {
            final now = DateTime.now();
            final scheduledDateTime = scheduleTime is Timestamp
                ? scheduleTime.toDate()
                : DateTime.parse(scheduleTime.toString());

            // Exclude if scheduled time is in the future
            if (scheduledDateTime.isAfter(now)) {
              return false;
            }
          }

          return true;
        }).toList();

        if (filteredDocs.isEmpty) {
          return const CenteredMessage('No active orders.');
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: filteredDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final data = filteredDocs[i].data();
            final id = filteredDocs[i].id;

            // Status can be numeric (0..3) or string (e.g., 'confirm', 'driver_assigned')
            final statusRaw = data['status'];
            final status = _statusToText(statusRaw);

            final driverId = (data['driverId'] ??
                    data['driverID'] ??
                    data['driver_id'] ??
                    '') as String? ??
                '';
            final eta = asInt(data['etaMinutes']);
            final createdAt = asTimestamp(data['createdAt']);
            final deliveredAt = asTimestamp(data['deliveredAt']);
            final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;
            final vendorName = (vendor['title'] ?? '') as String? ?? '';

            // Check if this order has status "Order Accepted" or "Order Completed"
            final isOrderAccepted = status == 'Order Accepted';
            final isOrderPlaced = status == 'Order Placed';
            final isDriverAssigned = status == 'Driver Assigned';
            final isDriverPending = status == 'Driver Pending';
            final isOrderCompleted = status == 'Order Completed';
            final isInTransit = status == 'In Transit';
            final isDriverRejected =
                status == 'Driver Rejected' || status == 'driver rejected';
            final isOrderRejected = status == 'Order Rejected';
            final isDispatching = _dispatching.contains(id);

            // Check if order is too old to auto-dispatch (older than 24 hours)
            final isOrderTooOld = createdAt != null &&
                DateTime.now().difference(createdAt.toDate()).inHours > 24;

            // AI Auto-dispatch ONLY when status is "Order Accepted" or "Driver Rejected"
            // Never assign riders if status is not one of these two specific statuses
            // Guard: Skip dispatch for completed or in transit orders
            if (!isDispatching &&
                !isOrderTooOld &&
                !isOrderCompleted &&
                !isInTransit) {
              // Auto-dispatch if driver rejected (NOT if order/restaurant rejected)
              // ONLY if there was a driver who rejected (driverId exists)
              // Additional guard: verify order is not in terminal/active delivery state
              if (isDriverRejected &&
                  !isOrderRejected &&
                  driverId.isNotEmpty &&
                  !isOrderCompleted &&
                  !isInTransit) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoDispatchAfterRejection(context, id, data);
                });
              }
              // Auto-dispatch if order accepted (but not if rejected)
              // ONLY if no driver is assigned yet (prevents re-dispatching)
              // Additional guard: verify order is not in terminal/active delivery state
              else if (isOrderAccepted &&
                  !isOrderRejected &&
                  driverId.isEmpty &&
                  !isOrderCompleted &&
                  !isInTransit) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _manualDispatch(context, id, data);
                });
              }
              // For any other status (including "Order Placed"), do NOT auto-dispatch
            }

            // Auto-accept logic for orders in "Order Placed" status
            if (isOrderPlaced && createdAt != null) {
              // Start auto-accept timer for new orders in "Order Placed" status
              if (!_autoAcceptService.hasActiveTimer(id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoAcceptService.startAutoAcceptTimer(
                    id,
                    createdAt.toDate(),
                    onAutoAccept: () {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '🔄 Order $id auto-accepted after 4 minutes'),
                            backgroundColor: Colors.orange,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  );
                });
              }
            } else {
              // Cancel auto-accept timer if order is no longer in "Order Placed" status
              if (_autoAcceptService.hasActiveTimer(id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoAcceptService.cancelAutoAcceptTimer(id);
                });
              }
            }

            // Show driver name for orders with drivers assigned (not "Order Accepted" or "Order Placed" or "Order Rejected")
            final shouldShowDriverName = !isOrderAccepted &&
                !isOrderPlaced &&
                !isOrderRejected &&
                driverId.isNotEmpty;

            return Card(
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  // Order header with status and actions
                  Container(
                    color: _getStatusColor(status).withOpacity(0.1),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long,
                            size: 20, color: _getStatusColor(status)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${id.substring(0, id.length > 8 ? 8 : id.length)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (createdAt != null) ...[
                                OrderPlacedTimer(
                                  orderCreatedAt: createdAt,
                                  status: status,
                                  deliveredAt: deliveredAt,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatOrderDate(createdAt) ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Change Status',
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () =>
                                  _showChangeStatusDialog(context, id, status),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Order content
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer & Product Info
                        OrderInfoSection(data: data, status: status),

                        const Divider(height: 20),

                        // Status chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (vendorName.isNotEmpty)
                              _InfoChip(
                                icon: Icons.store,
                                label: vendorName,
                                color: Colors.orange,
                              ),
                            // Show driver name for assigned orders (not completed)
                            if (shouldShowDriverName && !isOrderCompleted)
                              DriverNameChip(driverId: driverId),
                            // Show restaurant owner
                            RestaurantOwnerChip(orderData: data),
                            if (eta != null)
                              _InfoChip(
                                icon: Icons.timer,
                                label: '$eta min',
                                color: Colors.blue,
                              ),
                          ],
                        ),

                        // Display rider info for completed orders
                        if (isOrderCompleted && driverId.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _RiderInfoWidget(orderId: id, driverId: driverId),
                        ],
                      ],
                    ),
                  ),
                  // Accept and Reject Order Buttons - Only show for "Order Placed" status
                  if (isOrderPlaced)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isDispatching
                                  ? null
                                  : () => _acceptOrder(context, id),
                              icon: isDispatching
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(
                                  isDispatching ? 'Accepting...' : 'Accept'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isDispatching
                                  ? null
                                  : () => _rejectOrder(context, id),
                              icon: const Icon(Icons.cancel),
                              label: Text(
                                  isDispatching ? 'Processing...' : 'Reject'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Manual Dispatch Button - Only show for "Order Accepted" status
                  if (isOrderAccepted)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isDispatching
                              ? null
                              : () => _manualDispatch(context, id, data),
                          icon: isDispatching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.bolt),
                          label: Text(isDispatching
                              ? 'Dispatching...'
                              : 'Manual Dispatch (AI)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Change Driver Button - Show for "Driver Assigned" and "Driver Pending" statuses
                  if (isDriverAssigned || isDriverPending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isDispatching
                              ? null
                              : () => _showChangeDriverDialog(
                                  context, id, driverId),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Change Driver'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Order Rejected Status - Show rejection info
                  if (isOrderRejected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cancel,
                                    color: Colors.red.shade700, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Order Rejected',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                      if (data['rejectionReason'] != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Reason: ${data['rejectionReason']}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _sendingSMS.contains(id)
                                  ? null
                                  : () => _sendRejectionSMS(context, id, data),
                              icon: _sendingSMS.contains(id)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(_sendingSMS.contains(id)
                                  ? 'Sending SMS...'
                                  : 'Send SMS to Customer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _acceptOrder(BuildContext context, String orderId) async {
    setState(() => _dispatching.add(orderId));

    try {
      // Show dialog to select preparation time
      final preparationTime = await showOrderPreparationDialog(
        context,
        _orderAcceptanceService.getPreparationTimeOptions(),
      );

      // If no time selected, show warning and bail out
      if (!_orderAcceptanceService.isValidPreparationTime(preparationTime)) {
        _orderAcceptanceService.showWarningMessage(context);
        return;
      }

      // Accept the order with selected preparation time
      await _orderAcceptanceService.acceptOrder(
        orderId: orderId,
        preparationTime: preparationTime!,
      );

      // Show success message
      _orderAcceptanceService.showSuccessMessage(context, preparationTime);
    } catch (e, stackTrace) {
      print('[Accept Order] Error: $e\n$stackTrace');
      _orderAcceptanceService.showErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _dispatching.remove(orderId));
      }
    }
  }

  Future<void> _rejectOrder(BuildContext context, String orderId) async {
    setState(() => _dispatching.add(orderId));

    try {
      // Show dialog to select rejection reason
      final rejectionReason = await showOrderRejectionDialog(
        context,
        _orderRejectionService.getRejectionReasonOptions(),
      );

      // If no reason selected, show warning and bail out
      if (!_orderRejectionService.isValidRejectionReason(rejectionReason)) {
        _orderRejectionService.showWarningMessage(context);
        return;
      }

      // Reject the order with selected reason
      await _orderRejectionService.rejectOrder(
        orderId: orderId,
        rejectionReason: rejectionReason!,
      );

      // Show success message
      _orderRejectionService.showSuccessMessage(context, rejectionReason);
    } catch (e, stackTrace) {
      print('[Reject Order] Error: $e\n$stackTrace');
      _orderRejectionService.showErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _dispatching.remove(orderId));
      }
    }
  }

  Future<void> _sendRejectionSMS(
      BuildContext context, String orderId, Map<String, dynamic> data) async {
    setState(() => _sendingSMS.add(orderId));

    try {
      // Check SMS permission first
      final smsService = SMSService();
      if (!smsService.hasSmsPermission) {
        // Show permission dialog
        final bool shouldRequestPermission =
            await _showSMSPermissionDialog(context);

        if (!shouldRequestPermission) {
          // User declined to grant permission
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SMS permission is required to notify customers',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // Request permission
        final bool granted = await smsService.requestPermissions();
        if (!granted) {
          // Permission denied
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SMS permission denied. Please enable it in app settings.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Permission granted, send SMS
      await _orderRejectionService.sendRejectionSMS(orderData: data);
      _orderRejectionService.showSMSSuccessMessage(context);
    } catch (e, stackTrace) {
      print('[Send Rejection SMS] Error: $e\n$stackTrace');
      _orderRejectionService.showSMSErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _sendingSMS.remove(orderId));
      }
    }
  }

  Future<bool> _showSMSPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.sms, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('SMS Permission Required'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This app needs permission to send SMS messages to notify customers about their order status.',
                    style: TextStyle(fontSize: 15),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SMS messages will be sent automatically to inform customers.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(Icons.check),
                  label: Text('Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _manualDispatch(
      BuildContext context, String orderId, Map<String, dynamic> data) async {
    setState(() => _dispatching.add(orderId));

    try {
      // Check if order is already completed or in transit
      final statusRaw = data['status'];
      final status = _statusToText(statusRaw);
      if (status == 'Order Completed' || status == 'In Transit') {
        print(
            '[Manual Dispatch] Order $orderId is already $status. Skipping dispatch.');
        return;
      }

      // Extract vendor location from order data
      final location = _manualDispatchService.extractVendorLocation(data);
      final vendorLat = location['latitude']!;
      final vendorLng = location['longitude']!;

      // Try to dispatch the order
      final result = await _manualDispatchService.dispatchOrder(
        orderId: orderId,
        vendorLat: vendorLat,
        vendorLng: vendorLng,
        findAndAssignDriver: _findAndAssignDriver,
      );

      if (result['success']) {
        // Successfully assigned
        _manualDispatchService.showSuccessMessage(
          context,
          result['driverName'] as String,
          result['distance'] as double,
        );
      } else if (result['needsRetry'] == true) {
        // No active drivers - show retry message and wait
        _manualDispatchService.showRetryMessage(context);

        // Retry dispatch after waiting
        final retryResult = await _manualDispatchService.retryDispatch(
          orderId: orderId,
          vendorLat: vendorLat,
          vendorLng: vendorLng,
          findAndAssignDriver: _findAndAssignDriver,
        );

        // Show retry success message
        _manualDispatchService.showRetrySuccessMessage(
          context,
          retryResult['driverName'] as String,
          retryResult['distance'] as double,
        );
      }
    } catch (e, stackTrace) {
      print('[Manual Dispatch AI] Error: $e\n$stackTrace');
      _manualDispatchService.showErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _dispatching.remove(orderId));
      }
    }
  }

  Future<void> _showChangeDriverDialog(
      BuildContext context, String orderId, String currentDriverId) async {
    setState(() => _dispatching.add(orderId));

    try {
      // Fetch all drivers
      final drivers = await _driverChangeService.fetchAllDrivers();

      if (!context.mounted) return;

      // Check if any drivers exist
      if (!_driverChangeService.hasDrivers(drivers)) {
        _driverChangeService.showNoDriversWarning(context);
        return;
      }

      // Show dialog with list of drivers
      final selectedDriver = await showChangeDriverDialog(
        context,
        drivers: drivers,
        currentDriverId: currentDriverId,
      );

      if (selectedDriver == null || !context.mounted) return;

      // Change the driver for this order
      await _driverChangeService.changeDriverForOrder(
        context: context,
        orderId: orderId,
        newDriverId: selectedDriver['id'] as String,
        newDriverName: selectedDriver['name'] as String,
      );
    } catch (e) {
      print('[Change Driver] Error showing dialog: $e');
      _driverChangeService.showLoadDriversError(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _dispatching.remove(orderId));
      }
    }
  }

  Future<void> _autoDispatchAfterRejection(
      BuildContext context, String orderId, Map<String, dynamic> data) async {
    // Check if already dispatching to avoid duplicate attempts
    if (_dispatching.contains(orderId)) {
      return;
    }

    // Check if order is already completed or in transit
    final statusRaw = data['status'];
    final status = _statusToText(statusRaw);
    if (status == 'Order Completed' || status == 'In Transit') {
      print(
          '[Auto Re-Dispatch] Order $orderId is already $status. Skipping dispatch.');
      return;
    }

    setState(() => _dispatching.add(orderId));

    try {
      // Try to dispatch after rejection
      final result = await _autoRedispatchService.dispatchAfterRejection(
        orderId: orderId,
        orderData: data,
        findAndAssignDriver: _findAndAssignDriver,
      );

      if (result['success']) {
        // Successfully assigned to a new driver
        _autoRedispatchService.showSuccessMessage(
          context,
          result['driverName'] as String,
          result['distance'] as double,
        );
      } else if (result['needsRetry'] == true) {
        // No active drivers - show retry message and wait
        _autoRedispatchService.showRetryMessage(context);

        // Retry dispatch after waiting
        final retryResult =
            await _autoRedispatchService.retryDispatchAfterRejection(
          orderId: orderId,
          vendorLat: result['vendorLat'] as double,
          vendorLng: result['vendorLng'] as double,
          rejectedDriverId: result['rejectedDriverId'] as String?,
          findAndAssignDriver: _findAndAssignDriver,
        );

        if (retryResult['success']) {
          // Successfully assigned after retry
          _autoRedispatchService.showRetrySuccessMessage(
            context,
            retryResult['driverName'] as String,
            retryResult['distance'] as double,
          );
        } else if (retryResult['needsListener'] == true) {
          // Still no drivers - set up listener
          _autoRedispatchService.showWaitingForDriversMessage(context);

          // Set up listener for when drivers come online
          _setupDriverOnlineListener(
            context: context,
            orderId: orderId,
            vendorLat: retryResult['vendorLat'] as double,
            vendorLng: retryResult['vendorLng'] as double,
            excludeDriverId: retryResult['rejectedDriverId'] as String?,
          );
        }
      }
    } catch (e, stackTrace) {
      print('[Auto Re-Dispatch] Error: $e\n$stackTrace');
      _autoRedispatchService.showErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _dispatching.remove(orderId));
      }
    }
  }

  Future<Map<String, dynamic>> _findAndAssignDriver({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    String? excludeDriverId,
  }) async {
    // Guard: Check order status before attempting to assign driver
    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .get();

      if (!orderDoc.exists) {
        print('[Find and Assign Driver] Order $orderId does not exist.');
        return {'success': false, 'message': 'Order not found'};
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final statusRaw = orderData['status'];
      final status = _statusToText(statusRaw);

      // Skip dispatch if order is already completed or in transit
      if (status == 'Order Completed' || status == 'In Transit') {
        print(
            '[Find and Assign Driver] Order $orderId is already $status. Skipping dispatch.');
        return {
          'success': false,
          'message': 'Order is already $status',
          'skipDispatch': true,
        };
      }
    } catch (e) {
      print('[Find and Assign Driver] Error checking order status: $e');
      // Continue with dispatch if we can't verify status
    }

    return await _driverAssignmentService.findAndAssignDriver(
      orderId: orderId,
      vendorLat: vendorLat,
      vendorLng: vendorLng,
      excludeDriverId: excludeDriverId,
      setupDriverResponseListener: _setupDriverResponseListener,
    );
  }

  void _setupDriverOnlineListener({
    required BuildContext context,
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    String? excludeDriverId,
  }) {
    // Cancel any existing listener for this order
    _driverListeners[orderId]?.cancel();

    // Set up a listener using the service
    final listener = _autoRedispatchService.setupDriverOnlineListener(
      context: context,
      orderId: orderId,
      vendorLat: vendorLat,
      vendorLng: vendorLng,
      excludeDriverId: excludeDriverId,
      findAndAssignDriver: _findAndAssignDriver,
      onListenerCancel: (orderId) {
        // Cancel and remove the listener when assignment succeeds
        _driverListeners[orderId]?.cancel();
        _driverListeners.remove(orderId);
      },
    );

    // Store the listener so we can cancel it later
    _driverListeners[orderId] = listener;
  }

  void _setupDriverResponseListener({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
  }) {
    // Cancel any existing listener for this order
    _orderStatusListeners[orderId]?.cancel();

    // Set up listener using the service
    final listener = _driverResponseTrackingService.setupDriverResponseListener(
      orderId: orderId,
      driverId: driverId,
      assignmentLogId: assignmentLogId,
      trackedOrders: _trackedOrders,
      statusToText: _statusToText,
      onListenerComplete: (orderId) {
        // Cancel listener and clean up tracking
        _orderStatusListeners[orderId]?.cancel();
        _orderStatusListeners.remove(orderId);
        _trackedOrders.remove(orderId);
      },
    );

    // Store the listener
    _orderStatusListeners[orderId] = listener;
  }
}

// =================== INFO CHIP ===================

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}

// =================== RIDER INFO WIDGET ===================

class _RiderInfoWidget extends StatelessWidget {
  final String orderId;
  final String driverId;

  const _RiderInfoWidget({
    required this.orderId,
    required this.driverId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchRiderDetails(driverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Loading rider info...',
                    style: TextStyle(color: Colors.blue.shade700)),
              ],
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text('Rider info unavailable',
                    style: TextStyle(color: Colors.orange.shade700)),
              ],
            ),
          );
        }

        final riderData = snapshot.data!;
        final riderName = riderData['name'] as String? ?? 'Unknown Rider';
        final riderPhone = riderData['phone'] as String? ?? '';
        final latitude = riderData['latitude'] as double?;
        final longitude = riderData['longitude'] as double?;
        final hasLocation = latitude != null && longitude != null;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.delivery_dining,
                      size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rider: $riderName',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade900,
                            fontSize: 14,
                          ),
                        ),
                        if (riderPhone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            riderPhone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (hasLocation) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (!hasLocation) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_off,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Location not available',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// =================== DATA HELPERS ===================

String _statusToText(dynamic raw) {
  if (raw == null) return '—';
  if (raw is num) {
    // Map numeric statuses to Set A statuses
    switch (raw.toInt()) {
      case 0:
        return 'Order Placed';
      case 1:
        return 'Order Accepted';
      case 2:
        return 'In Transit';
      case 3:
        return 'Order Completed';
      default:
        return raw.toString();
    }
  }
  if (raw is String) {
    // Normalize string statuses to Set A values
    final normalized = raw.trim();
    switch (normalized.toLowerCase()) {
      case 'request':
      case 'order placed':
        return 'Order Placed';
      case 'confirm':
      case 'order accepted':
        return 'Order Accepted';
      case 'driver assigned':
        return 'Driver Assigned';
      case 'driver pending':
        return 'Driver Pending';
      case 'released':
      case 'in transit':
      case 'order shipped':
        return 'In Transit';
      case 'completed':
      case 'order completed':
        return 'Order Completed';
      case 'order rejected':
        return 'Order Rejected';
      default:
        return normalized;
    }
  }
  return raw.toString();
}

// Format order creation date to human-readable string
String? _formatOrderDate(Timestamp? timestamp) {
  if (timestamp == null) return null;
  final date = timestamp.toDate();

  // Format: "Jan 15, 2025 • 2:30 PM"
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final month = months[date.month - 1];
  final day = date.day;
  final year = date.year;

  // Format time
  final hour = date.hour;
  final minute = date.minute;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  final displayMinute = minute.toString().padLeft(2, '0');

  return '$month $day, $year • $displayHour:$displayMinute $period';
}

// Get color based on order status
Color _getStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'order placed':
      return Colors.blue;
    case 'order accepted':
      return Colors.orange;
    case 'driver assigned':
      return Colors.purple;
    case 'driver pending':
      return Colors.indigo;
    case 'in transit':
      return Colors.indigo;
    case 'order completed':
      return Colors.green;
    case 'order rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

// Change Order Status dialog and update helper
Future<void> _showChangeStatusDialog(
    BuildContext context, String orderId, String currentStatus) async {
  String? selectedStatus = currentStatus;
  final List<String> statuses = <String>[
    'Order Placed',
    'Order Accepted',
    'Driver Assigned',
    'Driver Pending',
    'In Transit',
    'Order Completed',
    'Order Rejected',
  ];

  final String? result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Change Order Status'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Select a new status:'),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedStatus,
                  items: statuses.map((s) {
                    return DropdownMenuItem<String>(
                      value: s,
                      child: Text(s),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => selectedStatus = v),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(selectedStatus),
            child: const Text('Update'),
          ),
        ],
      );
    },
  );

  if (result == null || result.isEmpty || result == currentStatus) return;

  try {
    await _updateOrderStatus(orderId, result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Status updated to "$result"')),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Failed to update status: $e')),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

Future<void> _updateOrderStatus(String orderId, String newStatus) async {
  await FirebaseFirestore.instance
      .collection('restaurant_orders')
      .doc(orderId)
      .update({
    'status': newStatus,
    'statusChangedAt': FieldValue.serverTimestamp(),
  });
}

// Calculate distance between two coordinates using Haversine formula
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371; // Earth's radius in kilometers
  final dLat = (lat2 - lat1) * (pi / 180);
  final dLon = (lon2 - lon1) * (pi / 180);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * (pi / 180)) *
          cos(lat2 * (pi / 180)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c; // Distance in kilometers
}

// Fetch restaurant owner information
// =================== STANDALONE PAGES (NO TABS) ===================

/// Standalone Assignments Log Page (no tabs)
class AssignmentsLogPage extends StatefulWidget {
  const AssignmentsLogPage({super.key});

  @override
  State<AssignmentsLogPage> createState() => _AssignmentsLogPageState();
}

class _AssignmentsLogPageState extends State<AssignmentsLogPage> {
  int _refreshBump = 0;

  Future<void> _pullToRefresh() async {
    setState(() => _refreshBump++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assignments Log'),
        backgroundColor: Colors.deepPurple,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: AssignmentsLogList(key: ValueKey('assignments$_refreshBump')),
      ),
    );
  }
}

/// Standalone Recent Orders Page (no tabs)
class RecentOrdersPage extends StatefulWidget {
  const RecentOrdersPage({super.key});

  @override
  State<RecentOrdersPage> createState() => _RecentOrdersPageState();
}

class _RecentOrdersPageState extends State<RecentOrdersPage> {
  int _refreshBump = 0;

  Future<void> _pullToRefresh() async {
    setState(() => _refreshBump++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: _RecentOrdersList(key: ValueKey('orders$_refreshBump')),
      ),
    );
  }
}

/// Standalone Today's Orders Page (no tabs)
class TodaysOrdersPage extends StatefulWidget {
  const TodaysOrdersPage({super.key});

  @override
  State<TodaysOrdersPage> createState() => _TodaysOrdersPageState();
}

class _TodaysOrdersPageState extends State<TodaysOrdersPage> {
  int _refreshBump = 0;

  Future<void> _pullToRefresh() async {
    setState(() => _refreshBump++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Orders Today"),
        backgroundColor: Colors.orange,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: _TodaysOrdersList(key: ValueKey('ordersToday$_refreshBump')),
      ),
    );
  }
}

class _TodaysOrdersList extends StatefulWidget {
  const _TodaysOrdersList({super.key});

  @override
  State<_TodaysOrdersList> createState() => _TodaysOrdersListState();
}

class _TodaysOrdersListState extends State<_TodaysOrdersList> {
  final Set<String> _sendingSMS = {}; // Track orders currently sending SMS
  final OrderRejectionService _orderRejectionService = OrderRejectionService();

  Future<void> _sendRejectionSMS(
      BuildContext context, String orderId, Map<String, dynamic> data) async {
    setState(() => _sendingSMS.add(orderId));

    try {
      // Check SMS permission first
      final smsService = SMSService();
      if (!smsService.hasSmsPermission) {
        // Show permission dialog
        final bool shouldRequestPermission =
            await _showSMSPermissionDialog(context);

        if (!shouldRequestPermission) {
          // User declined to grant permission
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SMS permission is required to notify customers',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // Request permission
        final bool granted = await smsService.requestPermissions();
        if (!granted) {
          // Permission denied
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SMS permission denied. Please enable it in app settings.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Permission granted, send SMS
      await _orderRejectionService.sendRejectionSMS(orderData: data);
      _orderRejectionService.showSMSSuccessMessage(context);
    } catch (e, stackTrace) {
      print('[Send Rejection SMS] Error: $e\n$stackTrace');
      _orderRejectionService.showSMSErrorMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _sendingSMS.remove(orderId));
      }
    }
  }

  Future<bool> _showSMSPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.sms, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('SMS Permission Required'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This app needs permission to send SMS messages to notify customers about their order status.',
                    style: TextStyle(fontSize: 15),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SMS messages will be sent automatically to inform customers.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(Icons.check),
                  label: Text('Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    final query = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return CenteredMessage('Error: ${snap.error}');
        }
        if (!snap.hasData) {
          return const CenteredLoading();
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const CenteredMessage('No orders today.');
        }

        // Filter out orders with "Order Completed" status and old "Order Rejected" orders
        final filteredDocs = docs.where((doc) {
          final data = doc.data();
          final statusRaw = data['status'];
          final status = _statusToText(statusRaw);

          // Filter out completed orders - use exact string 'Order Completed'
          if (status == 'Order Completed') {
            return false;
          }

          // Filter out "Order Rejected" orders older than 15 minutes
          if (status == 'Order Rejected') {
            final createdAt = data['createdAt'];
            if (createdAt != null) {
              final now = DateTime.now();
              final orderTime = createdAt is Timestamp
                  ? createdAt.toDate()
                  : DateTime.parse(createdAt.toString());
              final timeDifference = now.difference(orderTime);

              // If order is rejected and older than 15 minutes, don't display it
              if (timeDifference.inMinutes > 15) {
                return false;
              }
            }
          }

          // Filter scheduled orders: only show if scheduleTime has passed or is null
          final scheduleTime = data['scheduleTime'];
          if (scheduleTime != null) {
            final now = DateTime.now();
            final scheduledDateTime = scheduleTime is Timestamp
                ? scheduleTime.toDate()
                : DateTime.parse(scheduleTime.toString());

            // Exclude if scheduled time is in the future
            if (scheduledDateTime.isAfter(now)) {
              return false;
            }
          }

          return true;
        }).toList();

        if (filteredDocs.isEmpty) {
          return const CenteredMessage('No active orders today.');
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: filteredDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final data = filteredDocs[i].data();
            final id = filteredDocs[i].id;

            final statusRaw = data['status'];
            final status = _statusToText(statusRaw);

            final driverId = (data['driverId'] ??
                    data['driverID'] ??
                    data['driver_id'] ??
                    '') as String? ??
                '';
            final eta = asInt(data['etaMinutes']);
            final createdAt = asTimestamp(data['createdAt']);
            final deliveredAt = asTimestamp(data['deliveredAt']);
            final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;
            final vendorName = (vendor['title'] ?? '') as String? ?? '';

            final isOrderAccepted = status == 'Order Accepted';
            final isOrderPlaced = status == 'Order Placed';
            final isOrderCompleted = status == 'Order Completed';
            final isOrderRejected = status == 'Order Rejected';

            final shouldShowDriverName = !isOrderAccepted &&
                !isOrderPlaced &&
                !isOrderRejected &&
                driverId.isNotEmpty;

            return Card(
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Container(
                    color: _getStatusColor(status).withOpacity(0.1),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long,
                            size: 20, color: _getStatusColor(status)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${id.substring(0, id.length > 8 ? 8 : id.length)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (createdAt != null) ...[
                                OrderPlacedTimer(
                                  orderCreatedAt: createdAt,
                                  status: status,
                                  deliveredAt: deliveredAt,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatOrderDate(createdAt) ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Change Status',
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () =>
                                  _showChangeStatusDialog(context, id, status),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrderInfoSection(data: data, status: status),
                        const Divider(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (vendorName.isNotEmpty)
                              _InfoChip(
                                icon: Icons.store,
                                label: vendorName,
                                color: Colors.orange,
                              ),
                            if (shouldShowDriverName && !isOrderCompleted)
                              DriverNameChip(driverId: driverId),
                            // Show restaurant owner
                            RestaurantOwnerChip(orderData: data),
                            if (eta != null)
                              _InfoChip(
                                icon: Icons.timer,
                                label: '$eta min',
                                color: Colors.blue,
                              ),
                          ],
                        ),
                        if (isOrderCompleted && driverId.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _RiderInfoWidget(orderId: id, driverId: driverId),
                        ],
                      ],
                    ),
                  ),
                  // Order Rejected Status - Show rejection info
                  if (isOrderRejected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cancel,
                                    color: Colors.red.shade700, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Order Rejected',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                      if (data['rejectionReason'] != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Reason: ${data['rejectionReason']}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _sendingSMS.contains(id)
                                  ? null
                                  : () => _sendRejectionSMS(context, id, data),
                              icon: _sendingSMS.contains(id)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(_sendingSMS.contains(id)
                                  ? 'Sending SMS...'
                                  : 'Send SMS to Customer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Fetch rider details including name, phone, and location
Future<Map<String, dynamic>> _fetchRiderDetails(String driverId) async {
  try {
    final driverDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .get();

    if (!driverDoc.exists) {
      return {
        'name': 'Driver not found',
        'phone': '',
        'latitude': null,
        'longitude': null,
      };
    }

    final driverData = driverDoc.data();
    if (driverData == null) {
      return {
        'name': 'No driver data',
        'phone': '',
        'latitude': null,
        'longitude': null,
      };
    }

    // Get driver name and phone
    final firstName = driverData['firstName'] ?? '';
    final lastName = driverData['lastName'] ?? '';
    final driverName = '$firstName $lastName'.trim();
    final driverPhone = driverData['phoneNumber'] as String? ?? '';

    // Get driver location
    final location = driverData['location'];
    double? latitude;
    double? longitude;

    if (location != null && location is Map) {
      // Handle both Map<String, dynamic> and nested structures
      final lat = location['latitude'];
      final lng = location['longitude'];

      if (lat != null) {
        latitude = lat is double ? lat : (lat is num ? lat.toDouble() : null);
      }
      if (lng != null) {
        longitude = lng is double ? lng : (lng is num ? lng.toDouble() : null);
      }
    }

    return {
      'name': driverName.isEmpty ? 'Unknown Driver' : driverName,
      'phone': driverPhone,
      'latitude': latitude,
      'longitude': longitude,
    };
  } catch (e) {
    print('Error fetching rider details: $e');
    return {
      'name': 'Error loading rider',
      'phone': '',
      'latitude': null,
      'longitude': null,
    };
  }
}
