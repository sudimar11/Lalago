class FinancialTransaction {
  final int? id;
  final String date; // YYYY-MM-DD format
  final String type; // 'wallet_topup', 'other_income', 'credit_sale', 'expense'
  final double amount;
  final String description;
  final DateTime createdAt;

  FinancialTransaction({
    this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'type': type,
      'amount': amount,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory FinancialTransaction.fromMap(Map<String, dynamic> map) {
    return FinancialTransaction(
      id: map['id'],
      date: map['date'],
      type: map['type'],
      amount: map['amount'].toDouble(),
      description: map['description'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class DailySummary {
  final String date;
  final double openingBalance;
  final double walletTopups;
  final double otherIncome;
  final double totalExpenses;
  final double netBalance;
  final double closingBalance;

  DailySummary({
    required this.date,
    required this.openingBalance,
    required this.walletTopups,
    required this.otherIncome,
    required this.totalExpenses,
    required this.netBalance,
    required this.closingBalance,
  });
}
