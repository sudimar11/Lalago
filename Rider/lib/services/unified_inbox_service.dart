import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/services/chat_read_service.dart';
import 'package:foodie_driver/services/group_chat_service.dart';

class UnifiedInboxService {
  UnifiedInboxService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Stream<int> getSupportUnreadCountStream(String riderId) {
    return _firestore
        .collection('chat_admin_driver')
        .where('driverId', isEqualTo: riderId)
        .snapshots()
        .map((snapshot) {
      var total = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final raw = data['unreadForDriver'];
        final count = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? 0;
        total += count;
      }
      return total;
    });
  }

  static Stream<int> getCustomerUnreadCountStream(String riderId) {
    final controller = StreamController<int>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? inboxSub;
    final subsByOrder =
        <String, StreamSubscription<int>>{};
    final countsByOrder = <String, int>{};

    void emit() {
      var total = 0;
      for (final count in countsByOrder.values) {
        total += count;
      }
      controller.add(total);
    }

    Future<void> syncOrders(
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) async {
      final activeOrders = <String>{};
      for (final doc in snapshot.docs) {
        final orderId = (doc.data()['orderId'] ?? doc.id).toString();
        if (orderId.isEmpty) continue;
        activeOrders.add(orderId);
        if (subsByOrder.containsKey(orderId)) continue;
        final sub = ChatReadService.getUnreadCountStream(
          orderId: orderId,
          userId: riderId,
        ).listen((count) {
          countsByOrder[orderId] = count;
          emit();
        });
        subsByOrder[orderId] = sub;
      }

      final stale = subsByOrder.keys
          .where((orderId) => !activeOrders.contains(orderId))
          .toList();
      for (final orderId in stale) {
        await subsByOrder.remove(orderId)?.cancel();
        countsByOrder.remove(orderId);
      }
      emit();
    }

    inboxSub = _firestore
        .collection('chat_driver')
        .where('restaurantId', isEqualTo: riderId)
        .snapshots()
        .listen(syncOrders, onError: controller.addError);

    controller.onCancel = () async {
      await inboxSub?.cancel();
      for (final sub in subsByOrder.values) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  static Stream<int> watchRestaurantUnreadForOrder(
    String orderId,
    String riderId,
  ) {
    return _firestore
        .collection('order_communications')
        .doc(orderId)
        .collection('messages')
        .where('receiverId', isEqualTo: riderId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  static Stream<int> getRestaurantUnreadCountStream(String riderId) {
    final controller = StreamController<int>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? commSub;
    final subsByOrder =
        <String, StreamSubscription<int>>{};
    final countsByOrder = <String, int>{};

    void emit() {
      var total = 0;
      for (final count in countsByOrder.values) {
        total += count;
      }
      controller.add(total);
    }

    Future<void> syncOrders(
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) async {
      final activeOrders = <String>{};
      for (final doc in snapshot.docs) {
        final orderId = doc.id;
        if (orderId.isEmpty) continue;
        activeOrders.add(orderId);
        if (subsByOrder.containsKey(orderId)) continue;
        final sub = watchRestaurantUnreadForOrder(orderId, riderId).listen(
          (count) {
            countsByOrder[orderId] = count;
            emit();
          },
        );
        subsByOrder[orderId] = sub;
      }

      final stale = subsByOrder.keys
          .where((orderId) => !activeOrders.contains(orderId))
          .toList();
      for (final orderId in stale) {
        await subsByOrder.remove(orderId)?.cancel();
        countsByOrder.remove(orderId);
      }
      emit();
    }

    commSub = _firestore
        .collection('order_communications')
        .where('participants.riderId', isEqualTo: riderId)
        .snapshots()
        .listen(syncOrders, onError: controller.addError);

    controller.onCancel = () async {
      await commSub?.cancel();
      for (final sub in subsByOrder.values) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  static Stream<int> getCommunityUnreadCountStream() {
    return GroupChatService.getUnreadCountStream();
  }

  static Stream<int> getTotalUnreadCountStream(String riderId) {
    final controller = StreamController<int>.broadcast();
    StreamSubscription<int>? customerSub;
    StreamSubscription<int>? restaurantSub;
    StreamSubscription<int>? supportSub;
    StreamSubscription<int>? communitySub;

    var customer = 0;
    var restaurant = 0;
    var support = 0;
    var community = 0;

    void emit() {
      controller.add(customer + restaurant + support + community);
    }

    customerSub = getCustomerUnreadCountStream(riderId).listen((value) {
      customer = value;
      emit();
    }, onError: controller.addError);
    restaurantSub = getRestaurantUnreadCountStream(riderId).listen((value) {
      restaurant = value;
      emit();
    }, onError: controller.addError);
    supportSub = getSupportUnreadCountStream(riderId).listen((value) {
      support = value;
      emit();
    }, onError: controller.addError);
    communitySub = getCommunityUnreadCountStream().listen((value) {
      community = value;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await customerSub?.cancel();
      await restaurantSub?.cancel();
      await supportSub?.cancel();
      await communitySub?.cancel();
    };
    return controller.stream;
  }
}
