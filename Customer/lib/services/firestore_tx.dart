import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

typedef FirestoreTxHandler<T> = FutureOr<T> Function(Transaction transaction);

String _stackPreview() =>
    StackTrace.current.toString().split('\n').take(12).join('\n');

Future<T> runFirestoreTransaction<T>({
  required FirebaseFirestore firestore,
  required String txName,
  required String txParams,
  required FirestoreTxHandler<T> handler,
  int? maxAttempts,
}) async {
  final crashlytics = FirebaseCrashlytics.instance;
  final startedAtMs = DateTime.now().millisecondsSinceEpoch;

  crashlytics.setCustomKey('last_tx_name', txName);
  crashlytics.setCustomKey('last_tx_params', txParams);
  crashlytics.setCustomKey('last_tx_started_at_ms', startedAtMs);
  crashlytics.setCustomKey('last_tx_stack', _stackPreview());
  crashlytics.log('TX_START $txName $txParams');

  try {
    final result = await firestore.runTransaction<T>(
      (transaction) async => await handler(transaction),
      maxAttempts: maxAttempts ?? 5,
    );
    crashlytics.setCustomKey(
      'last_tx_ended_at_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
    crashlytics.setCustomKey('last_tx_success', true);
    crashlytics.log('TX_END $txName');
    return result;
  } catch (e) {
    crashlytics.setCustomKey(
      'last_tx_ended_at_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
    crashlytics.setCustomKey('last_tx_success', false);
    crashlytics.setCustomKey('last_tx_error', e.toString());
    crashlytics.log('TX_ERROR $txName $e');
    rethrow;
  }
}

