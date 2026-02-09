import 'package:cloud_firestore/cloud_firestore.dart';

class PendingReferralModel {
  String? id;
  String? referrerId; // User who provided the referral code
  String? refereeId; // User who used the referral code
  String? referralCode; // The referral code used
  Timestamp? createdAt;
  bool? isProcessed; // Whether the referral has been processed for rewards
  String? status; // 'pending', 'processed', 'invalid'

  PendingReferralModel({
    this.id,
    this.referrerId,
    this.refereeId,
    this.referralCode,
    this.createdAt,
    this.isProcessed = false,
    this.status = 'pending',
  });

  factory PendingReferralModel.fromJson(Map<String, dynamic> json) {
    return PendingReferralModel(
      id: json['id'],
      referrerId: json['referrerId'],
      refereeId: json['refereeId'],
      referralCode: json['referralCode'],
      createdAt: json['createdAt'],
      isProcessed: json['isProcessed'] ?? false,
      status: json['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'referrerId': this.referrerId,
      'refereeId': this.refereeId,
      'referralCode': this.referralCode,
      'createdAt': this.createdAt,
      'isProcessed': this.isProcessed,
      'status': this.status,
    };
  }
}
