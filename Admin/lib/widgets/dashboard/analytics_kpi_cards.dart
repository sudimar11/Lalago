import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/active_buyers_today_page.dart';
import 'package:brgy/active_buyers_this_week_page.dart';
import 'package:brgy/orders_this_week_page.dart';
import 'package:brgy/foods_page.dart';
import 'package:brgy/restaurants_page.dart';
import 'package:brgy/riders_orders_today_page.dart';
import 'package:brgy/inactive_customers_page.dart';
import 'package:brgy/active_customers_page.dart';
import 'package:brgy/customers_page.dart';

/// Shared date helpers for analytics KPIs.
Map<String, DateTime> analyticsGetWeekDateRange() {
  final now = DateTime.now();
  final weekday = now.weekday;
  final daysToMonday = weekday - 1;
  final mondayDate = now.subtract(Duration(days: daysToMonday));
  final String mondayDateStr = mondayDate.toIso8601String().split('T')[0];
  final DateTime startOfWeek =
      DateTime.parse('$mondayDateStr 00:00:00Z').toUtc();
  DateTime endOfWeek;
  if (weekday == 1) {
    endOfWeek = now.toUtc();
  } else {
    final daysToSunday = 7 - weekday;
    final sundayDate = now.add(Duration(days: daysToSunday));
    final String sundayDateStr =
        sundayDate.toIso8601String().split('T')[0];
    endOfWeek = DateTime.parse('$sundayDateStr 23:59:59Z').toUtc();
  }
  return {'start': startOfWeek, 'end': endOfWeek};
}

Map<String, DateTime> analyticsGetTodayUtcRange() {
  final String todayDate = DateTime.now().toIso8601String().split('T')[0];
  final DateTime startOfDay =
      DateTime.parse('$todayDate 00:00:00Z').toUtc();
  final DateTime endOfDay =
      DateTime.parse('$todayDate 23:59:59Z').toUtc();
  return {'start': startOfDay, 'end': endOfDay};
}

bool analyticsIsFoodPublished(Map<String, dynamic> data) {
  const keys = [
    'isPublished', 'published', 'publish',
    'is_public', 'isVisible', 'visible',
  ];
  for (final key in keys) {
    if (!data.containsKey(key)) continue;
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
  }
  return false;
}

/// Builder-style widget - parent provides KpiCard builder since it's private.
class NewCustomersTodayKpi extends StatelessWidget {
  const NewCustomersTodayKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.person_add,
            label: 'New customers today',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        int count = 0;
        final now = DateTime.now();
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data == null) continue;
            final ts = data['createdAt'] ?? data['created_at'];
            if (ts == null || ts is! Timestamp) continue;
            final dt = ts.toDate().toLocal();
            if (dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day) {
              count++;
            }
          }
        }
        return buildCard(
          icon: Icons.person_add,
          label: 'New customers today',
          value: '${snap.hasError ? '-' : count}',
          helper: 'Today',
          onTap: () => onNavigate(const CustomersPage()),
          isLoading: false,
        );
      },
    );
  }
}

class BuyersTodayKpi extends StatelessWidget {
  const BuyersTodayKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final range = analyticsGetTodayUtcRange();
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range['start']!))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range['end']!))
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.shopping_bag,
            label: 'Buyers today',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final orders = snap.data?.docs ?? [];
        final unique = <String>{};
        for (final doc in orders) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final author = data['author'] as Map<String, dynamic>?;
            if (author == null) continue;
            final id = author['id'] as String?;
            if (id != null && id.isNotEmpty) unique.add(id);
          } catch (_) {}
        }
        return buildCard(
          icon: Icons.shopping_bag,
          label: 'Buyers today',
          value: '${snap.hasError ? '-' : unique.length}',
          helper: 'Unique',
          onTap: () => onNavigate(const ActiveBuyersTodayPage()),
          isLoading: false,
        );
      },
    );
  }
}

class OrdersThisWeekKpi extends StatelessWidget {
  const OrdersThisWeekKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final range = analyticsGetWeekDateRange();
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range['start']!))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range['end']!))
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.calendar_view_week,
            label: 'Orders this week',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.calendar_view_week,
          label: 'Orders this week',
          value: '${snap.hasError ? '-' : n}',
          helper: 'Week',
          onTap: () => onNavigate(const OrdersThisWeekPage()),
          isLoading: false,
        );
      },
    );
  }
}

class BuyersThisWeekKpi extends StatelessWidget {
  const BuyersThisWeekKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final range = analyticsGetWeekDateRange();
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range['start']!))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range['end']!))
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.people,
            label: 'Buyers this week',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final orders = snap.data?.docs ?? [];
        final unique = <String>{};
        for (final doc in orders) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final author = data['author'] as Map<String, dynamic>?;
            if (author == null) continue;
            final id = author['id'] as String?;
            if (id != null && id.isNotEmpty) unique.add(id);
          } catch (_) {}
        }
        return buildCard(
          icon: Icons.people,
          label: 'Buyers this week',
          value: '${snap.hasError ? '-' : unique.length}',
          helper: 'Unique',
          onTap: () => onNavigate(const ActiveBuyersThisWeekPage()),
          isLoading: false,
        );
      },
    );
  }
}

