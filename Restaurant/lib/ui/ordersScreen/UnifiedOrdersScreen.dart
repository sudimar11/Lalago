import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/CurrencyModel.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/services/pushnotification.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/ui/customer/CustomerHistoryScreen.dart';
import 'package:foodie_restaurant/ui/order_acceptance_screen.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrderDetailsScreen.dart';
import 'package:foodie_restaurant/ui/ordersScreen/ExportOrdersBottomSheet.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrderFilterBottomSheet.dart';
import 'package:foodie_restaurant/utils/analytics_helper.dart';
import 'package:foodie_restaurant/utils/date_utils.dart' as app_date_utils;
import 'package:foodie_restaurant/utils/order_utils.dart';

enum OrdersTab { active, completed, all }

class UnifiedOrdersScreen extends StatefulWidget {
  final OrdersTab initialTab;

  const UnifiedOrdersScreen({Key? key, this.initialTab = OrdersTab.active})
      : super(key: key);

  @override
  UnifiedOrdersScreenState createState() => UnifiedOrdersScreenState();
}

class UnifiedOrdersScreenState extends State<UnifiedOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  FireStoreUtils _fireStoreUtils = FireStoreUtils();

  Stream<List<OrderModel>> ordersStream = Stream.empty();
  late Stream<List<OrderModel>> completedOrdersStream;
  bool isLoading = true;
  DateTime selectedDate = DateTime.now();

  Set<String> _previousOrderIds = {};
  bool _acceptanceScreenPushed = false;
  String? selectedTime;
  Timer? _soundLoopTimer;
  bool isSoundLooping = false;
  final audioPlayer = AudioPlayer(playerId: "orders_player");
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  List<OrderModel> _allOrders = [];
  DocumentSnapshot? _lastAllOrdersDoc;
  bool _allOrdersLoading = false;
  bool _allOrdersHasMore = true;

  String _searchQuery = '';
  Timer? _searchDebounce;
  final _searchController = TextEditingController();
  OrderFilterState _filterState = const OrderFilterState();

  static Future<List<OrderModel>> _applyFiltersAndSearch(
    List<OrderModel> orders,
    String searchQuery,
    OrderFilterState filter, {
    bool applyDateFilter = true,
  }) async {
    var result = orders;
    if (searchQuery.isNotEmpty) {
      result = _filterBySearch(result, searchQuery);
    }
    if (filter.selectedStatuses.isNotEmpty) {
      result = result.where((o) => filter.selectedStatuses.contains(o.status)).toList();
    }
    if (filter.orderTypes.isNotEmpty) {
      result = result.where((o) {
        if (filter.orderTypes.contains('delivery') && o.takeAway != true) return true;
        if (filter.orderTypes.contains('takeaway') && o.takeAway == true) return true;
        return false;
      }).toList();
    }
    if (applyDateFilter) {
      DateTime? rangeStart;
      DateTime? rangeEnd;
      switch (filter.dateRangePreset) {
        case 'Today':
          rangeStart = app_date_utils.DateUtils.startOfToday();
          rangeEnd = app_date_utils.DateUtils.endOfToday();
          break;
        case 'This Week':
          rangeStart = app_date_utils.DateUtils.startOfThisWeek();
          rangeEnd = app_date_utils.DateUtils.endOfThisWeek();
          break;
        case 'This Month':
          rangeStart = app_date_utils.DateUtils.startOfThisMonth();
          rangeEnd = app_date_utils.DateUtils.endOfThisMonth();
          break;
        case 'Custom Range':
          if (filter.customStart != null) rangeStart = filter.customStart;
          if (filter.customEnd != null) {
            rangeEnd = DateTime(
              filter.customEnd!.year,
              filter.customEnd!.month,
              filter.customEnd!.day,
            ).add(const Duration(days: 1));
          }
          break;
      }
      if (rangeStart != null) {
        result = result.where((o) {
          final t = o.createdAt.toDate();
          return t.isAfter(rangeStart!) &&
              (rangeEnd == null || t.isBefore(rangeEnd!));
        }).toList();
      }
    }
    if (filter.minAmount != null || filter.maxAmount != null) {
      final filtered = <OrderModel>[];
      for (final o in result) {
        final total = await AnalyticsHelper.calculateOrderNetTotal(o);
        if (filter.minAmount != null && total < filter.minAmount!) continue;
        if (filter.maxAmount != null && total > filter.maxAmount!) continue;
        filtered.add(o);
      }
      result = filtered;
    }
    return result;
  }

  static List<OrderModel> _filterBySearch(List<OrderModel> orders, String query) {
    if (query.isEmpty) return orders;
    final q = query.toLowerCase().trim();
    final phoneDigits = query.replaceAll(RegExp(r'\D'), '');
    return orders.where((o) {
      if (o.id.toLowerCase().contains(q)) return true;
      final name =
          '${o.author.firstName} ${o.author.lastName}'.toLowerCase();
      if (name.contains(q)) return true;
      if (phoneDigits.isNotEmpty) {
        final p = o.author.phoneNumber.replaceAll(RegExp(r'\D'), '');
        if (p.contains(phoneDigits)) return true;
      }
      return false;
    }).toList();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value.trim());
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _tabController.addListener(_onTabChanged);
    initializeData();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  void switchToTab(OrdersTab tab) {
    _tabController.animateTo(tab.index);
  }

  void showExportSheet() => showExportOrdersSheet(context);

  Future<void> showFilterSheet() async {
    final result = await showOrderFilterBottomSheet(
      context,
      initial: _filterState,
    );
    if (result != null && mounted) {
      setState(() => _filterState = result);
    }
  }

  Future<void> initializeData() async {
    await setCurrency();
    final vendorID = MyAppState.currentUser?.vendorID;
    if (vendorID == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    ordersStream =
        _fireStoreUtils.watchOrdersPlaced(vendorID).asBroadcastStream();
    ordersStream.listen(
      (orders) {
        final currentIds = orders.map((o) => o.id).toSet();
        final newIds = currentIds.difference(_previousOrderIds);
        if (newIds.isNotEmpty) {
          _startSoundLoop();
          final newPlaced = orders
              .where((o) =>
                  o.status == ORDER_STATUS_PLACED && newIds.contains(o.id))
              .toList();
          if (newPlaced.isNotEmpty && !_acceptanceScreenPushed && mounted) {
            _acceptanceScreenPushed = true;
            Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) =>
                        OrderAcceptanceScreen(orderModel: newPlaced.first)))
                .then((_) => _acceptanceScreenPushed = false);
          }
        }
        _previousOrderIds = currentIds;
      },
      onError: (e) => print('Error listening to orders stream: $e'),
    );

    completedOrdersStream = _fireStoreUtils
        .watchCompletedOrdersForDate(vendorID, selectedDate)
        .asBroadcastStream();

    PushNotificationService(_firebaseMessaging).initialise();
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Color(COLOR_PRIMARY),
            onPrimary: Colors.white,
            onSurface: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != selectedDate && mounted) {
      setState(() {
        selectedDate = picked;
        final vendorID = MyAppState.currentUser?.vendorID;
        if (vendorID != null) {
          completedOrdersStream = _fireStoreUtils
              .watchCompletedOrdersForDate(vendorID, picked)
              .asBroadcastStream();
        }
      });
    }
  }

  void _startSoundLoop() {
    if (isSoundLooping) return;
    isSoundLooping = true;
    _soundLoopTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _playSound();
    });
  }

  void _stopSoundLoop() {
    _soundLoopTimer?.cancel();
    isSoundLooping = false;
  }

  Future<void> _playSound() async {
    try {
      final bytes = await rootBundle
          .load('assets/audio/mixkit-happy-bells-notification-937.mp3');
      await audioPlayer.play(BytesSource(bytes.buffer.asUint8List()));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  Future<void> setCurrency() async {
    currencyModel = await FireStoreUtils().getCurrency() ??
        CurrencyModel(
          id: "",
          code: "USD",
          decimal: 2,
          isactive: true,
          name: "US Dollar",
          symbol: "\$",
          symbolatright: false,
        );
  }

  Future<void> _loadAllOrdersPage() async {
    final vendorID = MyAppState.currentUser?.vendorID;
    if (vendorID == null || _allOrdersLoading) {
      return;
    }
    _allOrdersLoading = true;
    if (mounted) setState(() {});

    final wasFirstPage = _lastAllOrdersDoc == null;
    List<OrderModel> orders;
    DocumentSnapshot? lastDoc;
    try {
      final result = await FireStoreUtils.getOrdersPaginated(vendorID,
          limit: 20, startAfter: _lastAllOrdersDoc);
      orders = result.$1;
      lastDoc = result.$2;
    } catch (e, s) {
      if (mounted) setState(() => _allOrdersLoading = false);
      rethrow;
    }
    if (orders.length < 20) _allOrdersHasMore = false;
    _lastAllOrdersDoc = lastDoc;
    final newAllOrders = wasFirstPage ? orders : _allOrders + orders;

    if (mounted) {
      setState(() {
        _allOrders = newAllOrders;
        _allOrdersLoading = false;
      });
    } else {
      _allOrdersLoading = false;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    try {
      _fireStoreUtils.closeOrdersStream();
    } catch (_) {}
    _soundLoopTimer?.cancel();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Color(0XFFFFFFFF),
      appBar: AppBar(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        elevation: 0,
        toolbarHeight: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Color(COLOR_PRIMARY),
          unselectedLabelColor:
              isDarkMode(context) ? Colors.grey : Colors.black54,
          indicatorColor: Color(COLOR_PRIMARY),
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'All Orders'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: RepaintBoundary(
                key: ValueKey<int>(_tabController.index),
                child: _buildTabContent(_tabController.index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(int index) {
    switch (index) {
      case 0:
        return RepaintBoundary(
          child: _ActiveTabContent(
            isLoading: isLoading,
            ordersStream: ordersStream,
            searchQuery: _searchQuery,
            filterState: _filterState,
            audioPlayer: audioPlayer,
            onStopSound: _stopSoundLoop,
            onStartSound: _startSoundLoop,
            selectedTime: selectedTime,
            onSelectedTimeChanged: (v) => setState(() => selectedTime = v),
            fireStoreUtils: _fireStoreUtils,
            onCustomerTap: (customer) {
              final vid = MyAppState.currentUser?.vendorID;
              if (vid != null) {
                push(context,
                    CustomerHistoryScreen(customer: customer, vendorID: vid));
              }
            },
          ),
        );
      case 1:
        return RepaintBoundary(
          child: _CompletedTabContent(
            completedOrdersStream: completedOrdersStream,
            selectedDate: selectedDate,
            onSelectDate: _selectDate,
            searchQuery: _searchQuery,
            filterState: _filterState,
            onCustomerTap: (customer) {
              final vid = MyAppState.currentUser?.vendorID;
              if (vid != null) {
                push(context,
                    CustomerHistoryScreen(customer: customer, vendorID: vid));
              }
            },
          ),
        );
      case 2:
        return RepaintBoundary(
          child: _AllTabContent(
            orders: _allOrders,
            searchQuery: _searchQuery,
            filterState: _filterState,
            hasMore: _allOrdersHasMore,
            isLoading: _allOrdersLoading,
            onLoadMore: _loadAllOrdersPage,
            onInit: () {
              if (_allOrders.isEmpty && !_allOrdersLoading) {
                _loadAllOrdersPage();
              }
            },
            onCustomerTap: (customer) {
              final vid = MyAppState.currentUser?.vendorID;
              if (vid != null) {
                push(context,
                    CustomerHistoryScreen(customer: customer, vendorID: vid));
              }
            },
          ),
        );
      default:
        return RepaintBoundary(
          child: _ActiveTabContent(
            isLoading: isLoading,
            ordersStream: ordersStream,
            searchQuery: _searchQuery,
            filterState: _filterState,
            audioPlayer: audioPlayer,
            onStopSound: _stopSoundLoop,
            onStartSound: _startSoundLoop,
            selectedTime: selectedTime,
            onSelectedTimeChanged: (v) => setState(() => selectedTime = v),
            fireStoreUtils: _fireStoreUtils,
            onCustomerTap: (customer) {
              final vid = MyAppState.currentUser?.vendorID;
              if (vid != null) {
                push(context,
                    CustomerHistoryScreen(customer: customer, vendorID: vid));
              }
            },
          ),
        );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.grey.shade50,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search by order ID, name, or phone',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSearch,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildFilterChips() {
    if (!_filterState.hasActiveFilters) return const SizedBox.shrink();
    final chips = <Widget>[];
    for (final s in _filterState.selectedStatuses) {
      chips.add(FilterChip(
        label: Text('Status: $s'),
        selected: false,
        onSelected: (_) {},
        onDeleted: () {
          setState(() {
            _filterState = _filterState.copyWith(
              selectedStatuses: {..._filterState.selectedStatuses}..remove(s),
            );
          });
        },
      ));
    }
    if (_filterState.dateRangePreset != 'Today') {
      chips.add(FilterChip(
        label: Text('Date: ${_filterState.dateRangePreset}'),
        selected: false,
        onSelected: (_) {},
        onDeleted: () {
          setState(() => _filterState = _filterState.copyWith(
            dateRangePreset: 'Today',
            customStart: null,
            customEnd: null,
          ));
        },
      ));
    }
    if (_filterState.minAmount != null || _filterState.maxAmount != null) {
      final label = _filterState.minAmount != null && _filterState.maxAmount != null
          ? 'Amount: ${_filterState.minAmount}-${_filterState.maxAmount}'
          : _filterState.minAmount != null
              ? 'Min: ${_filterState.minAmount}'
              : 'Max: ${_filterState.maxAmount}';
      chips.add(FilterChip(
        label: Text(label),
        selected: false,
        onSelected: (_) {},
        onDeleted: () {
          setState(() => _filterState = _filterState.copyWith(
            minAmount: null,
            maxAmount: null,
          ));
        },
      ));
    }
    for (final t in _filterState.orderTypes) {
      chips.add(FilterChip(
        label: Text(t == 'delivery' ? 'Delivery' : 'Takeaway'),
        selected: false,
        onSelected: (_) {},
        onDeleted: () {
          setState(() {
            _filterState = _filterState.copyWith(
              orderTypes: {..._filterState.orderTypes}..remove(t),
            );
          });
        },
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: c,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _ActiveTabContent extends StatefulWidget {
  final bool isLoading;
  final Stream<List<OrderModel>> ordersStream;
  final String searchQuery;
  final OrderFilterState filterState;
  final AudioPlayer audioPlayer;
  final VoidCallback onStopSound;
  final VoidCallback onStartSound;
  final String? selectedTime;
  final ValueChanged<String?> onSelectedTimeChanged;
  final FireStoreUtils fireStoreUtils;
  final void Function(User)? onCustomerTap;

  const _ActiveTabContent({
    required this.isLoading,
    required this.ordersStream,
    required this.searchQuery,
    required this.filterState,
    required this.audioPlayer,
    required this.onStopSound,
    required this.onStartSound,
    required this.selectedTime,
    required this.onSelectedTimeChanged,
    required this.fireStoreUtils,
    this.onCustomerTap,
  });

  @override
  State<_ActiveTabContent> createState() => _ActiveTabContentState();
}

class _ActiveTabContentState extends State<_ActiveTabContent> {
  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<OrderModel>>(
      stream: widget.ordersStream,
      initialData: <OrderModel>[],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
              child: Text('Error loading orders. Please try again.'));
        }

        return FutureBuilder<List<OrderModel>>(
          future: UnifiedOrdersScreenState._applyFiltersAndSearch(
            snapshot.data ?? [],
            widget.searchQuery,
            widget.filterState,
          ),
          builder: (context, filterSnap) {
            final rawOrders = snapshot.data ?? <OrderModel>[];
            final orders =
                filterSnap.hasData ? filterSnap.data! : rawOrders;
            return Column(
          children: [
            Expanded(
              child: orders.isEmpty
                  ? showEmptyState(
                      widget.searchQuery.isEmpty
                          ? 'No Orders'
                          : 'No results found',
                      widget.searchQuery.isEmpty
                          ? 'New order requests will show up here'
                          : 'Try a different search')
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: orders.length,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return InkWell(
                          onTap: () async {
                            await widget.audioPlayer.stop();
                            push(context, OrderDetailsScreen(orderModel: order));
                          },
                          child: OrderUtils.buildOrderItem(
                            context,
                            order,
                            index,
                            index > 0 ? orders[index - 1] : null,
                            showActions: true,
                            audioPlayer: widget.audioPlayer,
                            onStopSound: widget.onStopSound,
                            onStartSound: widget.onStartSound,
                            selectedTime: widget.selectedTime,
                            onSelectedTimeChanged: widget.onSelectedTimeChanged,
                            onCustomerTap: widget.onCustomerTap,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
          },
        );
      },
    );
  }

}

class _CompletedTabContent extends StatelessWidget {
  final Stream<List<OrderModel>> completedOrdersStream;
  final DateTime selectedDate;
  final Future<void> Function(BuildContext) onSelectDate;
  final String searchQuery;
  final OrderFilterState filterState;
  final void Function(User)? onCustomerTap;

  const _CompletedTabContent({
    required this.completedOrdersStream,
    required this.selectedDate,
    required this.onSelectDate,
    required this.searchQuery,
    required this.filterState,
    this.onCustomerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, color: Color(COLOR_PRIMARY), size: 20),
              const SizedBox(width: 8),
              Text(
                'Orders for: ${DateFormat('MMM d, yyyy').format(selectedDate)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onSelectDate(context),
                child: Text('Change Date',
                    style: TextStyle(
                        color: Color(COLOR_PRIMARY),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: completedOrdersStream,
            initialData: <OrderModel>[],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                    child: Text(
                        'Error loading completed orders. Please try again.'));
              }
              return FutureBuilder<List<OrderModel>>(
                future: UnifiedOrdersScreenState._applyFiltersAndSearch(
                  snapshot.data ?? [],
                  searchQuery,
                  filterState,
                ),
                builder: (context, filterSnap) {
                  final rawOrders = snapshot.data ?? <OrderModel>[];
                  final orders =
                      filterSnap.hasData ? filterSnap.data! : rawOrders;
                  if (orders.isEmpty) {
                return showEmptyState(
                    searchQuery.isEmpty
                        ? 'No Completed Orders'
                        : 'No results found',
                    searchQuery.isEmpty
                        ? 'No completed orders found'
                        : 'Try a different search');
              }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: orders.length,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return InkWell(
                      onTap: () =>
                          push(context, OrderDetailsScreen(orderModel: order)),
                      child: OrderUtils.buildOrderItem(
                        context,
                        order,
                        index,
                        index > 0 ? orders[index - 1] : null,
                        showActions: false,
                        onCustomerTap: onCustomerTap,
                      ),
                    );
                  },
                );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AllTabContent extends StatefulWidget {
  final List<OrderModel> orders;
  final String searchQuery;
  final OrderFilterState filterState;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final VoidCallback onInit;
  final void Function(User)? onCustomerTap;

  const _AllTabContent({
    required this.orders,
    required this.searchQuery,
    required this.filterState,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    required this.onInit,
    this.onCustomerTap,
  });

  @override
  State<_AllTabContent> createState() => _AllTabContentState();
}

class _AllTabContentState extends State<_AllTabContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onInit());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrderModel>>(
      future: UnifiedOrdersScreenState._applyFiltersAndSearch(
        widget.orders,
        widget.searchQuery,
        widget.filterState,
        applyDateFilter: false,
      ),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            orders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (orders.isEmpty && !widget.isLoading) {
          return showEmptyState(
              widget.searchQuery.isEmpty && !widget.filterState.hasActiveFilters
                  ? 'No Orders'
                  : 'No results found',
              widget.searchQuery.isEmpty && !widget.filterState.hasActiveFilters
                  ? 'Orders will appear here'
                  : 'Try a different search');
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: orders.length + (widget.hasMore ? 1 : 0),
          padding: const EdgeInsets.all(20),
          itemBuilder: (context, index) {
            if (index >= orders.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: widget.isLoading
                      ? const CircularProgressIndicator()
                      : TextButton(
                          onPressed: widget.onLoadMore,
                          child: const Text('Load More'),
                        ),
                ),
              );
            }
            final order = orders[index];
            return InkWell(
              onTap: () =>
                  push(context, OrderDetailsScreen(orderModel: order)),
              child: OrderUtils.buildOrderItem(
                context,
                order,
                index,
                index > 0 ? orders[index - 1] : null,
                showActions: false,
                onCustomerTap: widget.onCustomerTap,
              ),
            );
          },
        );
      },
    );
  }
}
