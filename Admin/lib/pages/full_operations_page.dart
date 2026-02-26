import 'package:flutter/material.dart';
import 'package:brgy/order_dispatcher.dart';
import 'package:brgy/restaurants_page.dart';
import 'package:brgy/driverlist.dart';
import 'package:brgy/remittance.dart';
import 'package:brgy/widgets/dashboard_button_card.dart';
import 'package:brgy/orders_today_page.dart';
import 'package:brgy/orders_this_week_page.dart';
import 'package:brgy/total_orders_page.dart';
import 'package:brgy/average_delivery_time_page.dart';
import 'package:brgy/riders_orders_today_page.dart';
import 'package:brgy/riders_orders_weekly_page.dart';
import 'package:brgy/rider_performance_page.dart';
import 'package:brgy/driver_reports_page.dart';
import 'package:brgy/map_page.dart';
import 'package:brgy/attendance_page.dart';
import 'package:brgy/foods_page.dart';
import 'package:brgy/pages/bundles_page.dart';
import 'package:brgy/pages/addons_page.dart';
import 'package:brgy/top_restaurants_orders_today_page.dart';
import 'package:brgy/restaurants_zero_orders_today_page.dart';
import 'package:brgy/restaurant_orders_weekly_page.dart';
import 'package:brgy/restaurant_orders_earning_page.dart';
import 'package:brgy/pages/restaurant_performance_page.dart';
import 'package:brgy/active_customers_page.dart';
import 'package:brgy/inactive_customers_page.dart';
import 'package:brgy/top_buyers_today_page.dart';
import 'package:brgy/pages/customer_suggestions_page.dart';
import 'package:brgy/pages/customer_feedback_page.dart';
import 'package:brgy/confirmed_transactions.dart';
import 'package:brgy/payout.dart';
import 'package:brgy/confirmed_payouts.dart';
import 'package:brgy/payout_remittance_page.dart';
import 'package:brgy/driver_wallet_page.dart';
import 'package:brgy/driver_collection_page.dart';
import 'package:brgy/adddashboard.dart';
import 'package:brgy/pages/ads_management_page.dart';
import 'package:brgy/pages/coupon_management_page.dart';
import 'package:brgy/pages/search_history_page.dart';
import 'package:brgy/pages/search_analytics_dashboard.dart';
import 'package:brgy/pages/click_analytics_dashboard.dart';
import 'package:brgy/pages/recommendation_performance.dart';
import 'package:brgy/analytics_today.dart';
import 'package:brgy/analytics_weekly.dart';
import 'package:brgy/pages/dispatch_analytics_page.dart';
import 'package:brgy/pages/rider_overview_page.dart';

