import 'package:cloud_firestore/cloud_firestore.dart';

class HappyHourConfig {
  String id;
  String name;
  String startTime; // HH:MM format
  String endTime; // HH:MM format
  List<int> activeDays; // 0=Sunday, 1=Monday, ..., 6=Saturday
  String promoType; // "fixed_amount" | "percentage" | "free_delivery" | "reduced_delivery"
  double promoValue;
  double minOrderAmount;
  String restaurantScope; // "all" | "selected"
  List<String> restaurantIds;
  String userEligibility; // "all" | "new" | "returning"
  int? maxUsagePerUserPerDay;
  int? minItems; // Minimum number of items required
  Timestamp createdAt;
  Timestamp updatedAt;

  HappyHourConfig({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.activeDays,
    required this.promoType,
    required this.promoValue,
    required this.minOrderAmount,
    required this.restaurantScope,
    required this.restaurantIds,
    required this.userEligibility,
    this.maxUsagePerUserPerDay,
    this.minItems,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  })  : createdAt = createdAt ?? Timestamp.now(),
        updatedAt = updatedAt ?? Timestamp.now();

  factory HappyHourConfig.fromJson(Map<String, dynamic> json, String docId) {
    List<int> activeDaysList = [];
    if (json['activeDays'] != null) {
      if (json['activeDays'] is List) {
        activeDaysList = (json['activeDays'] as List)
            .map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0)
            .toList();
      }
    }

    List<String> restaurantIdsList = [];
    if (json['restaurantIds'] != null) {
      if (json['restaurantIds'] is List) {
        restaurantIdsList = (json['restaurantIds'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    Timestamp createdAt;
    if (json['createdAt'] != null) {
      if (json['createdAt'] is Timestamp) {
        createdAt = json['createdAt'] as Timestamp;
      } else if (json['createdAt'] is Map) {
        createdAt = Timestamp(
          json['createdAt']['_seconds'] ?? 0,
          json['createdAt']['_nanoseconds'] ?? 0,
        );
      } else {
        createdAt = Timestamp.now();
      }
    } else {
      createdAt = Timestamp.now();
    }

    Timestamp updatedAt;
    if (json['updatedAt'] != null) {
      if (json['updatedAt'] is Timestamp) {
        updatedAt = json['updatedAt'] as Timestamp;
      } else if (json['updatedAt'] is Map) {
        updatedAt = Timestamp(
          json['updatedAt']['_seconds'] ?? 0,
          json['updatedAt']['_nanoseconds'] ?? 0,
        );
      } else {
        updatedAt = Timestamp.now();
      }
    } else {
      updatedAt = Timestamp.now();
    }

    return HappyHourConfig(
      id: docId,
      name: json['name'] ?? '',
      startTime: json['startTime'] ?? '00:00',
      endTime: json['endTime'] ?? '23:59',
      activeDays: activeDaysList,
      promoType: json['promoType'] ?? 'fixed_amount',
      promoValue: (json['promoValue'] is num)
          ? (json['promoValue'] as num).toDouble()
          : double.tryParse(json['promoValue']?.toString() ?? '0') ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] is num)
          ? (json['minOrderAmount'] as num).toDouble()
          : double.tryParse(json['minOrderAmount']?.toString() ?? '0') ?? 0.0,
      restaurantScope: json['restaurantScope'] ?? 'all',
      restaurantIds: restaurantIdsList,
      userEligibility: json['userEligibility'] ?? 'all',
      maxUsagePerUserPerDay: json['maxUsagePerUserPerDay'] != null
          ? (json['maxUsagePerUserPerDay'] is int
              ? json['maxUsagePerUserPerDay'] as int
              : int.tryParse(json['maxUsagePerUserPerDay'].toString()))
          : null,
      minItems: json['minItems'] != null
          ? (json['minItems'] is int
              ? json['minItems'] as int
              : int.tryParse(json['minItems'].toString()))
          : null,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'activeDays': activeDays,
      'promoType': promoType,
      'promoValue': promoValue,
      'minOrderAmount': minOrderAmount,
      'restaurantScope': restaurantScope,
      'restaurantIds': restaurantIds,
      'userEligibility': userEligibility,
      'maxUsagePerUserPerDay': maxUsagePerUserPerDay,
      'minItems': minItems,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  // Validation methods
  bool isValid() {
    if (name.isEmpty) return false;
    if (startTime.isEmpty || endTime.isEmpty) return false;
    if (activeDays.isEmpty) return false;
    if (promoValue <= 0) return false;
    if (minOrderAmount < 0) return false;
    if (restaurantScope == 'selected' && restaurantIds.isEmpty) return false;
    
    // Validate time format and range
    if (!_isValidTimeFormat(startTime) || !_isValidTimeFormat(endTime)) {
      return false;
    }
    
    if (!_isEndTimeAfterStartTime(startTime, endTime)) {
      return false;
    }
    
    // Validate promo type
    if (!['fixed_amount', 'percentage', 'free_delivery', 'reduced_delivery']
        .contains(promoType)) {
      return false;
    }
    
    // Validate percentage (0-100)
    if (promoType == 'percentage' && (promoValue < 0 || promoValue > 100)) {
      return false;
    }
    
    // Validate user eligibility
    if (!['all', 'new', 'returning'].contains(userEligibility)) {
      return false;
    }
    
    // Validate minItems if provided (must be positive integer >= 1)
    if (minItems != null && minItems! < 1) {
      return false;
    }
    
    return true;
  }

  bool _isValidTimeFormat(String time) {
    final regex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
    return regex.hasMatch(time);
  }

  bool _isEndTimeAfterStartTime(String start, String end) {
    try {
      final startParts = start.split(':');
      final endParts = end.split(':');
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return endMinutes > startMinutes;
    } catch (e) {
      return false;
    }
  }

  String get promoTypeDisplay {
    switch (promoType) {
      case 'fixed_amount':
        return 'Fixed Amount';
      case 'percentage':
        return 'Percentage';
      case 'free_delivery':
        return 'Free Delivery';
      case 'reduced_delivery':
        return 'Reduced Delivery';
      default:
        return promoType;
    }
  }

  String get userEligibilityDisplay {
    switch (userEligibility) {
      case 'all':
        return 'All Users';
      case 'new':
        return 'New Users Only';
      case 'returning':
        return 'Returning Users Only';
      default:
        return userEligibility;
    }
  }

  String get activeDaysDisplay {
    if (activeDays.isEmpty) return 'No days selected';
    final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    if (activeDays.length == 7) return 'Every day';
    return activeDays.map((d) => dayNames[d]).join(', ');
  }
}

class HappyHourSettings {
  bool enabled;
  List<HappyHourConfig> configs;

  HappyHourSettings({
    this.enabled = false,
    this.configs = const [],
  });

  factory HappyHourSettings.fromJson(Map<String, dynamic> json) {
    List<HappyHourConfig> configsList = [];
    if (json['configs'] != null && json['configs'] is List) {
      final configsJson = json['configs'] as List;
      configsList = configsJson.asMap().entries.map((entry) {
        final configJson = entry.value as Map<String, dynamic>;
        final configId = configJson['id']?.toString() ?? entry.key.toString();
        return HappyHourConfig.fromJson(configJson, configId);
      }).toList();
    }

    return HappyHourSettings(
      enabled: json['enabled'] ?? false,
      configs: configsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'configs': configs.map((config) => config.toJson()).toList(),
    };
  }

  factory HappyHourSettings.empty() {
    return HappyHourSettings(
      enabled: false,
      configs: [],
    );
  }
}

