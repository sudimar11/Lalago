import 'package:brgy/adddashboard.dart';
import 'package:brgy/login.dart';
import 'package:brgy/userlist.dart';
import 'package:brgy/driverlist.dart';
import 'package:brgy/order_dispatcher.dart';
import 'package:brgy/sales.dart';
import 'package:brgy/main.dart';
import 'package:brgy/customers_page.dart';
import 'package:brgy/restaurants_page.dart';
import 'package:brgy/foods_page.dart';
import 'package:brgy/analytics_today.dart';
import 'package:brgy/analytics_weekly.dart';
import 'package:brgy/riders_orders_today_page.dart';
import 'package:brgy/services/notification_service.dart';
import 'package:brgy/services/group_chat_service.dart';
import 'package:brgy/ui/group_chat/GroupChatScreen.dart';
import 'package:brgy/widgets/reaction_buttons.dart';
import 'package:brgy/widgets/driver_list_dialog.dart';
import 'package:brgy/widgets/dashboard_button_card.dart';
import 'package:brgy/active_buyers_today_page.dart';
import 'package:brgy/active_buyers_this_week_page.dart';
import 'package:brgy/orders_today_page.dart';
import 'package:brgy/orders_this_week_page.dart';
import 'package:brgy/total_orders_page.dart';
import 'package:brgy/average_delivery_time_page.dart';
import 'package:brgy/inactive_customers_page.dart';
import 'package:brgy/active_customers_page.dart';
import 'package:brgy/top_buyers_today_page.dart';
import 'package:brgy/customer_repeat_rate_page.dart';
import 'package:brgy/riders_orders_weekly_page.dart';
import 'package:brgy/top_restaurants_orders_today_page.dart';
import 'package:brgy/restaurants_zero_orders_today_page.dart';
import 'package:brgy/restaurant_orders_weekly_page.dart';
import 'package:brgy/restaurant_orders_earning_page.dart';
import 'package:brgy/driver_reports_page.dart';
import 'package:brgy/remittance.dart';
import 'package:brgy/confirmed_transactions.dart';
import 'package:brgy/payout.dart';
import 'package:brgy/confirmed_payouts.dart';
import 'package:brgy/payout_remittance_page.dart';
import 'package:brgy/driver_suspension.dart';
import 'package:brgy/attendance_page.dart';
import 'package:brgy/pages/ads_management_page.dart';
import 'package:brgy/pages/happy_hour_settings_page.dart';
import 'package:brgy/pages/notification_management_page.dart';
import 'package:brgy/pages/first_order_coupon_settings_page.dart';
import 'package:brgy/pages/coupon_management_page.dart';
import 'package:brgy/pages/new_user_promo_settings_page.dart';
import 'package:brgy/pages/referral_settings_page.dart';
import 'package:brgy/driver_wallet_page.dart';
import 'package:brgy/driver_collection_page.dart';
import 'package:brgy/pages/customer_suggestions_page.dart';
import 'package:brgy/pages/customer_feedback_page.dart';
import 'package:brgy/pages/search_history_page.dart';
import 'package:brgy/map_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'dart:async';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // List of widgets for each core feature screen
  final List<Widget> _screens = [
    DashboardBlankPage(),
    DriverListPage(),
    RecentOrdersPage(), // Recent Orders only (no tabs)
    SalesPage(),
    const GroupChatScreen(),
  ];

  // Handle bottom navigation bar item taps
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LalaGO'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.drive_eta),
            label: 'Drivers',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Orders',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Sales',
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
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey[400],
        backgroundColor: Colors.black,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        onTap: _onItemTapped,
      ),
    );
  }
}

class DashboardBlankPage extends StatefulWidget {
  @override
  State<DashboardBlankPage> createState() => _DashboardBlankPageState();
}

