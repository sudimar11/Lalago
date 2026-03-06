import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/model/PautosOrderModel.dart';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

/// Handler for PAUTOS order notifications. Listens to pautosOrderRequestData,
/// plays sound and shows local notification on new assignments.
class PautosOrderNotificationHandler {
  final NotificationService _notificationService;
  final String _userId;
  List<String> _lastPautosOrderRequestData = [];
  static const String _prefKeyLastPautos = 'last_pautos_order_request_data';

  PautosOrderNotificationHandler(this._notificationService, this._userId);

  Future<void> initialize() async {
    await _loadLastPautosData();
  }

  Future<void> _loadLastPautosData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        final last = prefs.getStringList(_prefKeyLastPautos);
        _lastPautosOrderRequestData = last ?? [];
      }
    } catch (e) {
      log('⚠️ Error loading last PAUTOS order data: $e');
    }
  }

  Future<void> _saveLastPautosData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setStringList(
          _prefKeyLastPautos,
          _lastPautosOrderRequestData,
        );
      }
    } catch (e) {
      log('⚠️ Error saving last PAUTOS order data: $e');
    }
  }

  Future<void> handlePautosOrderRequestDataChange(
    List<dynamic> currentPautosOrderRequestData,
  ) async {
    try {
      final currentIds = currentPautosOrderRequestData
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();

      final newIds = currentIds
          .where((id) => !_lastPautosOrderRequestData.contains(id))
          .toList();

      log('🔍 [PAUTOS_NOTIFY] pautosOrderRequestData: $currentIds, new=$newIds');

      if (newIds.isNotEmpty) {
        for (final orderId in newIds) {
          AudioService.instance.playNewOrderSound(orderId: orderId);
          await _showPautosNotification(orderId);
        }
      }

      _lastPautosOrderRequestData = List.from(currentIds);
      await _saveLastPautosData();
    } catch (e) {
      log('❌ Error handling PAUTOS order request data: $e');
    }
  }

  Future<void> _showPautosNotification(String orderId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(PAUTOS_ORDERS)
          .doc(orderId)
          .get();

      String body = 'New PAUTOS assignment. Tap to view.';
      if (doc.exists && doc.data() != null) {
        final order = PautosOrderModel.fromJson({
          ...doc.data()!,
          'id': doc.id,
        });
        final preview = order.shoppingList.length > 60
            ? '${order.shoppingList.substring(0, 60)}...'
            : order.shoppingList;
        body = preview.isNotEmpty ? preview : body;
      }

      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.order,
          title: 'New PAUTOS Assignment',
          body: body,
          priority: NotificationPriority.high,
          payload: {'orderId': orderId, 'type': 'pautos_assignment'},
          notificationId: NotificationService.idOrder + 2,
        ),
      );

      log('✅ PAUTOS notification shown for order: $orderId');
    } catch (e) {
      log('❌ Error showing PAUTOS notification: $e');
    }
  }

  void dispose() {}
}
