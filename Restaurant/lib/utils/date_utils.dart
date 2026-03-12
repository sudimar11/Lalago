/// Date range utilities for Insights analytics.
class DateUtils {
  static DateTime startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime endOfToday() {
    return startOfToday().add(const Duration(days: 1));
  }

  static DateTime startOfThisWeek() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final daysFromMonday = weekday - 1;
    return DateTime(now.year, now.month, now.day - daysFromMonday);
  }

  static DateTime endOfThisWeek() {
    return startOfThisWeek().add(const Duration(days: 7));
  }

  static DateTime startOfThisMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static DateTime endOfThisMonth() {
    final now = DateTime.now();
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    final nextYear = now.month == 12 ? now.year + 1 : now.year;
    return DateTime(nextYear, nextMonth, 1);
  }

  static (DateTime, DateTime) getTodayRange() =>
      (startOfToday(), endOfToday());
  static (DateTime, DateTime) getThisWeekRange() =>
      (startOfThisWeek(), endOfThisWeek());
  static (DateTime, DateTime) getThisMonthRange() =>
      (startOfThisMonth(), endOfThisMonth());
}
