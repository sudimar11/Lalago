import 'package:cloud_firestore/cloud_firestore.dart';

class ReferralWalletTransaction {
  String? id;
  String userId;
  String type; // 'credit' or 'debit'
  double amount;
  String? orderId; // Order ID if transaction is related to an order
  String? referralId; // Referral ID if transaction is related to a referral reward
  String description;
  Timestamp createdAt;

  ReferralWalletTransaction({
    this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.orderId,
    this.referralId,
    required this.description,
    required this.createdAt,
  });

  factory ReferralWalletTransaction.fromJson(Map<String, dynamic> json) {
    return ReferralWalletTransaction(
      id: json['id'],
      userId: json['userId'] ?? '',
      type: json['type'] ?? '',
      amount: json['amount'] != null
          ? (json['amount'] is num
              ? (json['amount'] as num).toDouble()
              : double.tryParse(json['amount'].toString()) ?? 0.0)
          : 0.0,
      orderId: json['orderId'],
      referralId: json['referralId'],
      description: json['description'] ?? '',
      createdAt: json['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'userId': this.userId,
      'type': this.type,
      'amount': this.amount,
      'orderId': this.orderId,
      'referralId': this.referralId,
      'description': this.description,
      'createdAt': this.createdAt,
    };
  }
}

