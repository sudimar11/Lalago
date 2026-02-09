import 'dart:math';

String newPendingTxId() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(0x7fffffff);
  return 'tx_${ms}_$rand';
}
