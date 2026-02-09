import 'package:cloud_firestore/cloud_firestore.dart';

enum DriverReportStatus {
  pending,
  under_review,
  resolved,
  dismissed;

  String get value {
    switch (this) {
      case DriverReportStatus.pending:
        return 'pending';
      case DriverReportStatus.under_review:
        return 'under_review';
      case DriverReportStatus.resolved:
        return 'resolved';
      case DriverReportStatus.dismissed:
        return 'dismissed';
    }
  }

  static DriverReportStatus fromString(String status) {
    switch (status) {
      case 'pending':
        return DriverReportStatus.pending;
      case 'under_review':
        return DriverReportStatus.under_review;
      case 'resolved':
        return DriverReportStatus.resolved;
      case 'dismissed':
        return DriverReportStatus.dismissed;
      default:
        return DriverReportStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case DriverReportStatus.pending:
        return 'Pending';
      case DriverReportStatus.under_review:
        return 'Under Review';
      case DriverReportStatus.resolved:
        return 'Resolved';
      case DriverReportStatus.dismissed:
        return 'Dismissed';
    }
  }
}

class AdminNote {
  final String note;
  final String adminId;
  final String adminName;
  final Timestamp createdAt;

  AdminNote({
    required this.note,
    required this.adminId,
    required this.adminName,
    required this.createdAt,
  });

  factory AdminNote.fromJson(Map<String, dynamic> json) {
    return AdminNote(
      note: json['note'] ?? '',
      adminId: json['adminId'] ?? '',
      adminName: json['adminName'] ?? '',
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'note': note,
      'adminId': adminId,
      'adminName': adminName,
      'createdAt': createdAt,
    };
  }
}

class DriverReport {
  final String id;
  final String orderId;
  final String driverId;
  final String userId;
  final String complaint;
  final Timestamp createdAt;
  final DriverReportStatus status;
  final List<AdminNote> adminNotes;
  final String? category;
  final Timestamp? updatedAt;
  final String? updatedBy;

  DriverReport({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.userId,
    required this.complaint,
    required this.createdAt,
    this.status = DriverReportStatus.pending,
    this.adminNotes = const [],
    this.category,
    this.updatedAt,
    this.updatedBy,
  });

  factory DriverReport.fromJson(Map<String, dynamic> json, String docId) {
    // Parse status
    final statusString = json['status'] ?? 'pending';
    final status = DriverReportStatus.fromString(statusString);

    // Parse admin notes
    List<AdminNote> notes = [];
    if (json['adminNotes'] != null) {
      if (json['adminNotes'] is List) {
        notes = (json['adminNotes'] as List)
            .map((note) => AdminNote.fromJson(note as Map<String, dynamic>))
            .toList();
      }
    }

    return DriverReport(
      id: docId,
      orderId: json['orderId'] ?? '',
      driverId: json['driverId'] ?? '',
      userId: json['userId'] ?? '',
      complaint: json['complaint'] ?? '',
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      status: status,
      adminNotes: notes,
      category: json['category'],
      updatedAt: json['updatedAt'] as Timestamp?,
      updatedBy: json['updatedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'driverId': driverId,
      'userId': userId,
      'complaint': complaint,
      'createdAt': createdAt,
      'type': 'driver_report',
      'status': status.value,
      'adminNotes': adminNotes.map((note) => note.toJson()).toList(),
      if (category != null) 'category': category,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }

  DriverReport copyWith({
    String? id,
    String? orderId,
    String? driverId,
    String? userId,
    String? complaint,
    Timestamp? createdAt,
    DriverReportStatus? status,
    List<AdminNote>? adminNotes,
    String? category,
    Timestamp? updatedAt,
    String? updatedBy,
  }) {
    return DriverReport(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      driverId: driverId ?? this.driverId,
      userId: userId ?? this.userId,
      complaint: complaint ?? this.complaint,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      adminNotes: adminNotes ?? this.adminNotes,
      category: category ?? this.category,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

