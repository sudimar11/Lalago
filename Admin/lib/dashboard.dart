import 'package:brgy/adddashboard.dart';
import 'package:brgy/login.dart';
import 'package:brgy/userlist.dart';
import 'package:brgy/order_dispatcher.dart';
import 'package:brgy/main.dart';
import 'package:brgy/restaurants_page.dart';
import 'package:brgy/foods_page.dart';
import 'package:brgy/pages/bundles_page.dart';
import 'package:brgy/pages/addons_page.dart';
import 'package:brgy/analytics_today.dart';
import 'package:brgy/analytics_weekly.dart';
import 'package:brgy/riders_orders_today_page.dart';
import 'package:brgy/services/notification_service.dart';
import 'package:brgy/services/group_chat_service.dart';
import 'package:brgy/ui/group_chat/GroupChatScreen.dart';
import 'package:brgy/widgets/reaction_buttons.dart';
import 'package:brgy/widgets/driver_list_dialog.dart';
import 'package:brgy/widgets/dashboard_button_card.dart';
import 'package:brgy/orders_today_page.dart';
import 'package:brgy/orders_this_week_page.dart';
import 'package:brgy/total_orders_page.dart';
import 'package:brgy/average_delivery_time_page.dart';
import 'package:brgy/inactive_customers_page.dart';
import 'package:brgy/active_customers_page.dart';
import 'package:brgy/top_buyers_today_page.dart';
import 'package:brgy/customer_repeat_rate_page.dart';
import 'package:brgy/riders_orders_weekly_page.dart';
import 'package:brgy/rider_performance_page.dart';
import 'package:brgy/top_restaurants_orders_today_page.dart';
import 'package:brgy/restaurants_zero_orders_today_page.dart';
import 'package:brgy/restaurant_orders_weekly_page.dart';
import 'package:brgy/restaurant_orders_earning_page.dart';
import 'package:brgy/pages/restaurant_performance_page.dart';
import 'package:brgy/driver_reports_page.dart';
import 'package:brgy/remittance.dart';
import 'package:brgy/confirmed_transactions.dart';
import 'package:brgy/payout.dart';
import 'package:brgy/confirmed_payouts.dart';
import 'package:brgy/payout_remittance_page.dart';
import 'package:brgy/driver_suspension.dart';
import 'package:brgy/driverlist.dart';
import 'package:brgy/pages/ads_management_page.dart';
import 'package:brgy/pages/happy_hour_settings_page.dart';
import 'package:brgy/pages/notification_management_page.dart';
import 'package:brgy/pages/order_recovery_dashboard.dart';
import 'package:brgy/pages/reorder_analytics_page.dart';
import 'package:brgy/pages/ash_voice_dashboard.dart';
import 'package:brgy/pages/hunger_reminder_analytics.dart';
import 'package:brgy/pages/cart_recovery_dashboard.dart';
import 'package:brgy/pages/first_order_coupon_settings_page.dart';
import 'package:brgy/pages/coupon_management_page.dart';
import 'package:brgy/pages/new_user_promo_settings_page.dart';
import 'package:brgy/pages/pautos_settings_page.dart';
import 'package:brgy/pages/referral_settings_page.dart';
import 'package:brgy/pages/loyalty_settings_page.dart';
import 'package:brgy/pages/gift_card_settings_page.dart';
import 'package:brgy/pages/delivery_zone_settings_page.dart';
import 'package:brgy/pages/rider_overview_page.dart';
import 'package:brgy/pages/dispatch_analytics_page.dart';
import 'package:brgy/pages/dispatch_config_page.dart';
import 'package:brgy/pages/rider_time_settings_page.dart';
import 'package:brgy/driver_wallet_page.dart';
import 'package:brgy/driver_collection_page.dart';
import 'package:brgy/pages/customer_suggestions_page.dart';
import 'package:brgy/pages/customer_feedback_page.dart';
import 'package:brgy/pages/search_history_page.dart';
import 'package:brgy/pages/search_analytics_dashboard.dart';
import 'package:brgy/pages/click_analytics_dashboard.dart';
import 'package:brgy/pages/recommendation_performance.dart';
import 'package:brgy/pages/full_operations_page.dart';
import 'package:brgy/pages/user_segments_page.dart';
import 'package:brgy/map_page.dart';
import 'package:brgy/widgets/dashboard/analytics_kpi_cards.dart';
import 'package:brgy/widgets/dashboard/health_score_gauge.dart';
import 'package:brgy/widgets/dashboard/forecast_card.dart';
import 'package:brgy/widgets/dashboard/alert_item.dart';
import 'package:brgy/widgets/dashboard/promo_impact_card.dart';
import 'package:brgy/widgets/dashboard/health_sparkline.dart';
import 'package:brgy/services/main_dashboard_service.dart';
import 'package:brgy/pages/demand_health_dashboard.dart';
import 'package:brgy/pages/forecast_dashboard.dart';
import 'package:brgy/pages/demand_alerts_page.dart';
import 'package:brgy/pages/promo_dashboard.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/services/order_sound_service.dart';
import 'package:brgy/utils/order_ready_time_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'dart:async';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  bool _hasInitialOrdersSnapshot = false;
  final Set<String> _seenOrderIds = <String>{};
  final DateTime _startedAtUtc = DateTime.now().toUtc();

  late final List<Widget> _screens;

  // Handle bottom navigation bar item taps
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _switchToOrdersTab() {
    setState(() {
      _selectedIndex = 1;
    });
  }

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardBlankPage(onNavigateToOrders: _switchToOrdersTab),
      RecentOrdersPage(),
      const GroupChatScreen(),
    ];
    unawaited(OrderSoundService.init());
    _subscribeNewOrders();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    super.dispose();
  }

  void _subscribeNewOrders() {
    final query = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .orderBy('createdAt', descending: true)
        .limit(25);

    _ordersSub = query.snapshots().listen((snapshot) async {
      if (!_hasInitialOrdersSnapshot) {
        _hasInitialOrdersSnapshot = true;
        for (final doc in snapshot.docs) {
          _seenOrderIds.add(doc.id);
        }
        return;
      }

      bool hasNew = false;

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final id = change.doc.id;
        if (_seenOrderIds.contains(id)) continue;
        _seenOrderIds.add(id);

        final data = change.doc.data();
        if (data == null) continue;

        final createdAt = data['createdAt'];
        if (createdAt is! Timestamp) continue;
        final createdUtc = createdAt.toDate().toUtc();

        // Ignore older orders that appear due to refresh/reconnect.
        if (createdUtc.isBefore(_startedAtUtc.subtract(const Duration(seconds: 5)))) {
          continue;
        }

        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'order rejected' || status == 'driver rejected') continue;

        hasNew = true;
      }

      // Prevent unbounded growth.
      if (_seenOrderIds.length > 400) {
        _seenOrderIds.removeAll(_seenOrderIds.take(200));
      }

      if (hasNew) {
        await OrderSoundService.playNewOrderSound();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final int safeIndex = _selectedIndex < _screens.length ? _selectedIndex : 0;

    return Scaffold(
      drawer: const _AnalyticsDrawer(),
      appBar: AppBar(
        title: Text('LalaGO'),
        actions: [
          IconButton(
            icon: const Icon(Icons.trending_up),
            tooltip: 'View Trends',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          StreamBuilder<int>(
            stream: MainDashboardService.streamActiveAlertCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.warning_amber),
                    tooltip: 'Demand Alerts',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DemandAlertsPage(),
                        ),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Notification icon with badge
          StreamBuilder<int>(
            stream: NotificationService.getUnreadCount(),
            builder: (context, snapshot) {
              int unreadCount = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications),
                    tooltip: 'Notifications',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsPage(),
                        ),
                      );
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Driver icon next to notifications
          IconButton(
            icon: Icon(Icons.drive_eta),
            tooltip: 'Drivers',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const DriverListDialog(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              bool? confirmLogout = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('Confirm Logout'),
                    content: Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text('Logout'),
                      ),
                    ],
                  );
                },
              );

              if (confirmLogout == true) {
                try {
                  await auth.FirebaseAuth.instance.signOut();
                  MyAppState.currentUser = null;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logout failed: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _screens[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: StreamBuilder<int>(
              stream: GroupChatService.getUnreadCountStream(),
              builder: (context, snapshot) {
                final unreadCount = snapshot.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat),
                    if (unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            label: 'Chat',
          ),
        ],
        currentIndex: safeIndex,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}

class DashboardBlankPage extends StatefulWidget {
  const DashboardBlankPage({super.key, this.onNavigateToOrders});

  final VoidCallback? onNavigateToOrders;

  @override
  State<DashboardBlankPage> createState() => _DashboardBlankPageState();
}

class _DashboardBlankPageState extends State<DashboardBlankPage> {
  late Future<int> _unpublishedFoodsFuture;

  @override
  void initState() {
    super.initState();
    _unpublishedFoodsFuture = _loadUnpublishedFoodsKpi();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _unpublishedFoodsFuture = _loadUnpublishedFoodsKpi();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<int> _loadUnpublishedFoodsKpi() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('vendor_products').get();

    int unpublished = 0;
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        if (!_isFoodPublished(data)) {
          unpublished++;
        }
      } catch (_) {
        continue;
      }
    }
    return unpublished;
  }

  Future<_AvgDeliveryKpiData> _loadAvgDeliveryKpi() async {
    final DateTime thirtyDaysAgo =
        DateTime.now().subtract(const Duration(days: 30)).toUtc();

    final QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo),
        )
        .get();

    final docs = snapshot.docs;
    int totalMinutes = 0;
    int completedCount = 0;

    for (final doc in docs) {
      try {
        final data = doc.data();
        if (data == null || data is! Map<String, dynamic>) continue;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status != 'order completed' && status != 'completed') continue;

        final createdAt = data['createdAt'];
        final deliveredAt = data['deliveredAt'];
        if (createdAt is! Timestamp || deliveredAt is! Timestamp) continue;

        final minutes =
            deliveredAt.toDate().difference(createdAt.toDate()).inMinutes;
        if (minutes <= 0) continue;

        totalMinutes += minutes;
        completedCount++;
      } catch (_) {
        continue;
      }
    }

    final int avgMinutes =
        completedCount == 0 ? 0 : (totalMinutes / completedCount).round();

    return _AvgDeliveryKpiData(
      avgMinutes: avgMinutes,
      completedCount: completedCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _DashboardLayout.columnsForWidth(
          constraints.maxWidth,
        );
        final isWideHeader = constraints.maxWidth >= 1100;

        void push(Widget page) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          );
        }

        final quickActions = <_QuickActionItem>[
          _QuickActionItem(
            icon: Icons.notifications_active_outlined,
            label: 'Notification management',
            onTap: () => push(const NotificationManagementPage()),
          ),
          _QuickActionItem(
            icon: Icons.restore,
            label: 'Order recovery',
            onTap: () => push(const OrderRecoveryDashboard()),
          ),
          _QuickActionItem(
            icon: Icons.analytics,
            label: 'Reorder analytics',
            onTap: () => push(const ReorderAnalyticsPage()),
          ),
          _QuickActionItem(
            icon: Icons.record_voice_over,
            label: 'Ash voice',
            onTap: () => push(const AshVoiceDashboard()),
          ),
          _QuickActionItem(
            icon: Icons.restaurant_menu,
            label: 'Hunger reminder analytics',
            onTap: () => push(const HungerReminderAnalytics()),
          ),
          _QuickActionItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Cart recovery',
            onTap: () => push(const CartRecoveryDashboard()),
          ),
          _QuickActionItem(
            icon: Icons.local_offer_outlined,
            label: 'Happy hour',
            onTap: () => push(const HappyHourSettingsPage()),
          ),
          _QuickActionItem(
            icon: Icons.notes,
            label: 'Daily notes',
            onTap: () => push(const DailyNotesPage()),
          ),
          _QuickActionItem(
            icon: Icons.block,
            label: 'Suspensions',
            onTap: () => push(DriverSuspensionPage()),
          ),
          _QuickActionItem(
            icon: Icons.analytics_outlined,
            label: 'Weekly analytics',
            onTap: () => push(const AnalyticsWeeklyPage()),
          ),
        ];

        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HealthGaugeCard(onNavigate: push),
                const SizedBox(height: 16),
                if (isWideHeader)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MainForecastCard(onNavigate: push),
                            const SizedBox(height: 12),
                            const _TodaysOrdersCard(),
                            const SizedBox(height: 12),
                            _QuickActionsCard(items: quickActions),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AlertsFeedSection(onNavigate: push),
                            const SizedBox(height: 16),
                            _PromoHighlightsSection(onNavigate: push),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MainForecastCard(onNavigate: push),
                      const SizedBox(height: 12),
                      _AlertsFeedSection(onNavigate: push),
                      const SizedBox(height: 12),
                      _PromoHighlightsSection(onNavigate: push),
                      const SizedBox(height: 12),
                      const _TodaysOrdersCard(),
                      const SizedBox(height: 12),
                      _QuickActionsCard(items: quickActions),
                    ],
                  ),
                const SizedBox(height: 16),
                _AtRiskFocalSection(onNavigate: push),
                const SizedBox(height: 12),
                _AtAGlanceSection(
                  columns: columns,
                  unpublishedFoodsFuture: _unpublishedFoodsFuture,
                  onNavigate: push,
                  onNavigateToOrders: widget.onNavigateToOrders,
                ),
                const SizedBox(height: 20),
                _ManagementHubBar(onNavigate: push),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HealthGaugeCard extends StatelessWidget {
  const _HealthGaugeCard({required this.onNavigate});

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      stream: MainDashboardService.streamLatestHealth(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final score =
            (data?['overallScore'] as num?)?.toInt() ?? 0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Overall Health Score',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    TextButton(
                      onPressed: () =>
                          onNavigate(const DemandHealthDashboard()),
                      child: const Text('View details'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: HealthScoreGauge(
                    score: score,
                    size: 100,
                    showLabel: true,
                    onTap: () =>
                        onNavigate(const DemandHealthDashboard()),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Last 7 days',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: MainDashboardService.getHealthHistory(7),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      );
                    }
                    return HealthSparkline(
                      history: snap.data!,
                      height: 48,
                      days: 7,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MainForecastCard extends StatelessWidget {
  const _MainForecastCard({required this.onNavigate});

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TodayForecastData>(
      future: MainDashboardService.getTodayForecast(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }
        final data = snapshot.data!;
        return FutureBuilder<List<FlSpot>>(
          future: MainDashboardService.getForecastTrendNext7Days(),
          builder: (context, sparkSnap) {
            final spots = sparkSnap.hasData && sparkSnap.data!.isNotEmpty
                ? sparkSnap.data
                : null;
            return ForecastCard(
              predicted: data.predicted,
              actual: data.actual,
              lowerBound: data.lowerBound,
              upperBound: data.upperBound,
              source: data.source,
              sparklineSpots: spots != null && spots.isNotEmpty ? spots : null,
              onTap: () => onNavigate(const ForecastDashboard()),
            );
          },
        );
      },
    );
  }
}

class _AlertsFeedSection extends StatelessWidget {
  const _AlertsFeedSection({required this.onNavigate});

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Active Alerts',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton(
                  onPressed: () => onNavigate(const DemandAlertsPage()),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: MainDashboardService.streamActiveAlerts(limit: 5),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final alerts = snapshot.data ?? [];
                if (alerts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No active alerts',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }
                return Column(
                  children: alerts
                      .map((a) => AlertItem(
                            alertId: a['id'] as String? ?? '',
                            data: a,
                            compact: true,
                            showViewButton: true,
                            onTap: () =>
                                onNavigate(const DemandAlertsPage()),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoHighlightsSection extends StatelessWidget {
  const _PromoHighlightsSection({required this.onNavigate});

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Top Promos',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton(
                  onPressed: () => onNavigate(const PromoDashboard()),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: MainDashboardService.getTopPromosByIncrementalOrders(
                limit: 3,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final promos = snapshot.data ?? [];
                if (promos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No promo data yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }
                return Column(
                  children: promos
                      .map((p) => PromoImpactCard(
                            promoId: p['promoId'] as String? ?? p['id'] ?? '',
                            data: p,
                            compact: true,
                            onTap: () =>
                                onNavigate(const PromoDashboard()),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardLayout {
  static int columnsForWidth(double width) {
    if (width < 420) return 1;
    if (width < 760) return 2;
    if (width < 1100) return 3;
    if (width < 1440) return 4;
    return 5;
  }
}

class _DashboardGroup extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;

  const _DashboardGroup({
    required this.title,
    required this.child,
    required this.initiallyExpanded,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
          children: [child],
        ),
      ),
    );
  }
}

class _DashboardNavItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashboardNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _DashboardNavGrid extends StatelessWidget {
  final int columns;
  final List<_DashboardNavItem> items;

  const _DashboardNavGrid({
    required this.columns,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 72,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return DashboardButtonCard(
          icon: item.icon,
          label: item.label,
          onTap: item.onTap,
        );
      },
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _QuickActionsCard extends StatelessWidget {
  final List<_QuickActionItem> items;

  const _QuickActionsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Quick actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  ElevatedButton.icon(
                    onPressed: item.onTap,
                    icon: Icon(item.icon, size: 18),
                    label: Text(item.label),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      elevation: 0,
                      backgroundColor: Colors.white,
                      foregroundColor: theme.colorScheme.onSurface,
                      iconColor: theme.colorScheme.primary,
                      side: BorderSide(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvgDeliveryKpiData {
  final int avgMinutes;
  final int completedCount;

  const _AvgDeliveryKpiData({
    required this.avgMinutes,
    required this.completedCount,
  });
}

class _AtRiskFocalSection extends StatelessWidget {
  const _AtRiskFocalSection({
    required this.onNavigate,
  });

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    final String todayDate =
        DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay =
        DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay =
        DateTime.parse('$todayDate 23:59:59Z').toUtc();

    final ordersStream = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'At-risk orders',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'At-risk orders',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.error, color: Colors.red),
                ],
              ),
            ),
          );
        }

        final orders = snapshot.data?.docs ?? [];
        final ordersTyped =
            orders.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        final atRiskItems = _computeAtRiskItemsFromOrders(ordersTyped);
        final topAtRisk =
            atRiskItems.length <= 10 ? atRiskItems : atRiskItems.sublist(0, 10);

        return _AtRiskOrdersCard(
          items: topAtRisk,
          onNavigate: onNavigate,
        );
      },
    );
  }
}

class _AnalyticsDrawer extends StatelessWidget {
  const _AnalyticsDrawer();

  void _navigateAndClose(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Trends & Analytics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('30-Day Avg Delivery'),
            onTap: () =>
                _navigateAndClose(context, const AverageDeliveryTimePage()),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Peak Hours Analysis'),
            subtitle: const Text('Most active hours'),
            onTap: () =>
                _navigateAndClose(context, const AnalyticsTodayPage()),
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart),
            title: const Text('User Segments'),
            onTap: () =>
                _navigateAndClose(context, const UserSegmentsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: const Text('Weekly Comparison'),
            onTap: () =>
                _navigateAndClose(context, const AnalyticsWeeklyPage()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.analytics),
            title: const Text('Full Analytics Suite'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () =>
                _navigateAndClose(context, const AnalyticsTodayPage()),
          ),
        ],
      ),
    );
  }
}

class _ManagementHubBar extends StatelessWidget {
  const _ManagementHubBar({
    required this.onNavigate,
  });

  final void Function(Widget page) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HubButton(
                icon: Icons.list_alt,
                label: 'Orders',
                onTap: () => onNavigate(const OrderDispatcherPage()),
              ),
              const SizedBox(width: 8),
              _HubButton(
                icon: Icons.restaurant,
                label: 'Restaurants',
                onTap: () => onNavigate(const RestaurantsPage()),
              ),
              const SizedBox(width: 8),
              _HubButton(
                icon: Icons.delivery_dining,
                label: 'Riders',
                onTap: () => onNavigate(DriverListPage()),
              ),
              const SizedBox(width: 8),
              _HubButton(
                icon: Icons.payments,
                label: 'Finance',
                onTap: () => onNavigate(const RemittancePage()),
              ),
              const SizedBox(width: 8),
              _HubButton(
                icon: Icons.settings,
                label: 'Settings',
                onTap: () => onNavigate(const SettingsPage()),
              ),
              const SizedBox(width: 8),
              _HubButton(
                icon: Icons.more_horiz,
                label: 'More...',
                onTap: () => onNavigate(const FullOperationsPage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HubButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneAKpiRow extends StatelessWidget {
  const _ZoneAKpiRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        if (isNarrow) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: children
                  .map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(width: 120, child: w),
                    ),
                  )
                  .toList(),
            ),
          );
        }
        return Row(
          children: children
              .map(
                (w) => Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: w,
                )),
              )
              .toList(),
        );
      },
    );
  }
}