class TotalFoodsKpi extends StatelessWidget {
  const TotalFoodsKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('vendor_products').get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.fastfood,
            label: 'Total foods',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.fastfood,
          label: 'Total foods',
          value: '${snap.hasError ? '-' : n}',
          helper: 'Menu items',
          onTap: () => onNavigate(const FoodsPage()),
          isLoading: false,
        );
      },
    );
  }
}

class UnpublishedFoodsKpi extends StatelessWidget {
  const UnpublishedFoodsKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('vendor_products').get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.visibility_off,
            label: 'Unpublished foods',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        int count = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null && !analyticsIsFoodPublished(data)) count++;
          }
        }
        return buildCard(
          icon: Icons.visibility_off,
          label: 'Unpublished foods',
          value: '${snap.hasError ? '-' : count}',
          helper: 'Need publish',
          onTap: () => onNavigate(const FoodsPage(filterUnpublished: true)),
          isLoading: false,
        );
      },
    );
  }
}

class FoodsAddedTodayKpi extends StatelessWidget {
  const FoodsAddedTodayKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final range = analyticsGetTodayUtcRange();
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('vendor_products')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range['start']!))
          .where('createdAt',
              isLessThanOrEqualTo: Timestamp.fromDate(range['end']!))
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.add_circle,
            label: 'Foods added today',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.add_circle,
          label: 'Foods added today',
          value: '${snap.hasError ? '-' : n}',
          helper: 'Today',
          onTap: () => onNavigate(const FoodsPage()),
          isLoading: false,
        );
      },
    );
  }
}

class TotalRestaurantsKpi extends StatelessWidget {
  const TotalRestaurantsKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('vendors').get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.restaurant,
            label: 'Total restaurants',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.restaurant,
          label: 'Total restaurants',
          value: '${snap.hasError ? '-' : n}',
          helper: 'Vendors',
          onTap: () => onNavigate(const RestaurantsPage()),
          isLoading: false,
        );
      },
    );
  }
}

class TotalRidersKpi extends StatelessWidget {
  const TotalRidersKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.delivery_dining,
            label: 'Total riders',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.delivery_dining,
          label: 'Total riders',
          value: '${snap.hasError ? '-' : n}',
          helper: 'Drivers',
          onTap: () => onNavigate(const RidersOrdersTodayPage()),
          isLoading: false,
        );
      },
    );
  }
}

class InactiveCustomersKpi extends StatelessWidget {
  const InactiveCustomersKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start30 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance
            .collection(USERS)
            .where('role', isEqualTo: USER_ROLE_CUSTOMER)
            .get(),
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start30))
            .where('createdAt',
                isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get(),
      ]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.person_off,
            label: 'Inactive customers',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        int inactive = 0;
        if (snap.hasData) {
          final customers = snap.data![0].docs;
          final orders = snap.data![1].docs;
          final allIds = <String>{};
          final activeIds = <String>{};
          for (final d in customers) {
            if (d.id.isNotEmpty) allIds.add(d.id);
          }
          for (final d in orders) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) continue;
            final author = data['author'];
            if (author is Map<String, dynamic>) {
              final id = author['id'] as String?;
              if (id != null && id.isNotEmpty) activeIds.add(id);
            }
          }
          inactive = allIds.length - activeIds.length;
        }
        return buildCard(
          icon: Icons.person_off,
          label: 'Inactive customers',
          value: '${snap.hasError ? '-' : inactive}',
          helper: 'Last 30d',
          onTap: () => onNavigate(const InactiveCustomersPage()),
          isLoading: false,
        );
      },
    );
  }
}

class ActiveCustomersKpi extends StatelessWidget {
  const ActiveCustomersKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start30 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start30))
            .where('createdAt',
                isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get(),
      ]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.person,
            label: 'Active customers',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final activeIds = <String>{};
        if (snap.hasData) {
          for (final d in snap.data![0].docs) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) continue;
            final author = data['author'];
            if (author is Map<String, dynamic>) {
              final id = author['id'] as String?;
              if (id != null && id.isNotEmpty) activeIds.add(id);
            }
          }
        }
        return buildCard(
          icon: Icons.person,
          label: 'Active customers',
          value: '${snap.hasError ? '-' : activeIds.length}',
          helper: 'Last 30d',
          onTap: () => onNavigate(const ActiveCustomersPage()),
          isLoading: false,
        );
      },
    );
  }
}

class TotalCustomersKpi extends StatelessWidget {
  const TotalCustomersKpi({
    super.key,
    required this.onNavigate,
    required this.buildCard,
  });

  final void Function(Widget page) onNavigate;
  final Widget Function({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
    VoidCallback? onTap,
    bool isLoading,
  }) buildCard;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildCard(
            icon: Icons.people,
            label: 'Total customers',
            value: '',
            helper: null,
            onTap: null,
            isLoading: true,
          );
        }
        final n = snap.data?.docs.length ?? 0;
        return buildCard(
          icon: Icons.people,
          label: 'Total customers',
          value: '${snap.hasError ? '-' : n}',
          helper: 'All',
          onTap: () => onNavigate(const CustomersPage()),
          isLoading: false,
        );
      },
    );
  }
}
