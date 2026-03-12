import 'package:cloud_firestore/cloud_firestore.dart';

class LoyaltyRewardClaimed {
  final String rewardId;
  final Timestamp claimedAt;
  final String cycle;
  final Timestamp? expiresAt;
  final String? orderId;

  LoyaltyRewardClaimed({
    required this.rewardId,
    required this.claimedAt,
    required this.cycle,
    this.expiresAt,
    this.orderId,
  });

  factory LoyaltyRewardClaimed.fromJson(Map<String, dynamic> json) {
    Timestamp? claimedAt;
    if (json['claimedAt'] != null) {
      final t = json['claimedAt'];
      if (t is Timestamp) {
        claimedAt = t;
      } else if (t is Map) {
        claimedAt = Timestamp(
          (t['_seconds'] ?? 0) as int,
          (t['_nanoseconds'] ?? 0) as int,
        );
      }
    }

    Timestamp? expiresAt;
    if (json['expiresAt'] != null) {
      final t = json['expiresAt'];
      if (t is Timestamp) {
        expiresAt = t;
      } else if (t is Map) {
        expiresAt = Timestamp(
          (t['_seconds'] ?? 0) as int,
          (t['_nanoseconds'] ?? 0) as int,
        );
      }
    }

    return LoyaltyRewardClaimed(
      rewardId: (json['rewardId'] ?? '').toString(),
      claimedAt: claimedAt ?? Timestamp.now(),
      cycle: (json['cycle'] ?? '').toString(),
      expiresAt: expiresAt,
      orderId: json['orderId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rewardId': rewardId,
      'claimedAt': claimedAt,
      'cycle': cycle,
      if (expiresAt != null) 'expiresAt': expiresAt,
      if (orderId != null) 'orderId': orderId,
    };
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!.toDate());
  }

  bool get isUsed => orderId != null && orderId!.isNotEmpty;
}

class LoyaltyTierHistory {
  final String tier;
  final Timestamp achievedAt;
  final String cycle;

  LoyaltyTierHistory({
    required this.tier,
    required this.achievedAt,
    required this.cycle,
  });

  factory LoyaltyTierHistory.fromJson(Map<String, dynamic> json) {
    Timestamp achievedAt;
    if (json['achievedAt'] != null) {
      final t = json['achievedAt'];
      if (t is Timestamp) {
        achievedAt = t;
      } else if (t is Map) {
        achievedAt = Timestamp(
          (t['_seconds'] ?? 0) as int,
          (t['_nanoseconds'] ?? 0) as int,
        );
      } else {
        achievedAt = Timestamp.now();
      }
    } else {
      achievedAt = Timestamp.now();
    }

    return LoyaltyTierHistory(
      tier: (json['tier'] ?? 'bronze').toString(),
      achievedAt: achievedAt,
      cycle: (json['cycle'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tier': tier,
      'achievedAt': achievedAt,
      'cycle': cycle,
    };
  }
}

class LoyaltyData {
  final String currentCycle;
  final Timestamp? cycleStartDate;
  final Timestamp? cycleEndDate;
  final int tokensThisCycle;
  final String currentTier;
  final String? previousCycle;
  final String? previousTier;
  final int? previousTokens;
  final int lifetimeTokens;
  final List<LoyaltyRewardClaimed> rewardsClaimed;
  final List<LoyaltyTierHistory> tierHistory;

  LoyaltyData({
    required this.currentCycle,
    this.cycleStartDate,
    this.cycleEndDate,
    this.tokensThisCycle = 0,
    this.currentTier = 'bronze',
    this.previousCycle,
    this.previousTier,
    this.previousTokens,
    this.lifetimeTokens = 0,
    this.rewardsClaimed = const [],
    this.tierHistory = const [],
  });

  factory LoyaltyData.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return LoyaltyData(currentCycle: '');
    }

    Timestamp? cycleStartDate;
    if (json['cycleStartDate'] != null) {
      final t = json['cycleStartDate'];
      if (t is Timestamp) {
        cycleStartDate = t;
      } else if (t is Map) {
        cycleStartDate = Timestamp(
          (t['_seconds'] ?? 0) as int,
          (t['_nanoseconds'] ?? 0) as int,
        );
      }
    }

    Timestamp? cycleEndDate;
    if (json['cycleEndDate'] != null) {
      final t = json['cycleEndDate'];
      if (t is Timestamp) {
        cycleEndDate = t;
      } else if (t is Map) {
        cycleEndDate = Timestamp(
          (t['_seconds'] ?? 0) as int,
          (t['_nanoseconds'] ?? 0) as int,
        );
      }
    }

    List<LoyaltyRewardClaimed> rewardsList = [];
    if (json['rewardsClaimed'] is List) {
      for (final item in json['rewardsClaimed'] as List) {
        if (item is Map<String, dynamic>) {
          rewardsList.add(LoyaltyRewardClaimed.fromJson(item));
        }
      }
    }

    List<LoyaltyTierHistory> historyList = [];
    if (json['tierHistory'] is List) {
      for (final item in json['tierHistory'] as List) {
        if (item is Map<String, dynamic>) {
          historyList.add(LoyaltyTierHistory.fromJson(item));
        }
      }
    }

    return LoyaltyData(
      currentCycle: (json['currentCycle'] ?? '').toString(),
      cycleStartDate: cycleStartDate,
      cycleEndDate: cycleEndDate,
      tokensThisCycle: (json['tokensThisCycle'] is num)
          ? (json['tokensThisCycle'] as num).toInt()
          : int.tryParse(json['tokensThisCycle']?.toString() ?? '0') ?? 0,
      currentTier: (json['currentTier'] ?? 'bronze').toString(),
      previousCycle: json['previousCycle']?.toString(),
      previousTier: json['previousTier']?.toString(),
      previousTokens: json['previousTokens'] != null
          ? ((json['previousTokens'] is num)
              ? (json['previousTokens'] as num).toInt()
              : int.tryParse(json['previousTokens'].toString()))
          : null,
      lifetimeTokens: (json['lifetimeTokens'] is num)
          ? (json['lifetimeTokens'] as num).toInt()
          : int.tryParse(json['lifetimeTokens']?.toString() ?? '0') ?? 0,
      rewardsClaimed: rewardsList,
      tierHistory: historyList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentCycle': currentCycle,
      if (cycleStartDate != null) 'cycleStartDate': cycleStartDate,
      if (cycleEndDate != null) 'cycleEndDate': cycleEndDate,
      'tokensThisCycle': tokensThisCycle,
      'currentTier': currentTier,
      if (previousCycle != null) 'previousCycle': previousCycle,
      if (previousTier != null) 'previousTier': previousTier,
      if (previousTokens != null) 'previousTokens': previousTokens,
      'lifetimeTokens': lifetimeTokens,
      'rewardsClaimed': rewardsClaimed.map((r) => r.toJson()).toList(),
      'tierHistory': tierHistory.map((h) => h.toJson()).toList(),
    };
  }
}