class _AtAGlanceSection extends StatelessWidget {
  const _AtAGlanceSection({
    required this.columns,
    required this.unpublishedFoodsFuture,
    required this.onNavigate,
    this.onNavigateToOrders,
  });

  final int columns;
  final Future<int> unpublishedFoodsFuture;
  final void Function(Widget page) onNavigate;
  final VoidCallback? onNavigateToOrders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    final ordersStream = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .snapshots();

    final assignmentsLogStream = FirebaseFirestore.instance
        .collection('assignments_log')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .snapshots();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'At a glance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: ordersStream,
              builder: (context, ordersSnap) {
                if (ordersSnap.connectionState == ConnectionState.waiting) {
                  return _KpiGrid(
                    columns: _KpiGrid.columnsForDashboard(columns),
                    children: const [
                      _KpiCard.loading(),
                      _KpiCard.loading(),
                      _KpiCard.loading(),
                      _KpiCard.loading(),
                      _KpiCard.loading(),
                      _KpiCard.loading(),
                    ],
                  );
                }

                if (ordersSnap.hasError) {
                  return _KpiError(
                    message: 'Failed to load today KPIs',
                    details: '${ordersSnap.error}',
                  );
                }

                final orders = ordersSnap.data?.docs ?? const [];
                final int ordersToday = orders.length;
                final int rejectedToday = orders.where((doc) {
                  try {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString().toLowerCase() ?? '';
                    return status == 'order rejected' || status == 'driver rejected';
                  } catch (_) {
                    return false;
                  }
                }).length;

                int completedToday = 0;
                int pendingToday = 0;
                int unassignedNearReady = 0;
                int stuckDriverAssigned = 0;
                int waitingAccept = 0;
                final deliveredRiders = <String>{};
                final ordersByHour = <int, int>{};
                for (int i = 0; i < 24; i++) {
                  ordersByHour[i] = 0;
                }

                final Set<String> vendorsWithOrders = {};
                double earningsToday = 0.0;

                String normalizeOrderStatus(dynamic raw) {
                  if (raw == null) return '—';
                  if (raw is num) {
                    switch (raw.toInt()) {
                      case 0:
                        return 'Order Placed';
                      case 1:
                        return 'Order Accepted';
                      case 2:
                        return 'In Transit';
                      case 3:
                        return 'Order Completed';
                      default:
                        return raw.toString();
                    }
                  }
                  final s = raw.toString().trim();
                  switch (s.toLowerCase()) {
                    case 'request':
                    case 'order placed':
                      return 'Order Placed';
                    case 'confirm':
                    case 'order accepted':
                      return 'Order Accepted';
                    case 'driver assigned':
                      return 'Driver Assigned';
                    case 'driver accepted':
                      return 'Driver Accepted';
                    case 'order shipped':
                      return 'Order Shipped';
                    case 'released':
                    case 'in transit':
                      return 'In Transit';
                    case 'completed':
                    case 'order completed':
                      return 'Order Completed';
                    case 'driver rejected':
                      return 'Driver Rejected';
                    case 'order rejected':
                      return 'Order Rejected';
                    default:
                      return s;
                  }
                }

                String extractDriverId(Map<String, dynamic> data) {
                  final raw = (data['driverID'] ??
                          data['driverId'] ??
                          data['driver_id'] ??
                          '') as Object?;
                  return raw?.toString().trim() ?? '';
                }

                DateTime? asDateTime(dynamic value) {
                  if (value is Timestamp) return value.toDate();
                  if (value is DateTime) return value;
                  return null;
                }

                DateTime? computeReadyAt(Map<String, dynamic> data) {
                  final acceptedAt = asDateTime(data['acceptedAt']);
                  final createdAt = asDateTime(data['createdAt']);
                  final baseTime = acceptedAt ?? createdAt;
                  if (baseTime == null) return null;
                  final prepMin = OrderReadyTimeHelper.parsePreparationMinutes(
                    data['estimatedTimeToPrepare']?.toString(),
                  );
                  return OrderReadyTimeHelper.getReadyAt(baseTime, prepMin);
                }

                for (final doc in orders) {
                  try {
                    final data = doc.data();
                    if (data == null || data is! Map<String, dynamic>) continue;

                    final status = (data['status'] ?? '').toString().toLowerCase();
                    if (status == 'order completed' || status == 'completed') {
                      completedToday++;
                      final driverIdRaw = data['driverID'] ?? data['driver_id'];
                      final driverId = driverIdRaw?.toString();
                      if (driverId != null && driverId.isNotEmpty) {
                        deliveredRiders.add(driverId);
                      }
                    } else if (status != 'order rejected' &&
                        status != 'driver rejected') {
                      pendingToday++;
                    }

                    final normalizedStatus = normalizeOrderStatus(data['status']);
                    final driverId = extractDriverId(data);
                    final now = DateTime.now();

                    if (normalizedStatus == 'Order Accepted' &&
                        driverId.isEmpty) {
                      final readyAt = computeReadyAt(data);
                      if (readyAt != null) {
                        final minutesToReady =
                            readyAt.difference(now).inMinutes;
                        if (minutesToReady <= 10) {
                          unassignedNearReady++;
                        }
                      }
                    }

                    if (normalizedStatus == 'Driver Assigned') {
                      final assignedAt = asDateTime(data['assignedAt']);
                      if (assignedAt != null) {
                        final minutesPending =
                            now.difference(assignedAt).inMinutes;
                        if (minutesPending >= 5) {
                          stuckDriverAssigned++;
                        }
                      }
                    }

                    if (normalizedStatus == 'Order Placed') {
                      final created = asDateTime(data['createdAt']);
                      if (created != null &&
                          now.difference(created).inMinutes >= 5) {
                        waitingAccept++;
                      }
                    }

                    final createdAt = data['createdAt'];
                    if (createdAt is Timestamp) {
                      final hour = createdAt.toDate().toLocal().hour;
                      ordersByHour[hour] = (ordersByHour[hour] ?? 0) + 1;
                    }

                    if (status == 'order rejected' || status == 'driver rejected') {
                      continue;
                    }

                    final vendor = data['vendor'];
                    if (vendor is Map<String, dynamic>) {
                      final vendorId =
                          vendor['id'] as String? ?? vendor['vendorId'] as String?;
                      if (vendorId != null && vendorId.isNotEmpty) {
                        vendorsWithOrders.add(vendorId);
                      }
                    }

                    earningsToday += _commissionFromOrder(data);
                  } catch (_) {
                    continue;
                  }
                }

                final maxOrdersInHour = ordersByHour.values.isEmpty
                    ? 0
                    : ordersByHour.values.reduce((a, b) => a > b ? a : b);
                final peakHours = ordersByHour.entries
                    .where((e) => e.value == maxOrdersInHour && maxOrdersInHour > 0)
                    .map((e) => e.key)
                    .toList()
                  ..sort();
                final peakHourDisplay = peakHours.isEmpty
                    ? 'N/A'
                    : peakHours
                        .map((h) => '${h.toString().padLeft(2, '0')}:00')
                        .join(', ');

                final vendorsStream = FirebaseFirestore.instance
                    .collection('vendors')
                    .orderBy('title')
                    .snapshots();

                return StreamBuilder<QuerySnapshot>(
                  stream: vendorsStream,
                  builder: (context, vendorsSnap) {
                    int? zeroRestaurants;
                    String? zeroRestaurantsError;

                    if (vendorsSnap.hasError) {
                      zeroRestaurantsError = '${vendorsSnap.error}';
                    } else if (vendorsSnap.hasData) {
                      final vendors = vendorsSnap.data?.docs ?? const [];
                      int withOrders = 0;
                      for (final vendor in vendors) {
                        if (vendorsWithOrders.contains(vendor.id)) {
                          withOrders++;
                        }
                      }
                      zeroRestaurants =
                          (vendors.length - withOrders).clamp(0, vendors.length);
                    }

                    DateTime? asDateTime(dynamic value) {
                      if (value is Timestamp) return value.toDate();
                      if (value is DateTime) return value;
                      return null;
                    }

                    String formatSeconds(int seconds) {
                      if (seconds <= 0) return '—';
                      final minutes = seconds ~/ 60;
                      final remSeconds = seconds % 60;
                      if (minutes <= 0) return '${remSeconds}s';
                      return '${minutes}m ${remSeconds.toString().padLeft(2, '0')}s';
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream: assignmentsLogStream,
                      builder: (context, assignmentsSnap) {
                        Widget avgResponseKpi() {
                          if (assignmentsSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const _KpiCard.loading();
                          }
                          if (assignmentsSnap.hasError) {
                            return _KpiCard(
                              icon: Icons.speed,
                              label: 'Avg response',
                              value: '-',
                              helper: 'Failed to load',
                              onTap: () => onNavigate(AssignmentsLogPage()),
                              tone: _KpiTone.warning,
                            );
                          }

                          final docs = assignmentsSnap.data?.docs ?? const [];
                          int totalSeconds = 0;
                          int responses = 0;

                          for (final doc in docs) {
                            try {
                              final data = doc.data();
                              if (data is! Map<String, dynamic>) continue;

                              final status =
                                  (data['status'] ?? '').toString().toLowerCase();
                              if (status != 'accepted' && status != 'rejected') {
                                continue;
                              }

                              final offeredAt =
                                  asDateTime(data['offeredAt']) ??
                                      asDateTime(data['createdAt']);
                              final responseAt =
                                  asDateTime(data['responseTime']) ??
                                      asDateTime(data['acceptedAt']) ??
                                      asDateTime(data['rejectedAt']);
                              if (offeredAt == null || responseAt == null) continue;

                              final seconds =
                                  responseAt.difference(offeredAt).inSeconds;
                              if (seconds <= 0) continue;

                              totalSeconds += seconds;
                              responses++;
                            } catch (_) {
                              continue;
                            }
                          }

                          final avgSeconds = responses == 0
                              ? null
                              : (totalSeconds / responses).round();

                          return _KpiCard(
                            icon: Icons.speed,
                            label: 'Avg response',
                            value: avgSeconds == null ? '—' : formatSeconds(avgSeconds),
                            helper: responses == 0 ? 'No responses' : 'Today • $responses',
                            onTap: () => onNavigate(AssignmentsLogPage()),
                            tone: avgSeconds == null
                                ? _KpiTone.neutral
                                : (avgSeconds >= 180 ? _KpiTone.warning : _KpiTone.neutral),
                          );
                        }

                        Widget rejectionRateKpi() {
                          if (assignmentsSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const _KpiCard.loading();
                          }
                          if (assignmentsSnap.hasError) {
                            return _KpiCard(
                              icon: Icons.thumb_down_alt_outlined,
                              label: 'Rejection rate',
                              value: '-',
                              helper: 'Failed to load',
                              onTap: () => onNavigate(AssignmentsLogPage()),
                              tone: _KpiTone.warning,
                            );
                          }

                          final docs = assignmentsSnap.data?.docs ?? const [];
                          int accepted = 0;
                          int rejected = 0;

                          for (final doc in docs) {
                            try {
                              final data = doc.data();
                              if (data is! Map<String, dynamic>) continue;
                              final status =
                                  (data['status'] ?? '').toString().toLowerCase();
                              if (status == 'accepted') accepted++;
                              if (status == 'rejected') rejected++;
                            } catch (_) {
                              continue;
                            }
                          }

                          final total = accepted + rejected;
                          final rate = total == 0 ? null : rejected / total;
                          final percent =
                              rate == null ? '—' : '${(rate * 100).round()}%';

                          final tone = rate == null
                              ? _KpiTone.neutral
                              : (rate >= 0.5
                                  ? _KpiTone.danger
                                  : (rate >= 0.2
                                      ? _KpiTone.warning
                                      : _KpiTone.neutral));

                          return _KpiCard(
                            icon: Icons.thumb_down_alt_outlined,
                            label: 'Rejection rate',
                            value: percent,
                            helper: total == 0 ? 'No responses' : 'Today • $total',
                            onTap: () => onNavigate(AssignmentsLogPage()),
                            tone: tone,
                          );
                        }

                        return FutureBuilder<int>(
                          future: unpublishedFoodsFuture,
                          builder: (context, foodsSnap) {
                            final unpublishedFoods = foodsSnap.data;

                            Widget buildAnalyticsCard({
                              required IconData icon,
                              required String label,
                              required String value,
                              String? helper,
                              VoidCallback? onTap,
                              bool isLoading = false,
                            }) {
                              return isLoading
                                  ? const _KpiCard.loading()
                                  : _KpiCard(
                                      icon: icon,
                                      label: label,
                                      value: value,
                                      helper: helper,
                                      onTap: onTap,
                                      tone: _KpiTone.neutral,
                                    );
                            }

                            final kpiChildren = <Widget>[
                          _KpiCard(
                            icon: Icons.receipt_long,
                            label: 'Orders today',
                            value: ordersToday.toString(),
                            helper: 'Today',
                            tone: _KpiTone.brand,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.pending_actions,
                            label: 'Pending today',
                            value: pendingToday.toString(),
                            helper: 'Not done yet',
                            tone: pendingToday > 0
                                ? _KpiTone.warning
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.schedule,
                            label: 'Near-ready unassigned',
                            value: unassignedNearReady.toString(),
                            helper: 'Ready ≤10m • no rider',
                            tone: unassignedNearReady > 0
                                ? _KpiTone.danger
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(
                              const OrderDispatcherPage(initialTabIndex: 1),
                            ),
                          ),
                          _KpiCard(
                            icon: Icons.hourglass_bottom,
                            label: 'Stuck assigned',
                            value: stuckDriverAssigned.toString(),
                            helper: 'Driver assigned ≥5m',
                            tone: stuckDriverAssigned > 0
                                ? _KpiTone.warning
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(AssignmentsLogPage()),
                          ),
                          _KpiCard(
                            icon: Icons.check_circle,
                            label: 'Completed today',
                            value: completedToday.toString(),
                            helper: 'Delivered/completed',
                            tone: completedToday > 0
                                ? _KpiTone.success
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.cancel,
                            label: 'Rejected today',
                            value: rejectedToday.toString(),
                            helper: 'Order/driver rejected',
                            tone: rejectedToday > 0
                                ? _KpiTone.danger
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _ActiveRidersKpi(onNavigate: onNavigate),
                          if (vendorsSnap.connectionState ==
                              ConnectionState.waiting)
                            const _KpiCard.loading()
                          else if (zeroRestaurantsError != null)
                            _KpiCard(
                              icon: Icons.restaurant,
                              label: 'Zero-order restaurants',
                              value: '-',
                              helper: 'Failed to load',
                              onTap: () => onNavigate(
                                const RestaurantsZeroOrdersTodayPage(),
                              ),
                              tone: _KpiTone.warning,
                            )
                          else
                            _KpiCard(
                              icon: Icons.restaurant,
                              label: 'Zero-order restaurants',
                              value: '${zeroRestaurants ?? 0}',
                              helper: 'Today',
                              onTap: () => onNavigate(
                                const RestaurantsZeroOrdersTodayPage(),
                              ),
                              tone: (zeroRestaurants ?? 0) > 0
                                  ? _KpiTone.warning
                                  : _KpiTone.neutral,
                            ),
                          _KpiCard(
                            icon: Icons.local_shipping,
                            label: 'Riders delivered',
                            value: deliveredRiders.length.toString(),
                            helper: 'Unique riders',
                            tone: deliveredRiders.isNotEmpty
                                ? _KpiTone.success
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(const AnalyticsTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.payments,
                            label: 'Earnings today',
                            value: _formatCurrency(earningsToday),
                            helper: 'Admin commission',
                            tone: earningsToday > 0
                                ? _KpiTone.success
                                : _KpiTone.neutral,
                            onTap: () =>
                                onNavigate(const RestaurantOrdersEarningPage()),
                          ),
                          NewCustomersTodayKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          BuyersTodayKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          OrdersThisWeekKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          BuyersThisWeekKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          TotalFoodsKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          UnpublishedFoodsKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          FoodsAddedTodayKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          TotalRestaurantsKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          TotalRidersKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          InactiveCustomersKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          ActiveCustomersKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          TotalCustomersKpi(
                            onNavigate: onNavigate,
                            buildCard: buildAnalyticsCard,
                          ),
                          avgResponseKpi(),
                          rejectionRateKpi(),
                        ];

                        final atRiskCount =
                            unassignedNearReady + stuckDriverAssigned;
                        final zoneACards = <Widget>[
                          _KpiCard(
                            icon: Icons.receipt_long,
                            label: 'Orders',
                            value: ordersToday.toString(),
                            helper: 'Today',
                            tone: _KpiTone.brand,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.pending_actions,
                            label: 'Pending',
                            value: pendingToday.toString(),
                            helper: 'Not done',
                            tone: pendingToday > 0
                                ? _KpiTone.warning
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(const OrdersTodayPage()),
                          ),
                          _KpiCard(
                            icon: Icons.warning_amber_outlined,
                            label: 'At-Risk',
                            value: atRiskCount.toString(),
                            helper: 'Need action',
                            tone: atRiskCount > 0
                                ? _KpiTone.danger
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(
                              const OrderDispatcherPage(initialTabIndex: 1),
                            ),
                          ),
                          _ActiveRidersKpi(onNavigate: onNavigate),
                          _KpiCard(
                            icon: Icons.payments,
                            label: 'GMV',
                            value: _formatCurrency(earningsToday),
                            helper: 'Today',
                            tone: earningsToday > 0
                                ? _KpiTone.success
                                : _KpiTone.neutral,
                            onTap: () => onNavigate(
                              const RestaurantOrdersEarningPage(),
                            ),
                          ),
                        ];

                        return Column(
                          children: [
                            _ZoneAKpiRow(children: zoneACards),
                            const SizedBox(height: 12),
                            _DeliveryPipelineCard(
                              ordersToday: orders.cast<
                                  QueryDocumentSnapshot<
                                      Map<String, dynamic>>>(),
                              waitingAccept: waitingAccept,
                              unassignedNearReady: unassignedNearReady,
                              stuckDriverAssigned: stuckDriverAssigned,
                              onNavigate: onNavigate,
                              onNavigateToOrders: onNavigateToOrders,
                              asDateTime: asDateTime,
                            ),
                            const SizedBox(height: 12),
                            _AlertsStrip(
                              rejectedToday: rejectedToday,
                              zeroOrderRestaurants: zeroRestaurants,
                              unpublishedFoods: unpublishedFoods,
                              onNavigate: onNavigate,
                            ),
                            const SizedBox(height: 12),
                            _OrdersSparklineCard(
                              countsByHour: List<int>.generate(
                                24,
                                (i) => ordersByHour[i] ?? 0,
                              ),
                              peakHourDisplay: peakHourDisplay,
                              onTap: () =>
                                  onNavigate(const AnalyticsTodayPage()),
                            ),
                            const SizedBox(height: 12),
                            _KpiGrid(
                              columns: _KpiGrid.columnsForDashboard(
                                columns,
                              ),
                              children: kpiChildren,
                            ),
                            const SizedBox(height: 12),
                            _WeeklySnapshotCard(
                              onNavigate: onNavigate,
                            ),
                            const SizedBox(height: 12),
                            _DailyFinanceShortcuts(
                              onNavigate: onNavigate,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
          ],
        ),
      ),
    );
  }

  double _commissionFromOrder(Map<String, dynamic> data) =>
      _commissionFromOrderData(data);

  String _formatCurrency(double value) => '₱${value.toStringAsFixed(2)}';
}

double _commissionFromOrderData(Map<String, dynamic> data) {
  final adminCommission = data['adminCommission'];
  final adminCommissionType =
      (data['adminCommissionType'] as String? ?? 'Fixed').trim();

  double commissionValue = 0.0;
  if (adminCommission is num) {
    commissionValue = adminCommission.toDouble();
  } else if (adminCommission is String) {
    commissionValue = double.tryParse(adminCommission) ?? 0.0;
  }
  if (commissionValue <= 0) return 0.0;

  final itemCount = _itemCountFromOrderData(data);
  if (itemCount <= 0) return 0.0;

  if (adminCommissionType == 'Fixed') {
    return itemCount * commissionValue;
  }

  if (adminCommissionType == 'Percent') {
    return itemCount * commissionValue;
  }

  return itemCount * commissionValue;
}

int _itemCountFromOrderData(Map<String, dynamic> data) {
  final products = data['products'];
  if (products is! List) return 0;

  int count = 0;
  for (final p in products) {
    if (p is! Map<String, dynamic>) continue;
    final raw = p['quantity'];
    if (raw is num) {
      count += raw.toInt();
    } else if (raw is String) {
      count += int.tryParse(raw) ?? 1;
    } else {
      count += 1;
    }
  }
  return count;
}

enum _AtRiskOrderType { unassignedNearReady, stuckDriverAssigned }

class _AtRiskOrderItem {
  final _AtRiskOrderType type;
  final String orderId;
  final String vendorName;

  final DateTime? readyAt;
  final int? minutesToReady;

  final DateTime? assignedAt;
  final int? minutesPending;

  const _AtRiskOrderItem._({
    required this.type,
    required this.orderId,
    required this.vendorName,
    required this.readyAt,
    required this.minutesToReady,
    required this.assignedAt,
    required this.minutesPending,
  });

  factory _AtRiskOrderItem.unassignedNearReady({
    required String orderId,
    required String vendorName,
    required DateTime readyAt,
    required int minutesToReady,
  }) {
    return _AtRiskOrderItem._(
      type: _AtRiskOrderType.unassignedNearReady,
      orderId: orderId,
      vendorName: vendorName,
      readyAt: readyAt,
      minutesToReady: minutesToReady,
      assignedAt: null,
      minutesPending: null,
    );
  }

  factory _AtRiskOrderItem.stuckDriverAssigned({
    required String orderId,
    required String vendorName,
    required DateTime assignedAt,
    required int minutesPending,
  }) {
    return _AtRiskOrderItem._(
      type: _AtRiskOrderType.stuckDriverAssigned,
      orderId: orderId,
      vendorName: vendorName,
      readyAt: null,
      minutesToReady: null,
      assignedAt: assignedAt,
      minutesPending: minutesPending,
    );
  }

  String get shortOrderId =>
      orderId.length <= 8 ? orderId : orderId.substring(0, 8);

  String get displayVendorName =>
      vendorName.trim().isEmpty ? 'Unknown restaurant' : vendorName.trim();

  String get statusText => switch (type) {
        _AtRiskOrderType.unassignedNearReady => 'Unassigned',
        _AtRiskOrderType.stuckDriverAssigned => 'Driver Assigned',
      };

  String get timingText {
    switch (type) {
      case _AtRiskOrderType.unassignedNearReady:
        final m = minutesToReady ?? 0;
        if (m < 0) return 'Overdue ${-m}m';
        return 'Ready in ${m}m';
      case _AtRiskOrderType.stuckDriverAssigned:
        final m = minutesPending ?? 0;
        return 'Pending ${m}m';
    }
  }

  int get riskScore {
    switch (type) {
      case _AtRiskOrderType.unassignedNearReady:
        final m = minutesToReady ?? 999;
        if (m <= 0) return 1000 + (-m).clamp(0, 120);
        return 900 + (10 - m).clamp(0, 10);
      case _AtRiskOrderType.stuckDriverAssigned:
        final m = minutesPending ?? 0;
        return 700 + m.clamp(0, 120);
    }
  }
}

String _vendorNameFromOrder(Map<String, dynamic> data) {
  final vendor = data['vendor'];
  if (vendor is Map<String, dynamic>) {
    final title = vendor['title'] ?? vendor['name'];
    final s = title?.toString().trim() ?? '';
    if (s.isNotEmpty) return s;
  }
  return '';
}

List<_AtRiskOrderItem> _computeAtRiskItemsFromOrders(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
) {
  DateTime? asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String normalizeOrderStatus(dynamic raw) {
    if (raw == null) return '—';
    if (raw is num) {
      switch (raw.toInt()) {
        case 0:
          return 'Order Placed';
        case 1:
          return 'Order Accepted';
        case 2:
          return 'In Transit';
        case 3:
          return 'Order Completed';
        default:
          return raw.toString();
      }
    }
    final s = raw.toString().trim();
    switch (s.toLowerCase()) {
      case 'request':
      case 'order placed':
        return 'Order Placed';
      case 'confirm':
      case 'order accepted':
        return 'Order Accepted';
      case 'driver assigned':
        return 'Driver Assigned';
      case 'driver accepted':
        return 'Driver Accepted';
      case 'order shipped':
        return 'Order Shipped';
      case 'released':
      case 'in transit':
        return 'In Transit';
      case 'completed':
      case 'order completed':
        return 'Order Completed';
      case 'driver rejected':
        return 'Driver Rejected';
      case 'order rejected':
        return 'Order Rejected';
      default:
        return s;
    }
  }

  String extractDriverId(Map<String, dynamic> data) {
    final raw = (data['driverID'] ?? data['driverId'] ?? data['driver_id'] ?? '')
        as Object?;
    return raw?.toString().trim() ?? '';
  }

  DateTime? computeReadyAt(Map<String, dynamic> data) {
    final acceptedAt = asDateTime(data['acceptedAt']);
    final createdAt = asDateTime(data['createdAt']);
    final baseTime = acceptedAt ?? createdAt;
    if (baseTime == null) return null;
    final prepMin = OrderReadyTimeHelper.parsePreparationMinutes(
      data['estimatedTimeToPrepare']?.toString(),
    );
    return OrderReadyTimeHelper.getReadyAt(baseTime, prepMin);
  }

  final atRiskItems = <_AtRiskOrderItem>[];
  final now = DateTime.now();

  for (final doc in orders) {
    try {
      final data = doc.data();
      if (data == null || data is! Map<String, dynamic>) continue;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'order rejected' || status == 'driver rejected') continue;

      final normalizedStatus = normalizeOrderStatus(data['status']);
      final driverId = extractDriverId(data);

      if (normalizedStatus == 'Order Accepted' && driverId.isEmpty) {
        final readyAt = computeReadyAt(data);
        if (readyAt != null) {
          final minutesToReady = readyAt.difference(now).inMinutes;
          if (minutesToReady <= 10) {
            atRiskItems.add(
              _AtRiskOrderItem.unassignedNearReady(
                orderId: doc.id,
                vendorName: _vendorNameFromOrder(data),
                readyAt: readyAt,
                minutesToReady: minutesToReady,
              ),
            );
          }
        }
      }

      if (normalizedStatus == 'Driver Assigned') {
        final assignedAt = asDateTime(data['assignedAt']);
        if (assignedAt != null) {
          final minutesPending = now.difference(assignedAt).inMinutes;
          if (minutesPending >= 5) {
            atRiskItems.add(
              _AtRiskOrderItem.stuckDriverAssigned(
                orderId: doc.id,
                vendorName: _vendorNameFromOrder(data),
                assignedAt: assignedAt,
                minutesPending: minutesPending,
              ),
            );
          }
        }
      }
    } catch (_) {
      continue;
    }
  }

  atRiskItems.sort((a, b) => b.riskScore.compareTo(a.riskScore));
  return atRiskItems;
}

/// Stage averages (today) for delivery pipeline. -1 means no data.
class _PipelineStageAverages {
  const _PipelineStageAverages({
    required this.acceptMinutes,
    required this.assignMinutes,
    required this.atRestaurantMinutes,
    required this.transitMinutes,
  });

  final int acceptMinutes;
  final int assignMinutes;
  final int atRestaurantMinutes;
  final int transitMinutes;

  int get slowestIndex {
    final list = [acceptMinutes, assignMinutes, atRestaurantMinutes, transitMinutes];
    int max = -1;
    int idx = -1;
    for (int i = 0; i < list.length; i++) {
      if (list[i] > max) {
        max = list[i];
        idx = i;
      }
    }
    return idx;
  }
}

_PipelineStageAverages _computePipelineStageAverages(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
  DateTime? Function(dynamic) asDateTime,
) {
  int acceptSum = 0, acceptCount = 0;
  int assignSum = 0, assignCount = 0;
  int atRestaurantSum = 0, atRestaurantCount = 0;
  int transitSum = 0, transitCount = 0;

  for (final doc in orders) {
    final data = doc.data();
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'order rejected' || status == 'driver rejected') continue;

    final createdAt = asDateTime(data['createdAt']);
    final acceptedAt = asDateTime(data['acceptedAt']);
    final assignedAt = asDateTime(data['assignedAt']);
    final pickedUpAt = asDateTime(data['pickedUpAt']);
    final deliveredAt = asDateTime(data['deliveredAt']);

    if (createdAt != null && acceptedAt != null && acceptedAt.isAfter(createdAt)) {
      final min = acceptedAt.difference(createdAt).inMinutes;
      if (min >= 0) {
        acceptSum += min;
        acceptCount++;
      }
    }
    if (acceptedAt != null && assignedAt != null && assignedAt.isAfter(acceptedAt)) {
      final min = assignedAt.difference(acceptedAt).inMinutes;
      if (min >= 0) {
        assignSum += min;
        assignCount++;
      }
    }
    if (assignedAt != null && pickedUpAt != null && pickedUpAt.isAfter(assignedAt)) {
      final min = pickedUpAt.difference(assignedAt).inMinutes;
      if (min >= 0) {
        atRestaurantSum += min;
        atRestaurantCount++;
      }
    }
    if (pickedUpAt != null && deliveredAt != null && deliveredAt.isAfter(pickedUpAt)) {
      final min = deliveredAt.difference(pickedUpAt).inMinutes;
      if (min >= 0) {
        transitSum += min;
        transitCount++;
      }
    }
  }

  return _PipelineStageAverages(
    acceptMinutes: acceptCount == 0 ? -1 : (acceptSum / acceptCount).round(),
    assignMinutes: assignCount == 0 ? -1 : (assignSum / assignCount).round(),
    atRestaurantMinutes: atRestaurantCount == 0
        ? -1
        : (atRestaurantSum / atRestaurantCount).round(),
    transitMinutes: transitCount == 0 ? -1 : (transitSum / transitCount).round(),
  );
}

class _DeliveryPipelineCard extends StatelessWidget {
  const _DeliveryPipelineCard({
    required this.ordersToday,
    required this.waitingAccept,
    required this.unassignedNearReady,
    required this.stuckDriverAssigned,
    required this.onNavigate,
    required this.asDateTime,
    this.onNavigateToOrders,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> ordersToday;
  final int waitingAccept;
  final int unassignedNearReady;
  final int stuckDriverAssigned;
  final void Function(Widget page) onNavigate;
  final DateTime? Function(dynamic) asDateTime;
  final VoidCallback? onNavigateToOrders;

  static String _formatStageMinutes(int minutes) {
    if (minutes < 0) return '—';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final averages =
        _computePipelineStageAverages(ordersToday, asDateTime);
    final slowest = averages.slowestIndex;
    const labels = ['Accept', 'Assign', 'At restaurant', 'Transit'];
    final values = [
      averages.acceptMinutes,
      averages.assignMinutes,
      averages.atRestaurantMinutes,
      averages.transitMinutes,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Delivery pipeline',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(4, (i) {
                    final isSlowest = i == slowest && values[i] >= 0;
                    return InkWell(
                      onTap: onNavigateToOrders,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSlowest
                              ? Colors.orange.withValues(alpha: 0.15)
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: isSlowest
                              ? Border.all(color: Colors.orange, width: 1.5)
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              labels[i],
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight:
                                    isSlowest ? FontWeight.w700 : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatStageMinutes(values[i]),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isSlowest ? Colors.orange : null,
                              ),
                            ),
                            if (isSlowest) ...[
                              const SizedBox(width: 4),
                              Text(
                                'Slowest',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$waitingAccept waiting accept · '
                    '$unassignedNearReady unassigned · '
                    '$stuckDriverAssigned stuck',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onNavigateToOrders != null)
                  TextButton(
                    onPressed: onNavigateToOrders,
                    child: const Text('View orders'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AtRiskOrdersCard extends StatelessWidget {
  final List<_AtRiskOrderItem> items;
  final void Function(Widget page) onNavigate;

  const _AtRiskOrdersCard({
    required this.items,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'At-risk orders',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(
                'No at-risk orders right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        item.timingText.replaceAll(RegExp(r'[^0-9]'), ''),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      item.displayVendorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Order #${item.shortOrderId} • ${item.statusText} • ${item.timingText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      switch (item.type) {
                        case _AtRiskOrderType.unassignedNearReady:
                          onNavigate(const OrderDispatcherPage(initialTabIndex: 1));
                          return;
                        case _AtRiskOrderType.stuckDriverAssigned:
                          onNavigate(AssignmentsLogPage());
                          return;
                      }
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

enum _KpiTone { neutral, brand, success, warning, danger }

class _KpiCard extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String? value;
  final String? helper;
  final VoidCallback? onTap;
  final _KpiTone tone;
  final bool isLoading;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.onTap,
    this.tone = _KpiTone.neutral,
  }) : isLoading = false;

  const _KpiCard.loading()
      : icon = null,
        label = null,
        value = null,
        helper = null,
        onTap = null,
        tone = _KpiTone.neutral,
        isLoading = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const dangerColor = Color(0xFFDC2626);
    const warningColor = Color(0xFFF59E0B);
    const successColor = Color(0xFF16A34A);

    final baseColor = switch (tone) {
      _KpiTone.brand => theme.colorScheme.primary,
      _KpiTone.success => successColor,
      _KpiTone.warning => warningColor,
      _KpiTone.danger => dangerColor,
      _KpiTone.neutral => theme.colorScheme.onSurface.withValues(alpha: 0.65),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: isLoading
              ? const _KpiLoading()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: baseColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      value!,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (helper != null && helper!.isNotEmpty)
                      Text(
                        helper!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _KpiLoading extends StatelessWidget {
  const _KpiLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 4),
        LinearProgressIndicator(minHeight: 6),
        SizedBox(height: 10),
        LinearProgressIndicator(minHeight: 10),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _KpiGrid({required this.columns, required this.children});

  static int columnsForDashboard(int dashboardColumns) {
    if (dashboardColumns <= 1) return 1;
    if (dashboardColumns == 2) return 2;
    if (dashboardColumns == 3) return 3;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 118,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _KpiError extends StatelessWidget {
  final String message;
  final String details;

  const _KpiError({required this.message, required this.details});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SelectableText.rich(
        TextSpan(
          text: '$message\n',
          style: const TextStyle(color: Colors.red),
          children: [
            TextSpan(
              text: details,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRidersKpi extends StatelessWidget {
  final void Function(Widget page) onNavigate;

  const _ActiveRidersKpi({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _KpiCard.loading();
        }
        if (snapshot.hasError) {
          return _KpiCard(
            icon: Icons.drive_eta,
            label: 'Active riders',
            value: '-',
            helper: 'Failed to load',
            onTap: () => onNavigate(DriversMapPage()),
            tone: _KpiTone.warning,
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        int activeToday = 0;
        for (final doc in docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final isOnline = data['isOnline'] == true;
            final availability =
                (data['riderAvailability'] ?? 'offline').toString();
            if (isOnline &&
                availability != 'offline') {
              activeToday++;
            }
          } catch (_) {}
        }

        return _KpiCard(
          icon: Icons.drive_eta,
          label: 'Active riders',
          value: activeToday.toString(),
          helper: 'Currently online',
          onTap: () => onNavigate(DriversMapPage()),
        );
      },
    );
  }
}

class _AvgDeliveryKpi extends StatelessWidget {
  final Future<_AvgDeliveryKpiData> future;
  final void Function(Widget page) onNavigate;

  const _AvgDeliveryKpi({
    required this.future,
    required this.onNavigate,
  });

  String _formatDuration(int totalMinutes) {
    if (totalMinutes <= 0) return 'N/A';
    if (totalMinutes < 60) return '$totalMinutes mins';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}mins';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AvgDeliveryKpiData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _KpiCard.loading();
        }
        if (snapshot.hasError) {
          return _KpiCard(
            icon: Icons.timer,
            label: 'Avg delivery',
            value: '-',
            helper: 'Failed to load',
            onTap: () => onNavigate(const AverageDeliveryTimePage()),
            tone: _KpiTone.warning,
          );
        }

        final data = snapshot.data;
        return _KpiCard(
          icon: Icons.timer,
          label: 'Avg delivery',
          value: _formatDuration(data?.avgMinutes ?? 0),
          helper: 'Last 30 days',
          onTap: () => onNavigate(const AverageDeliveryTimePage()),
        );
      },
    );
  }
}

class _AlertsStrip extends StatelessWidget {
  final int rejectedToday;
  final int? zeroOrderRestaurants;
  final int? unpublishedFoods;
  final void Function(Widget page) onNavigate;

  const _AlertsStrip({
    required this.rejectedToday,
    required this.zeroOrderRestaurants,
    required this.unpublishedFoods,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const successColor = Color(0xFF16A34A);
    final alerts = <Widget>[];

    if (rejectedToday > 0) {
      alerts.add(
        _AlertChip(
          icon: Icons.cancel,
          label: '$rejectedToday rejected today',
          tone: _KpiTone.danger,
          onTap: () => onNavigate(const OrdersTodayPage()),
        ),
      );
    }

    if ((zeroOrderRestaurants ?? 0) > 0) {
      alerts.add(
        _AlertChip(
          icon: Icons.restaurant,
          label: '${zeroOrderRestaurants ?? 0} restaurants with 0 orders',
          tone: _KpiTone.warning,
          onTap: () => onNavigate(const RestaurantsZeroOrdersTodayPage()),
        ),
      );
    }

    if ((unpublishedFoods ?? 0) > 0) {
      alerts.add(
        _AlertChip(
          icon: Icons.visibility_off,
          label: '${unpublishedFoods ?? 0} unpublished foods',
          tone: _KpiTone.warning,
          onTap: () => onNavigate(const FoodsPage(filterUnpublished: true)),
        ),
      );
    }

    if (alerts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: successColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: successColor.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: successColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No urgent alerts right now',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: alerts,
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final _KpiTone tone;
  final VoidCallback onTap;

  const _AlertChip({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const dangerColor = Color(0xFFDC2626);
    const warningColor = Color(0xFFF59E0B);
    const successColor = Color(0xFF16A34A);

    final color = switch (tone) {
      _KpiTone.brand => Theme.of(context).colorScheme.primary,
      _KpiTone.success => successColor,
      _KpiTone.warning => warningColor,
      _KpiTone.danger => dangerColor,
      _KpiTone.neutral => Theme.of(context).colorScheme.onSurface,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklySnapshotCard extends StatefulWidget {
  final void Function(Widget page) onNavigate;

  const _WeeklySnapshotCard({required this.onNavigate});

  @override
  State<_WeeklySnapshotCard> createState() => _WeeklySnapshotCardState();
}

class _WeeklySnapshotCardState extends State<_WeeklySnapshotCard> {
  late final Future<_WeeklySnapshotData> _weeklyFuture;

  @override
  void initState() {
    super.initState();
    _weeklyFuture = _loadWeeklyData();
  }

  Future<_WeeklySnapshotData> _loadWeeklyData() async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));
    final startOfRange =
        DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);
    final endOfRange =
        DateTime(now.year, now.month, now.day, 23, 59, 59);

    final snapshot = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfRange))
        .get();

    int ordersThisWeek = 0;
    int completedThisWeek = 0;
    double earningsThisWeek = 0.0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        if (data.isEmpty) continue;

        ordersThisWeek++;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'order completed' || status == 'completed') {
          completedThisWeek++;
        }
        if (status != 'order rejected' && status != 'driver rejected') {
          earningsThisWeek += _commissionFromOrderData(data);
        }
      } catch (_) {
        continue;
      }
    }

    return _WeeklySnapshotData(
      orders: ordersThisWeek,
      completed: completedThisWeek,
      earnings: earningsThisWeek,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<_WeeklySnapshotData>(
      future: _weeklyFuture,
      builder: (context, snapshot) {
        final orders = snapshot.data?.orders ?? 0;
        final completed = snapshot.data?.completed ?? 0;
        final earnings = snapshot.data?.earnings ?? 0.0;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onNavigate(const AnalyticsWeeklyPage()),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_view_week,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Weekly snapshot',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLoading
                        ? 'Loading...'
                        : hasError
                            ? '—'
                            : 'Orders: $orders | Completed: $completed | '
                                'Earnings: ₱${earnings.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap for full analytics',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeeklySnapshotData {
  final int orders;
  final int completed;
  final double earnings;

  const _WeeklySnapshotData({
    required this.orders,
    required this.completed,
    required this.earnings,
  });
}

class _DailyFinanceShortcuts extends StatelessWidget {
  final void Function(Widget page) onNavigate;

  const _DailyFinanceShortcuts({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance_wallet, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Daily finance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: DashboardButtonCard(
                  icon: Icons.send,
                  label: 'Remittance',
                  onTap: () => onNavigate(const RemittancePage()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: DashboardButtonCard(
                  icon: Icons.check_circle,
                  label: 'Confirm remittance',
                  onTap: () => onNavigate(const ConfirmedTransactionsPage()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: DashboardButtonCard(
                  icon: Icons.payment,
                  label: 'Payout request',
                  onTap: () => onNavigate(const PayoutPage()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: DashboardButtonCard(
                  icon: Icons.verified,
                  label: 'Confirm payout',
                  onTap: () => onNavigate(const ConfirmedPayoutsPage()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: DashboardButtonCard(
                  icon: Icons.money_off,
                  label: 'Collect from driver',
                  onTap: () => onNavigate(const DriverCollectionPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrdersSparklineCard extends StatelessWidget {
  final List<int> countsByHour;
  final String peakHourDisplay;
  final VoidCallback onTap;

  const _OrdersSparklineCard({
    required this.countsByHour,
    required this.peakHourDisplay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Orders timeline (today)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Peak: $peakHourDisplay',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 96,
                width: double.infinity,
                child: CustomPaint(
                  painter: _OrdersSparklinePainter(
                    countsByHour: countsByHour,
                    lineColor: Colors.orange,
                    fillColor: Colors.orange.withValues(alpha: 0.10),
                    gridColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap for full analytics',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersSparklinePainter extends CustomPainter {
  final List<int> countsByHour;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  const _OrdersSparklinePainter({
    required this.countsByHour,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (countsByHour.isEmpty) return;

    const padding = 8.0;
    final rect = Rect.fromLTWH(
      padding,
      padding,
      size.width - (padding * 2),
      size.height - (padding * 2),
    );

    final maxValue = countsByHour.reduce((a, b) => a > b ? a : b);
    final denom = (maxValue <= 0) ? 1 : maxValue;

    // Grid: vertical at 0, 6, 12, 18, 23
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final hour in const [0, 6, 12, 18, 23]) {
      final dx = rect.left + rect.width * (hour / 23.0);
      canvas.drawLine(Offset(dx, rect.top), Offset(dx, rect.bottom), gridPaint);
    }
    // Horizontal mid line
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height * 0.5),
      Offset(rect.right, rect.top + rect.height * 0.5),
      gridPaint,
    );

    final points = <Offset>[];
    for (int hour = 0; hour < 24; hour++) {
      final v = countsByHour[hour].clamp(0, 1 << 30);
      final t = hour / 23.0;
      final x = rect.left + rect.width * t;
      final y = rect.bottom - rect.height * (v / denom);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, rect.bottom)
      ..lineTo(points.first.dx, rect.bottom)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Dot at latest hour
    final dotPaint = Paint()..color = lineColor;
    canvas.drawCircle(points.last, 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _OrdersSparklinePainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor) return true;
    if (oldDelegate.fillColor != fillColor) return true;
    if (oldDelegate.gridColor != gridColor) return true;
    if (oldDelegate.countsByHour.length != countsByHour.length) return true;
    for (int i = 0; i < countsByHour.length; i++) {
      if (oldDelegate.countsByHour[i] != countsByHour[i]) return true;
    }
    return false;
  }
}

bool _isFoodPublished(Map<String, dynamic> data) {
  const keys = [
    'isPublished',
    'published',
    'publish',
    'is_public',
    'isVisible',
    'visible',
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const List<String> _docIds = [
    'AdminCommission',
    'CODSettings',
    'ContactUs',
    'DeliveryCharge',
    'DineinForRestaurant',
    'DriverNearBy',
    'driver_incentive_rules',
    'MEzIir0oeVNvVU70xF7w',
    'RestaurantNearBy',
    'Version',
    'placeHolderImage',
    'privacyPolicy',
    'referral_amount',
    'restaurant',
    'specialDiscountOffer',
    'story',
    'termsAndConditions',
    'walletSettings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: EdgeInsets.all(12),
        itemCount: _docIds.length + 16,
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _WarningBanner();
          }
          if (index == 1) {
            return const _OrderSoundToggleTile();
          }
          if (index == 2) {
            return _NotificationManagementTile();
          }
          if (index == 3) {
            return _HappyHourSettingsTile();
          }
          if (index == 4) {
            return _FirstOrderCouponSettingsTile();
          }
          if (index == 5) {
            return _NewUserPromoSettingsTile();
          }
          if (index == 6) {
            return _ReferralSettingsTile();
          }
          if (index == 7) {
            return _LoyaltySettingsTile();
          }
          if (index == 8) {
            return const _GiftCardSettingsTile();
          }
          if (index == 9) {
            return _UsersTile();
          }
          if (index == 10) {
            return _CustomerRepeatRateTile();
          }
          if (index == 11) {
            return _AssignmentLogTile();
          }
          if (index == 12) {
            return _DeliveryZoneSettingsTile();
          }
          if (index == 13) {
            return const _RiderTimeSettingsTile();
          }
          if (index == 14) {
            return const _DispatchConfigTile();
          }
          if (index == 15) {
            return const _PautosSettingsTile();
          }
          final String docId = _docIds[index - 16];
          return _SettingsDocTile(collection: 'settings', docId: docId);
        },
      ),
    );
  }
}

class _OrderSoundToggleTile extends StatefulWidget {
  const _OrderSoundToggleTile();

  @override
  State<_OrderSoundToggleTile> createState() => _OrderSoundToggleTileState();
}

class _OrderSoundToggleTileState extends State<_OrderSoundToggleTile> {
  bool _loading = true;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await OrderSoundService.init();
      if (!mounted) return;
      setState(() {
        _enabled = OrderSoundService.isEnabled;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _loading
        ? 'Loading...'
        : 'Plays a short sound when a new order arrives (web may require a click to enable audio).';

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: _loading
                ? null
                : (v) async {
                    setState(() {
                      _enabled = v;
                      _error = null;
                    });
                    try {
                      await OrderSoundService.setEnabled(v);
                      if (v) {
                        // Called from a user gesture → unlocks web audio.
                        await OrderSoundService.playTest();
                      }
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _error = '$e';
                      });
                    }
                  },
            secondary: const Icon(Icons.volume_up, color: Colors.orange),
            title: const Text('Order sound alerts'),
            subtitle: Text(subtitle),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText.rich(
                TextSpan(
                  text: 'Error: ',
                  style: const TextStyle(color: Colors.red),
                  children: [
                    TextSpan(
                      text: _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsDocTile extends StatelessWidget {
  final String collection;
  final String docId;

  const _SettingsDocTile({
    required this.collection,
    required this.docId,
  });

  @override
  Widget build(BuildContext context) {
    final DocumentReference<Map<String, dynamic>> docRef =
        FirebaseFirestore.instance.collection(collection).doc(docId);

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, snapshot) {
            Widget trailing;
            String subtitleText = '';
            Map<String, dynamic> data = const {};

            if (snapshot.connectionState == ConnectionState.waiting) {
              trailing = SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            } else if (snapshot.hasError) {
              trailing = Icon(Icons.error, color: Colors.red);
              subtitleText = 'Failed to load';
            } else {
              data = snapshot.data?.data() ?? {};
              trailing = Icon(Icons.chevron_right);
              subtitleText = data.isEmpty
                  ? 'No fields'
                  : '${data.length} field${data.length == 1 ? '' : 's'}';
            }

            return ExpansionTile(
              title: Text(docId),
              subtitle: subtitleText.isEmpty ? null : Text(subtitleText),
              trailing: trailing,
              childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (snapshot.connectionState == ConnectionState.waiting)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (snapshot.hasError)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Error loading document'),
                  )
                else if ((data).isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No fields'),
                  )
                else
                  _EditableFieldsList(docRef: docRef, data: data),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Be careful when adjusting system settings. Changes here affect all application functionality.',
                style: TextStyle(
                    color: Colors.orange[900], fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationManagementTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.notifications_active, color: Colors.orange),
        title: Text('Notification Management'),
        subtitle: Text('Send broadcast notifications to all customers'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationManagementPage(),
            ),
          );
        },
      ),
    );
  }
}

class _HappyHourSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.local_offer, color: Colors.orange),
        title: Text('Happy Hour Settings'),
        subtitle: Text('Manage Happy Hour promotional discounts'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const HappyHourSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _FirstOrderCouponSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.card_giftcard, color: Colors.orange),
        title: Text('First Order Coupon'),
        subtitle: Text('Manage auto-applied first order coupon'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FirstOrderCouponSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _NewUserPromoSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.local_offer, color: Colors.orange),
        title: Text('New User Promo'),
        subtitle: Text('Manage new user promotional discount'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NewUserPromoSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _ReferralSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.people, color: Colors.orange),
        title: Text('Referral System'),
        subtitle: Text('Manage referral rewards and wallet balances'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ReferralSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _LoyaltySettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.emoji_events, color: Colors.orange),
        title: Text('Loyalty Program'),
        subtitle: Text('Manage tiers, tokens, and rewards'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const LoyaltySettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _GiftCardSettingsTile extends StatelessWidget {
  const _GiftCardSettingsTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.card_giftcard, color: Colors.orange),
        title: Text('Gift Cards'),
        subtitle: Text('Configure denominations, validity, and delivery'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GiftCardSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _UsersTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.people, color: Colors.orange),
        title: Text('Users'),
        subtitle: Text('View and manage user accounts'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserListPage(),
            ),
          );
        },
      ),
    );
  }
}

class _CustomerRepeatRateTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.repeat, color: Colors.orange),
        title: Text('Customer repeat rate'),
        subtitle: Text('Customer activity / logs'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CustomerRepeatRatePage(),
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentLogTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.bolt, color: Colors.orange),
        title: Text('Assignment log'),
        subtitle: Text('Dispatch assignment history'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssignmentsLogPage(),
            ),
          );
        },
      ),
    );
  }
}

class _DeliveryZoneSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.location_on, color: Colors.orange),
        title: Text('Delivery Zone Settings'),
        subtitle: Text('Service areas, barangays, and rider assignment'),
        trailing: Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DeliveryZoneSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _RiderTimeSettingsTile extends StatelessWidget {
  const _RiderTimeSettingsTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.timer, color: Colors.teal),
        title: const Text('Rider Time Settings'),
        subtitle: const Text(
          'Inactivity timeout, auto-logout, and rider session',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RiderTimeSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _DispatchConfigTile extends StatelessWidget {
  const _DispatchConfigTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(
            Icons.tune, color: Colors.deepPurple),
        title: const Text('Dispatch Configuration'),
        subtitle: const Text(
            'Scoring weights, peak hours, batching'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const DispatchConfigPage(),
            ),
          );
        },
      ),
    );
  }
}

class _PautosSettingsTile extends StatelessWidget {
  const _PautosSettingsTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shopping_bag, color: Colors.orange),
        title: const Text('PAUTOS Settings'),
        subtitle: const Text(
          'Service fee, delivery fee, rider commission',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PautosSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _EditableFieldsList extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> data;

  const _EditableFieldsList({
    required this.docRef,
    required this.data,
  });

  @override
  State<_EditableFieldsList> createState() => _EditableFieldsListState();
}

class _EditableFieldsListState extends State<_EditableFieldsList> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _savingKeys = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          _buildField(context, entry.key, entry.value),
      ],
    );
  }

  Widget _buildField(BuildContext context, String key, dynamic value) {
    if (value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(key, style: TextStyle(fontWeight: FontWeight.w600)),
        value: value,
        onChanged: (v) async {
          await _updateField(context, key, value, v);
        },
      );
    }

    if (value is Timestamp) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(key, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(value.toDate().toString()),
            ),
          ],
        ),
      );
    }

    if (value is Map || value is List) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(key, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(value.toString()),
            ),
          ],
        ),
      );
    }

    // Text or numeric field
    final TextEditingController controller = _controllers.putIfAbsent(
        key, () => TextEditingController(text: '$value'))
      ..text = _controllers[key]?.text.isNotEmpty == true
          ? _controllers[key]!.text
          : '$value';

    final bool isNumeric = value is num;
    final bool isMultiline =
        ('$value').length > 60 || ('$value').contains('\n');
    final bool isSaving = _savingKeys.contains(key);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(key, style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  minLines: isMultiline ? 2 : 1,
                  maxLines: isMultiline ? 6 : 1,
                  keyboardType: isNumeric
                      ? TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixIcon: isSaving
                        ? Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(Icons.save),
                            tooltip: 'Save',
                            onPressed: () async {
                              await _updateField(
                                  context, key, value, controller.text);
                            },
                          ),
                  ),
                  onSubmitted: (_) async {
                    await _updateField(context, key, value, controller.text);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateField(
    BuildContext context,
    String key,
    dynamic oldValue,
    dynamic newRaw,
  ) async {
    dynamic newValue = newRaw;

    // Preserve Firestore field types when updating
    try {
      if (oldValue is bool) {
        newValue = newRaw as bool;
      } else if (oldValue is int) {
        final String text = newRaw.toString().trim();
        newValue = int.tryParse(text);
        if (newValue == null) throw 'Enter a valid integer';
      } else if (oldValue is double) {
        final String text = newRaw.toString().trim();
        newValue = double.tryParse(text);
        if (newValue == null) throw 'Enter a valid number';
      } else if (oldValue is num) {
        final String text = newRaw.toString().trim();
        final double? d = double.tryParse(text);
        if (d == null) throw 'Enter a valid number';
        // Keep integer if no fractional part
        newValue = d % 1 == 0 ? d.toInt() : d;
      } else {
        newValue = newRaw.toString();
      }

      if (newValue == oldValue) {
        return;
      }

      setState(() {
        _savingKeys.add(key);
      });

      await widget.docRef.update({key: newValue});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $key')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update $key: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingKeys.remove(key);
        });
      }
    }
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.mark_email_read),
            tooltip: 'Mark all as read',
            onPressed: () async {
              try {
                await NotificationService.markAllAsRead();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('All notifications marked as read')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to mark as read: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: NotificationService.getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('Failed to load notifications'),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final notifications = snapshot.data?.docs ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You\'ll see important updates here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] ?? false;
              final title = data['title'] ?? 'Notification';
              final message = data['message'] ?? '';
              final createdAt = data['createdAt'] as Timestamp?;
              final type = data['type'] ?? 'info';

              Color getTypeColor() {
                switch (type) {
                  case 'success':
                    return Colors.green;
                  case 'warning':
                    return Colors.orange;
                  case 'error':
                    return Colors.red;
                  case 'note':
                    return Colors.purple;
                  default:
                    return Colors.blue;
                }
              }

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                color: isRead
                    ? Colors.grey[50]
                    : type == 'note'
                        ? Colors.purple[50]
                        : Colors.blue[50],
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: getTypeColor(),
                    child: Icon(
                      _getTypeIcon(type),
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isNotEmpty) Text(message),
                      if (createdAt != null)
                        Text(
                          _formatDate(createdAt.toDate()),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  trailing: isRead
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                  onTap: () async {
                    if (!isRead) {
                      try {
                        await NotificationService.markAsRead(doc.id);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to mark as read')),
                          );
                        }
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      case 'order':
        return Icons.shopping_cart;
      case 'driver':
        return Icons.drive_eta;
      case 'payment':
        return Icons.payment;
      case 'note':
        return Icons.note;
      default:
        return Icons.info;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}

class DailyNotesPage extends StatefulWidget {
  const DailyNotesPage({super.key});

  @override
  State<DailyNotesPage> createState() => _DailyNotesPageState();
}

class _DailyNotesPageState extends State<DailyNotesPage> {
  String selectedDate = DateTime.now().toIso8601String().split('T')[0];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Notes'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            tooltip: 'Add Note',
            onPressed: () {
              _showAddNoteDialog(context);
            },
          ),
          IconButton(
            icon: Icon(Icons.mark_email_read),
            tooltip: 'Mark all as read',
            onPressed: () async {
              try {
                await NotificationService.markAllDailyNotesAsRead(selectedDate);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('All notes marked as read')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to mark as read: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Date: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Text(
                    _formatDisplayDate(selectedDate),
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.date_range),
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(selectedDate),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDate = picked.toIso8601String().split('T')[0];
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          // Notes list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: NotificationService.getDailyNotesStream(selectedDate),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Failed to load notes'),
                        SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final notes = snapshot.data?.docs ?? [];

                if (notes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notes, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No notes for this date',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Add a note to get started',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(8),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final doc = notes[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isRead = data['is_read'] ?? false;
                    final title = data['title'] ?? 'Note';
                    final message = data['message'] ?? '';
                    final createdAt = data['created_at'] as Timestamp?;

                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      color: isRead ? Colors.grey[50] : Colors.purple[50],
                      child: InkWell(
                        onTap: () async {
                          if (!isRead) {
                            try {
                              await NotificationService.markDailyNoteAsRead(
                                  selectedDate, doc.id);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Failed to mark as read')),
                                );
                              }
                            }
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.purple,
                                    child:
                                        Icon(Icons.note, color: Colors.white),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontWeight: isRead
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (message.isNotEmpty) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            message,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                        if (createdAt != null) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            _formatDate(createdAt.toDate()),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isRead)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.purple,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          if (value == 'mark_read' && !isRead) {
                                            try {
                                              await NotificationService
                                                  .markDailyNoteAsRead(
                                                      selectedDate, doc.id);
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'Failed to mark as read')),
                                                );
                                              }
                                            }
                                          } else if (value == 'delete') {
                                            final bool? confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: Text('Delete Note'),
                                                content: Text(
                                                    'Are you sure you want to delete this note?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(context)
                                                            .pop(false),
                                                    child: Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(context)
                                                            .pop(true),
                                                    child: Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              try {
                                                await NotificationService
                                                    .deleteDailyNote(
                                                        selectedDate, doc.id);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Note deleted')),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Failed to delete note')),
                                                  );
                                                }
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (!isRead)
                                            PopupMenuItem(
                                              value: 'mark_read',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.mark_email_read),
                                                  SizedBox(width: 8),
                                                  Text('Mark as read'),
                                                ],
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // Add reaction buttons
                              if (MyAppState.currentUser != null) ...[
                                SizedBox(height: 12),
                                ReactionButtons(
                                  date: selectedDate,
                                  noteId: doc.id,
                                  currentUserId: MyAppState.currentUser!.userID,
                                  currentUserName:
                                      MyAppState.currentUser!.fullName(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.note_add, color: Colors.orange),
              SizedBox(width: 8),
              Text('Add Note'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${_formatDisplayDate(selectedDate)}',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: 'Enter note title',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: InputDecoration(
                    labelText: 'Content',
                    hintText: 'Enter note content',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a title')),
                  );
                  return;
                }
                if (contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter content')),
                  );
                  return;
                }

                try {
                  await NotificationService.createDailyNote(
                    title: titleController.text.trim(),
                    message: contentController.text.trim(),
                    date: selectedDate,
                  );

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Note created successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to create note: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text('Create Note'),
            ),
          ],
        );
      },
    );
  }

  String _formatDisplayDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}

class _TodaysOrdersCard extends StatelessWidget {
  const _TodaysOrdersCard();

  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay =
        DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Today's Orders",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Today's Orders",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.error, color: Colors.red),
                ],
              ),
            ),
          );
        }

        final orders = snapshot.data?.docs ?? [];
        final orderCount = orders.length;
        final rejectedCount = orders.where((doc) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status']?.toString().toLowerCase() ?? '';
            return status == 'order rejected' || status == 'driver rejected';
          } catch (e) {
            return false;
          }
        }).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Orders",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '$orderCount ${orderCount == 1 ? 'Order' : 'Orders'} Today',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      if (rejectedCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$rejectedCount Rejected',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
