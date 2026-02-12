class TransactionEntry {
  final String date;
  final String type;
  final double amount;
  final String description;
  final String? riderId;
  final String txId;

  TransactionEntry({
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    required this.txId,
    this.riderId,
  });

  Map<String, dynamic> toMap() => {
        'date': date,
        'type': type,
        'amount': amount,
        'description': description,
        'riderId': riderId,
        'txId': txId,
      };

  static TransactionEntry fromMap(Map<String, dynamic> m) => TransactionEntry(
        date: (m['date'] ?? '').toString(),
        type: (m['type'] ?? '').toString(),
        amount: (m['amount'] ?? 0).toDouble(),
        description: (m['description'] ?? '').toString(),
        riderId: m['riderId']?.toString(),
        txId: (m['txId'] ?? '').toString(),
      );
}
