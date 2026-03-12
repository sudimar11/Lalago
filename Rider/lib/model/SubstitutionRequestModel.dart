import 'package:cloud_firestore/cloud_firestore.dart';

class SubstitutionRequestModel {
  String id;
  String originalItem;
  int originalItemIndex;
  String proposedItem;
  double proposedPrice;
  String status; // pending | approved | rejected
  Timestamp createdAt;
  String createdBy;
  Timestamp? resolvedAt;
  String? resolvedBy;

  SubstitutionRequestModel({
    required this.id,
    required this.originalItem,
    required this.originalItemIndex,
    required this.proposedItem,
    required this.proposedPrice,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory SubstitutionRequestModel.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    return SubstitutionRequestModel(
      id: id,
      originalItem: json['originalItem']?.toString() ?? '',
      originalItemIndex: (json['originalItemIndex'] as num?)?.toInt() ?? 0,
      proposedItem: json['proposedItem']?.toString() ?? '',
      proposedPrice: (json['proposedPrice'] is num
              ? (json['proposedPrice'] as num).toDouble()
              : double.tryParse(json['proposedPrice']?.toString() ?? '0') ??
                  0.0),
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['createdAt'] is Timestamp
          ? json['createdAt'] as Timestamp
          : Timestamp.now(),
      createdBy: json['createdBy']?.toString() ?? '',
      resolvedAt: json['resolvedAt'] is Timestamp
          ? json['resolvedAt'] as Timestamp
          : null,
      resolvedBy: json['resolvedBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalItem': originalItem,
      'originalItemIndex': originalItemIndex,
      'proposedItem': proposedItem,
      'proposedPrice': proposedPrice,
      'status': status,
      'createdAt': createdAt,
      'createdBy': createdBy,
      if (resolvedAt != null) 'resolvedAt': resolvedAt,
      if (resolvedBy != null) 'resolvedBy': resolvedBy,
    };
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
