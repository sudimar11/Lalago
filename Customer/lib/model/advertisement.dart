import 'package:cloud_firestore/cloud_firestore.dart';

class Advertisement {
  String id;
  String title;
  String description;
  List<String> imageUrls;
  bool isEnabled;
  DateTime? startDate;
  DateTime? endDate;
  int priority;
  int impressions;
  int clicks;
  String? restaurantId;
  DateTime createdAt;
  DateTime updatedAt;
  bool isDeleted;

  Advertisement({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrls,
    this.isEnabled = true,
    this.startDate,
    this.endDate,
    this.priority = 0,
    this.impressions = 0,
    this.clicks = 0,
    this.restaurantId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Advertisement.fromJson(
      Map<String, dynamic> parsedJson, String docId) {
    List<String> imageUrlsList = [];
    if (parsedJson['image_urls'] != null) {
      if (parsedJson['image_urls'] is List) {
        imageUrlsList = (parsedJson['image_urls'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    DateTime? startDate;
    if (parsedJson['start_date'] != null) {
      if (parsedJson['start_date'] is Timestamp) {
        startDate = (parsedJson['start_date'] as Timestamp).toDate();
      } else if (parsedJson['start_date'] is Map) {
        try {
          startDate = Timestamp(
            parsedJson['start_date']['_seconds'] ?? 0,
            parsedJson['start_date']['_nanoseconds'] ?? 0,
          ).toDate();
        } catch (e) {
          startDate = null;
        }
      }
    }

    DateTime? endDate;
    if (parsedJson['end_date'] != null) {
      if (parsedJson['end_date'] is Timestamp) {
        endDate = (parsedJson['end_date'] as Timestamp).toDate();
      } else if (parsedJson['end_date'] is Map) {
        try {
          endDate = Timestamp(
            parsedJson['end_date']['_seconds'] ?? 0,
            parsedJson['end_date']['_nanoseconds'] ?? 0,
          ).toDate();
        } catch (e) {
          endDate = null;
        }
      }
    }

    DateTime createdAt;
    if (parsedJson['created_at'] != null) {
      if (parsedJson['created_at'] is Timestamp) {
        createdAt = (parsedJson['created_at'] as Timestamp).toDate();
      } else if (parsedJson['created_at'] is Map) {
        createdAt = Timestamp(
          parsedJson['created_at']['_seconds'] ?? 0,
          parsedJson['created_at']['_nanoseconds'] ?? 0,
        ).toDate();
      } else {
        createdAt = DateTime.now();
      }
    } else {
      createdAt = DateTime.now();
    }

    DateTime updatedAt;
    if (parsedJson['updated_at'] != null) {
      if (parsedJson['updated_at'] is Timestamp) {
        updatedAt = (parsedJson['updated_at'] as Timestamp).toDate();
      } else if (parsedJson['updated_at'] is Map) {
        updatedAt = Timestamp(
          parsedJson['updated_at']['_seconds'] ?? 0,
          parsedJson['updated_at']['_nanoseconds'] ?? 0,
        ).toDate();
      } else {
        updatedAt = DateTime.now();
      }
    } else {
      updatedAt = DateTime.now();
    }

    return Advertisement(
      id: docId,
      title: parsedJson['title'] ?? '',
      description: parsedJson['description'] ?? '',
      imageUrls: imageUrlsList,
      isEnabled: parsedJson['is_enabled'] ?? true,
      startDate: startDate,
      endDate: endDate,
      priority: parsedJson['priority'] ?? 0,
      impressions: parsedJson['impressions'] ?? 0,
      clicks: parsedJson['clicks'] ?? 0,
      restaurantId: parsedJson['restaurant_id'],
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: parsedJson['is_deleted'] ?? false,
    );
  }

  bool get isScheduled {
    if (startDate == null && endDate == null) return false;
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return true;
    if (endDate != null && now.isAfter(endDate!)) return true;
    return false;
  }

  bool get isExpired {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate!);
  }

  bool get isActive {
    if (!isEnabled || isDeleted) return false;
    if (isExpired) return false;
    if (startDate != null && DateTime.now().isBefore(startDate!)) {
      return false;
    }
    return true;
  }
}

