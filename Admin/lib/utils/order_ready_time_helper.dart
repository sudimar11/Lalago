/// Pure helper for order ready-at time (Admin: "Ready at ~HH:MM").
/// Same parsing as Rider so both apps show consistent times.
class OrderReadyTimeHelper {
  OrderReadyTimeHelper._();

  static const int _minPrepMinutes = 5;
  static const int _maxPrepMinutes = 120;
  static const int _defaultPrepMinutes = 30;

  /// Parse "30 min", "0:30", "1:00", etc. Returns clamped 5–120; 30 for null/empty.
  static int parsePreparationMinutes(String? estimatedTimeToPrepare) {
    final raw = (estimatedTimeToPrepare ?? '').trim();
    if (raw.isEmpty) return _defaultPrepMinutes;

    // "X min" format (e.g. "30 min", "10 min")
    final minMatch = RegExp(r'(\d+)\s*min', caseSensitive: false).firstMatch(raw);
    if (minMatch != null) {
      final m = int.tryParse(minMatch.group(1) ?? '') ?? _defaultPrepMinutes;
      return m.clamp(_minPrepMinutes, _maxPrepMinutes);
    }

    // "H:MM" or "HH:MM" format (e.g. "0:30", "1:00")
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final hours = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final minutes = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final total = hours * 60 + minutes;
      if (total > 0) return total.clamp(_minPrepMinutes, _maxPrepMinutes);
    }

    // Single number (minutes)
    final single = RegExp(r'\d+').firstMatch(raw);
    if (single != null) {
      final m = int.tryParse(single.group(0) ?? '') ?? _defaultPrepMinutes;
      return m.clamp(_minPrepMinutes, _maxPrepMinutes);
    }

    return _defaultPrepMinutes;
  }

  /// readyAt = base time + prep minutes.
  static DateTime getReadyAt(DateTime baseTime, int prepMinutes) {
    return baseTime.add(Duration(minutes: prepMinutes));
  }
}
