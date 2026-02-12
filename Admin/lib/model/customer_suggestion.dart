import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/driver_report.dart';

enum SuggestionStatus {
  new_,
  under_review,
  acknowledged,
  archived;

  String get value {
    switch (this) {
      case SuggestionStatus.new_:
        return 'new';
      case SuggestionStatus.under_review:
        return 'under_review';
      case SuggestionStatus.acknowledged:
        return 'acknowledged';
      case SuggestionStatus.archived:
        return 'archived';
    }
  }

  static SuggestionStatus fromString(String status) {
    switch (status) {
      case 'new':
        return SuggestionStatus.new_;
      case 'under_review':
        return SuggestionStatus.under_review;
      case 'acknowledged':
        return SuggestionStatus.acknowledged;
      case 'archived':
        return SuggestionStatus.archived;
      default:
        return SuggestionStatus.new_;
    }
  }

  String get displayName {
    switch (this) {
      case SuggestionStatus.new_:
        return 'New';
      case SuggestionStatus.under_review:
        return 'Under Review';
      case SuggestionStatus.acknowledged:
        return 'Acknowledged';
      case SuggestionStatus.archived:
        return 'Archived';
    }
  }
}

class CustomerSuggestion {
  final String id;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String suggestion;
  final String? category;
  final SuggestionStatus status;
  final Timestamp createdAt;
  final Timestamp? updatedAt;
  final String? reviewedBy;
  final String? reviewedByName;
  final List<AdminNote> adminNotes;
  final String? priority;

  CustomerSuggestion({
    required this.id,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    required this.suggestion,
    this.category,
    this.status = SuggestionStatus.new_,
    required this.createdAt,
    this.updatedAt,
    this.reviewedBy,
    this.reviewedByName,
    this.adminNotes = const [],
    this.priority,
  });

  factory CustomerSuggestion.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    // Parse status
    final statusString = json['status'] ?? 'new';
    final status = SuggestionStatus.fromString(statusString);

    // Parse admin notes
    List<AdminNote> notes = [];
    if (json['adminNotes'] != null) {
      if (json['adminNotes'] is List) {
        notes = (json['adminNotes'] as List)
            .map((note) => AdminNote.fromJson(note as Map<String, dynamic>))
            .toList();
      }
    }

    // Map userId to customerId (actual data structure uses userId)
    final userId = json['userId'] ?? json['customerId'] ?? '';
    
    return CustomerSuggestion(
      id: docId,
      customerId: userId,
      customerName: json['customerName'] ?? '',
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      suggestion: json['suggestion'] ?? '',
      category: json['category'],
      status: status,
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updatedAt'] as Timestamp?,
      reviewedBy: json['reviewedBy'],
      reviewedByName: json['reviewedByName'],
      adminNotes: notes,
      priority: json['priority'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      if (customerEmail != null) 'customerEmail': customerEmail,
      if (customerPhone != null) 'customerPhone': customerPhone,
      'suggestion': suggestion,
      if (category != null) 'category': category,
      'status': status.value,
      'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
      if (reviewedByName != null) 'reviewedByName': reviewedByName,
      'adminNotes': adminNotes.map((note) => note.toJson()).toList(),
      if (priority != null) 'priority': priority,
    };
  }

  CustomerSuggestion copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? suggestion,
    String? category,
    SuggestionStatus? status,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    String? reviewedBy,
    String? reviewedByName,
    List<AdminNote>? adminNotes,
    String? priority,
  }) {
    return CustomerSuggestion(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      suggestion: suggestion ?? this.suggestion,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      adminNotes: adminNotes ?? this.adminNotes,
      priority: priority ?? this.priority,
    );
  }
}