/// Categorized hub for all operations, replacing the expanded dashboard nav.
class FullOperationsPage extends StatelessWidget {
  const FullOperationsPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Operations'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            'Orders & delivery',
            [
              _NavItem('Orders today', Icons.today, () => _push(context, const OrdersTodayPage())),
              _NavItem('Orders this week', Icons.calendar_view_week, () => _push(context, const OrdersThisWeekPage())),
              _NavItem('Total orders', Icons.shopping_cart, () => _push(context, const TotalOrdersPage())),
              _NavItem('Avg delivery time', Icons.timer, () => _push(context, const AverageDeliveryTimePage())),
              _NavItem('Order dispatcher', Icons.local_shipping, () => _push(context, const OrderDispatcherPage())),
            ],
          ),
          _buildSection(
            context,
            'Restaurant management',
            [
              _NavItem('Total restaurants', Icons.storefront, () => _push(context, const RestaurantsPage())),
              _NavItem('Total foods', Icons.fastfood, () => _push(context, const FoodsPage())),
              _NavItem('Bundle deals', Icons.inventory_2, () => _push(context, const BundlesPage())),
              _NavItem('Add-on promos', Icons.add_circle_outline, () => _push(context, const AddonsPage())),
              _NavItem('Restaurant performance', Icons.insights, () => _push(context, const RestaurantPerformancePage())),
              _NavItem('Top restaurants today', Icons.restaurant, () => _push(context, const TopRestaurantsOrdersTodayPage())),
              _NavItem('Zero orders today', Icons.block, () => _push(context, const RestaurantsZeroOrdersTodayPage())),
              _NavItem('Restaurant orders (week)', Icons.restaurant_menu, () => _push(context, const RestaurantOrdersWeeklyPage())),
              _NavItem('Restaurant earnings', Icons.attach_money, () => _push(context, const RestaurantOrdersEarningPage())),
            ],
          ),
          _buildSection(
            context,
            'Rider operations',
            [
              _NavItem('Rider orders today', Icons.local_shipping, () => _push(context, const RidersOrdersTodayPage())),
              _NavItem('Rider overview', Icons.people_outline, () => _push(context, const RiderOverviewPage())),
              _NavItem('Rider orders (week)', Icons.calendar_view_week, () => _push(context, const RidersOrdersWeeklyPage())),
              _NavItem('Rider performance', Icons.bar_chart, () => _push(context, const RiderPerformancePage())),
              _NavItem('Driver reports', Icons.report_problem, () => _push(context, const DriverReportsPage())),
              _NavItem('Active riders (map)', Icons.map, () => _push(context, DriversMapPage())),
              _NavItem('Attendance', Icons.event_note, () => _push(context, const AttendancePage())),
              _NavItem('Driver list', Icons.list_alt, () => _push(context, DriverListPage())),
            ],
          ),
          _buildSection(
            context,
            'Customers',
            [
              _NavItem('Top 10 buyers today', Icons.people_alt, () => _push(context, const TopBuyersTodayPage())),
              _NavItem('Active customers', Icons.person, () => _push(context, const ActiveCustomersPage())),
              _NavItem('Inactive customers', Icons.person_off, () => _push(context, const InactiveCustomersPage())),
              _NavItem('Suggestions', Icons.lightbulb_outline, () => _push(context, const CustomerSuggestionsPage())),
              _NavItem('Feedback', Icons.feedback, () => _push(context, const CustomerFeedbackPage())),
            ],
          ),
          _buildSection(
            context,
            'Finance',
            [
              _NavItem('Remittance', Icons.send, () => _push(context, const RemittancePage())),
              _NavItem('Confirm remittance', Icons.check_circle, () => _push(context, const ConfirmedTransactionsPage())),
              _NavItem('Payout request', Icons.payment, () => _push(context, const PayoutPage())),
              _NavItem('Confirm payout', Icons.verified, () => _push(context, const ConfirmedPayoutsPage())),
              _NavItem('Driver wallet', Icons.account_balance_wallet, () => _push(context, const DriverWalletPage())),
              _NavItem('Payout & remittance', Icons.swap_horiz, () => _push(context, const PayoutRemittancePage())),
              _NavItem('Collect from driver', Icons.money_off, () => _push(context, const DriverCollectionPage())),
            ],
          ),
          _buildSection(
            context,
            'Marketing',
            [
              _NavItem('SMS tool', Icons.sms, () => _push(context, AddDashboard())),
              _NavItem('Ads management', Icons.campaign, () => _push(context, const AdsManagementPage())),
              _NavItem('Coupon management', Icons.local_offer, () => _push(context, const CouponManagementPage())),
            ],
          ),
          _buildSection(
            context,
            'Search & analytics',
            [
              _NavItem('Search history', Icons.search, () => _push(context, const SearchHistoryPage())),
              _NavItem('Search analytics', Icons.analytics, () => _push(context, const SearchAnalyticsDashboard())),
              _NavItem('Click analytics', Icons.touch_app, () => _push(context, const ClickAnalyticsDashboard())),
              _NavItem('Recommendation performance', Icons.insights, () => _push(context, const RecommendationPerformance())),
              _NavItem('Analytics today', Icons.analytics, () => _push(context, const AnalyticsTodayPage())),
              _NavItem('Analytics (week)', Icons.analytics_outlined, () => _push(context, const AnalyticsWeeklyPage())),
              _NavItem('Dispatch analytics', Icons.local_shipping, () => _push(context, const DispatchAnalyticsPage())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_NavItem> items,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          subtitle: Text(
            '${items.length} items',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount =
                    constraints.maxWidth > 600 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: 56,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return DashboardButtonCard(
                      icon: item.icon,
                      label: item.label,
                      onTap: item.onTap,
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
}

class _NavItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  _NavItem(this.label, this.icon, this.onTap);
}
