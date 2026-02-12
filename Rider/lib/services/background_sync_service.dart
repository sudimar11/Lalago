import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'offline_transaction_service.dart';

/// Background task for syncing pending orders
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔄 Background sync task started');
      
      final offlineService = OfflineTransactionService();
      await offlineService.initialize();
      await offlineService.processPendingTransactions();
      
      debugPrint('✅ Background sync task completed');
      return true;
    } catch (e) {
      debugPrint('❌ Background sync task failed: $e');
      return false;
    }
  });
}

class BackgroundSyncService {
  static const String _taskName = 'syncPendingOrders';
  static const String _uniqueName = 'pendingOrdersSync';

  /// Initialize background sync worker
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      
      // Register periodic task (runs every 15 minutes when connected)
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
      
      debugPrint('✅ Background sync service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize background sync: $e');
    }
  }

  /// Trigger immediate one-time sync
  static Future<void> triggerImmediateSync() async {
    try {
      await Workmanager().registerOneOffTask(
        'oneTimeSync',
        _taskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint('✅ Triggered immediate sync');
    } catch (e) {
      debugPrint('❌ Failed to trigger immediate sync: $e');
    }
  }

  /// Cancel all background tasks
  static Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      debugPrint('✅ Cancelled all background tasks');
    } catch (e) {
      debugPrint('❌ Failed to cancel tasks: $e');
    }
  }
}