class _DashboardBlankPageState extends State<DashboardBlankPage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Today's Orders Card
            const _TodaysOrdersCard(),
            const SizedBox(height: 16),
            // Customers Section
            Row(
              children: [
                Text(
                  'Customers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.people_alt,
                  label: 'Top 10 Buyers',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TopBuyersTodayPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.repeat,
                  label: 'Customer Repeat Rate',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomerRepeatRatePage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.lightbulb_outline,
                  label: 'Customer Suggestions',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomerSuggestionsPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.feedback,
                  label: 'Customer Feedback',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomerFeedbackPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // Search Section
            Row(
              children: [
                Text(
                  'Search',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.search,
                  label: 'Search History',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchHistoryPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // Riders Section
            Row(
              children: [
                Text(
                  'Riders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.local_shipping,
                  label: 'Riders Orders Weekly',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RidersOrdersWeeklyPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.report_problem,
                  label: 'Driver Reports',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DriverReportsPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.map,
                  label: 'View Active Riders (Live Map)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DriversMapPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.event_note,
                  label: 'Attendance',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AttendancePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // Orders Section
            Row(
              children: [
                Text(
                  'Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.calendar_view_week,
                  label: 'Orders This Week',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const OrdersThisWeekPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.shopping_cart,
                  label: 'Total Orders',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TotalOrdersPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.timer,
                  label: 'Avg Delivery Time',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AverageDeliveryTimePage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.attach_money,
                  label: 'Restaurant Earnings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const RestaurantOrdersEarningPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // Restaurants Section
            Row(
              children: [
                Text(
                  'Restaurants',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.fastfood,
                  label: 'Total Foods',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FoodsPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.storefront,
                  label: 'Total Restaurants',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RestaurantsPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.restaurant,
                  label: 'Top Restaurants Today',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const TopRestaurantsOrdersTodayPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.block,
                  label: 'Zero Orders Today',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const RestaurantsZeroOrdersTodayPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.restaurant_menu,
                  label: 'Restaurant Orders Weekly',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const RestaurantOrdersWeeklyPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // Marketing Section
            Row(
              children: [
                Text(
                  'Marketing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Divider(color: Colors.grey[300], thickness: 1),
            SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: [
                DashboardButtonCard(
                  icon: Icons.campaign,
                  label: 'Ads Management',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdsManagementPage(),
                      ),
                    );
                  },
                ),
                DashboardButtonCard(
                  icon: Icons.local_offer,
                  label: 'Coupon Management',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CouponManagementPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddDashboard(),
                              ),
                            );
                          },
                          icon: Icon(Icons.sms),
                          label: Text('SMS'),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserListPage(),
                              ),
                            );
                          },
                          icon: Icon(Icons.people),
                          label: Text('Users'),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AssignmentsLogPage(),
                              ),
                            );
                          },
                          icon: Icon(Icons.bolt),
                          label: Text(
                            'Assignment',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DailyNotesPage(),
                              ),
                            );
                          },
                          icon: Icon(Icons.notes),
                          label: Text('View Notes'),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DriverSuspensionPage(),
                              ),
                            );
                          },
                          icon: Icon(Icons.block),
                          label: Text('Suspension'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet,
                            color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Financial Management',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RemittancePage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.send),
                            label: Text('Remittance'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ConfirmedTransactionsPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.check_circle),
                            label: Text('Confirm Remittance'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const PayoutPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.payment),
                            label: Text('Payout Request'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ConfirmedPayoutsPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.verified),
                            label: Text('Confirm Payout'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DriverWalletPage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.account_balance_wallet),
                        label: Text('Driver Wallet'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PayoutRemittancePage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.swap_horiz),
                        label: Text('Payout & Remittance'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const DriverCollectionPage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.money_off),
                        label: Text('Collect from Driver'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            // Notes Section
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes, color: Colors.purple),
                        SizedBox(width: 8),
                        Text(
                          "Daily Notes",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DailyNotesPage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.notes),
                        label: Text("View Today's Notes"),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Analytics',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AnalyticsTodayPage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.analytics),
                        label: Text('Analytics Today'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AnalyticsWeeklyPage(),
                            ),
                          );
                        },
                        icon: Icon(Icons.analytics_outlined),
                        label: Text('Weekly Analytics'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        itemCount: _docIds.length + 6,
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _WarningBanner();
          }
          if (index == 1) {
            return _NotificationManagementTile();
          }
          if (index == 2) {
            return _HappyHourSettingsTile();
          }
          if (index == 3) {
            return _FirstOrderCouponSettingsTile();
          }
          if (index == 4) {
            return _NewUserPromoSettingsTile();
          }
          if (index == 5) {
            return _ReferralSettingsTile();
          }
          final String docId = _docIds[index - 6];
          return _SettingsDocTile(collection: 'settings', docId: docId);
        },
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
