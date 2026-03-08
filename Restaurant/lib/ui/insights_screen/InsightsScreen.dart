import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/Ratingmodel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/forecast_service.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/analytics_helper.dart';
import 'package:foodie_restaurant/utils/date_utils.dart' as app_date_utils;
import 'package:foodie_restaurant/ui/driver_performance/driver_performance_screen.dart';
import 'package:intl/intl.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({Key? key}) : super(key: key);

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _fireStoreUtils = FireStoreUtils();

  DateTime _rangeStart = app_date_utils.DateUtils.startOfToday();
  DateTime _rangeEnd = app_date_utils.DateUtils.endOfToday();
  String _rangeLabel = 'Today';
  bool _isLoading = true;
  List<OrderModel>? _orders;
  String? _error;

  String _forecastRangeLabel = 'Today';
  Map<String, dynamic>? _demandForecast;
  Map<String, dynamic>? _forecastAggregates;
  bool _forecastLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadForecastData();
  }

  Future<void> _loadForecastData() async {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) return;

    setState(() => _forecastLoading = true);
    EasyLoading.show(status: 'Loading forecast...');

    DateTime targetDate;
    switch (_forecastRangeLabel) {
      case 'Tomorrow':
        targetDate = DateTime.now().add(const Duration(days: 1));
        break;
      case 'Next 7 Days':
        targetDate = DateTime.now();
        break;
      default:
        targetDate = DateTime.now();
    }

    try {
      Map<String, dynamic>? forecast;
      Map<String, dynamic>? aggregates;

      if (_forecastRangeLabel == 'Next 7 Days') {
        final end = DateTime.now().add(const Duration(days: 7));
        final forecasts = await ForecastService.getDemandForecastsForRange(
          vendorId,
          targetDate,
          end,
        );
        forecast = forecasts.isNotEmpty ? forecasts.first : null;
      } else {
        forecast = await ForecastService.getDemandForecast(vendorId, targetDate);
      }

      aggregates = await ForecastService.getForecastAggregatesForComparison(
        vendorId,
        targetDate,
      );

      if (mounted) {
        setState(() {
          _demandForecast = forecast;
          _forecastAggregates = aggregates;
          _forecastLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _demandForecast = null;
          _forecastAggregates = null;
          _forecastLoading = false;
        });
      }
    } finally {
      EasyLoading.dismiss();
    }
  }

  void _selectForecastRange(String label) {
    _forecastRangeLabel = label;
    _loadForecastData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final vendorID = MyAppState.currentUser?.vendorID;
    if (vendorID == null || vendorID.isEmpty) {
      setState(() {
        _error = 'No vendor selected';
        _orders = null;
        _isLoading = false;
      });
      return;
    }

    try {
      final result = await FireStoreUtils.getOrdersInDateRange(
        vendorID,
        _rangeStart,
        _rangeEnd,
      );
      if (mounted) {
        setState(() {
          _orders = result;
          _error = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _orders = null;
          _isLoading = false;
        });
      }
    }
  }

  void _selectRange(String label) {
    switch (label) {
      case 'Today':
        _rangeStart = app_date_utils.DateUtils.startOfToday();
        _rangeEnd = app_date_utils.DateUtils.endOfToday();
        break;
      case 'This Week':
        _rangeStart = app_date_utils.DateUtils.startOfThisWeek();
        _rangeEnd = app_date_utils.DateUtils.endOfThisWeek();
        break;
      case 'This Month':
        _rangeStart = app_date_utils.DateUtils.startOfThisMonth();
        _rangeEnd = app_date_utils.DateUtils.endOfThisMonth();
        break;
      default:
        return;
    }
    _rangeLabel = label;
    _loadData();
  }

  Future<void> _selectCustomRange() async {
    final start = await showDatePicker(
      context: context,
      initialDate: _rangeStart,
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
    if (start == null || !mounted) return;

    final end = await showDatePicker(
      context: context,
      initialDate: start.isBefore(_rangeEnd) ? _rangeEnd : start,
      firstDate: start,
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
    if (end == null || !mounted) return;

    if (end.isBefore(start)) return;

    setState(() {
      _rangeStart = DateTime(start.year, start.month, start.day);
      _rangeEnd = DateTime(end.year, end.month, end.day).add(
        const Duration(days: 1),
      );
      _rangeLabel = 'Custom';
    });
    _loadData();
  }

  String _formatAmount(double value) {
    if (currencyModel != null) {
      return amountShow(amount: value.toString());
    }
    return '\$${value.toStringAsFixed(2)}';
  }

  String _getFormattedDateRange() {
    final fmt = DateFormat('MMM d, yyyy');
    final endDisplay = _rangeEnd.subtract(const Duration(seconds: 1));
    return '${fmt.format(_rangeStart)} – ${fmt.format(endDisplay)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = isDarkMode(context);

    return Scaffold(
      backgroundColor: isDark ? Color(COLOR_DARK) : Colors.white,
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadData();
          await _loadForecastData();
        },
        color: Color(COLOR_PRIMARY),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: Color(COLOR_PRIMARY)),
              )
            : _error != null
                ? Center(
                    child: SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDateSelector(isDark),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            _getFormattedDateRange(),
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_orders == null || _orders!.isEmpty)
                          Center(
                            child: showEmptyState(
                              'No orders in this period',
                              'Try selecting a different date range',
                              isDarkMode: isDark,
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildKpiCards(isDark),
                              const SizedBox(height: 12),
                              _buildDriverPerformanceCard(isDark),
                              const SizedBox(height: 20),
                              _buildRevenueChart(isDark),
                              const SizedBox(height: 20),
                              _buildPopularItems(isDark),
                              const SizedBox(height: 20),
                              _buildPeakHoursChart(isDark),
                              const SizedBox(height: 20),
                              _buildStatusPieChart(isDark),
                              const SizedBox(height: 20),
                              _buildOrderTypeBreakdown(isDark),
                              const SizedBox(height: 20),
                              _buildReviewsSection(isDark),
                              const SizedBox(height: 20),
                              _buildDemandForecastsSection(isDark),
                            ],
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildDateSelector(bool isDark) {
    final chips = ['Today', 'This Week', 'This Month'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...chips.map(
            (label) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: _rangeLabel == label,
                onSelected: (_) => _selectRange(label),
                selectedColor: Color(COLOR_PRIMARY).withValues(alpha: 0.3),
                checkmarkColor: Color(COLOR_PRIMARY),
              ),
            ),
          ),
          FilterChip(
            label: Text('Custom'),
            selected: _rangeLabel == 'Custom',
            onSelected: (_) => _selectCustomRange(),
            selectedColor: Color(COLOR_PRIMARY).withValues(alpha: 0.3),
            checkmarkColor: Color(COLOR_PRIMARY),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverPerformanceCard(bool isDark) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DriverPerformanceScreen(),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(COLOR_PRIMARY).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.delivery_dining,
                color: Color(COLOR_PRIMARY),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver Performance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View metrics, leaderboard & incentives',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCards(bool isDark) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Future<Map<String, dynamic>>(() async {
        final revenue = await AnalyticsHelper.calculateTotalRevenue(_orders!);
        final completedCount = _orders!
            .where((o) =>
                o.status == 'Order Completed' ||
                o.status == 'Order Shipped' ||
                o.status == 'Order Delivered' ||
                o.status == 'In Transit')
            .length;
        final avgPrep = await AnalyticsHelper.calculateAveragePrepTime(
          _orders!,
        );
        return <String, dynamic>{
          'revenue': revenue,
          'completedCount': completedCount,
          'avgPrep': avgPrep,
        };
      }),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data ?? {};
        final revenue = (data['revenue'] as double?) ?? 0.0;
        final completedCount = (data['completedCount'] as int?) ?? 0;
        final avgPrep = data['avgPrep'] as double?;

        final cardColor =
            isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white;
        return RepaintBoundary(
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _kpiCard(
              'Total Revenue',
              _formatAmount(revenue),
              FontAwesomeIcons.pesoSign,
              cardColor,
              isDark,
            ),
            _kpiCard(
              'Total Orders',
              '${_orders!.length}',
              Icons.receipt_long,
              cardColor,
              isDark,
            ),
            _kpiCard(
              'Completed Orders',
              '$completedCount',
              Icons.check_circle,
              cardColor,
              isDark,
            ),
            _kpiCard(
              'Avg Prep Time',
              avgPrep != null
                  ? '${avgPrep.toStringAsFixed(1)} min'
                  : 'N/A',
              Icons.schedule,
              cardColor,
              isDark,
            ),
          ],
        ),
      );
      },
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color bgColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Color(COLOR_PRIMARY), size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(bool isDark) {
    return FutureBuilder<Map<String, double>>(
      future: AnalyticsHelper.getRevenueByDate(_orders!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _chartCard(
            'Revenue Trend',
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            isDark,
          );
        }
        final data = snap.data ?? {};
        if (data.isEmpty) {
          return _chartCard(
            'Revenue Trend',
            const SizedBox(
              height: 160,
              child: Center(child: Text('No revenue data')),
            ),
            isDark,
          );
        }
        final sortedDates = data.keys.toList()..sort();
        final spots = <FlSpot>[];
        for (var i = 0; i < sortedDates.length; i++) {
          spots.add(FlSpot(i.toDouble(), data[sortedDates[i]]!));
        }
        final maxY = data.values.fold(
          1.0,
          (a, b) => a > b ? a : b,
        );
        final gridColor =
            isDark ? Colors.grey.shade700 : Colors.grey.shade300;
        return _chartCard(
          'Revenue Trend',
          RepaintBoundary(
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: gridColor,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                        _formatAmount(v),
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (sortedDates.length / 5).ceilToDouble(),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i >= 0 && i < sortedDates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              sortedDates[i].substring(5),
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 9,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: gridColor),
                ),
                minX: 0,
                maxX: (sortedDates.length - 1).toDouble(),
                minY: 0,
                maxY: maxY * 1.1 + 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Color(COLOR_PRIMARY),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Color(COLOR_PRIMARY).withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
          isDark,
        );
      },
    );
  }

  Widget _chartCard(String title, Widget child, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPopularItems(bool isDark) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: AnalyticsHelper.getPopularItems(_orders!, limit: 5),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _chartCard(
            'Popular Items',
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            isDark,
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _chartCard(
            'Popular Items',
            const SizedBox(
              height: 80,
              child: Center(child: Text('No items')),
            ),
            isDark,
          );
        }
        final maxQty = items.isNotEmpty
            ? (items.first['quantity'] as int).toDouble()
            : 1.0;
        return _chartCard(
          'Popular Items',
          Column(
            children: items.map((item) {
              final name = item['name'] as String? ?? 'Unknown';
              final qty = item['quantity'] as int? ?? 0;
              final pct = maxQty > 0 ? (qty / maxQty) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$qty',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(COLOR_PRIMARY),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: pct,
                      backgroundColor: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          isDark,
        );
      },
    );
  }

  Widget _buildPeakHoursChart(bool isDark) {
    final byHour = AnalyticsHelper.getOrdersByHour(_orders!);
    final maxCount = byHour.values.isEmpty
        ? 1
        : byHour.values.reduce((a, b) => a > b ? a : b);
    final gridColor =
        isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final barGroups = List.generate(24, (i) {
      final count = byHour[i] ?? 0;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: maxCount > 0 ? count.toDouble() : 0,
            color: Color(COLOR_PRIMARY),
            width: 12,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    });

    return _chartCard(
      'Peak Hours',
      RepaintBoundary(
        child: SizedBox(
          height: 200,
          child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (maxCount + 1).toDouble(),
            minY: 0,
            barTouchData: BarTouchData(enabled: true),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 3,
                  getTitlesWidget: (v, _) {
                    final h = v.toInt();
                    if (h >= 0 && h < 24) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$h',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, _) => Text(
                    v.toInt().toString(),
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                color: gridColor,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: gridColor),
            ),
            barGroups: barGroups,
          ),
        ),
        ),
      ),
      isDark,
    );
  }

  Widget _buildStatusPieChart(bool isDark) {
    final breakdown = AnalyticsHelper.getStatusBreakdown(_orders!);
    if (breakdown.isEmpty) {
      return _chartCard(
        'Status Breakdown',
        const SizedBox(
          height: 160,
          child: Center(child: Text('No data')),
        ),
        isDark,
      );
    }
    const colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.amber,
    ];
    final total = breakdown.values.fold(0, (a, b) => a + b);
    final sections = breakdown.entries.toList().asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      return PieChartSectionData(
        value: total > 0 ? entry.value.toDouble() : 0,
        title: '${entry.value}',
        color: colors[i % colors.length],
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return _chartCard(
      'Status Breakdown',
      RepaintBoundary(
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  sectionsSpace: 2,
                  centerSpaceRadius: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: breakdown.entries.map((e) {
              final i = breakdown.keys.toList().indexOf(e.key);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    color: colors[i % colors.length],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    e.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ],
              );
              }).toList(),
            ),
          ],
        ),
      ),
      isDark,
    );
  }

  Widget _buildOrderTypeBreakdown(bool isDark) {
    final breakdown = AnalyticsHelper.getOrderTypeBreakdown(_orders!);
    final delivery = breakdown['Delivery'] ?? 0;
    final takeaway = breakdown['Takeaway'] ?? 0;
    final total = delivery + takeaway;
    if (total == 0) {
      return _chartCard(
        'Delivery vs Takeaway',
        const SizedBox(
          height: 60,
          child: Center(child: Text('No data')),
        ),
        isDark,
      );
    }
    return _chartCard(
      'Delivery vs Takeaway',
      Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Icon(Icons.delivery_dining,
                    color: Colors.blue, size: 32),
                const SizedBox(height: 4),
                Text(
                  'Delivery',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  '$delivery',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Icon(Icons.shopping_bag, color: Colors.orange, size: 32),
                const SizedBox(height: 4),
                Text(
                  'Takeaway',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  '$takeaway',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      isDark,
    );
  }

  Widget _buildReviewsSection(bool isDark) {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<RatingModel>>(
      stream: _fireStoreUtils.getReviewsByVendor(vendorId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _chartCard(
            'Reviews',
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            isDark,
          );
        }
        final allReviews = snap.data ?? [];
        final reviews = allReviews.where((r) {
          if (r.status == 'hidden') return false;
          final ts = r.createdAt;
          if (ts == null) return true;
          final dt = ts.toDate();
          return !dt.isBefore(_rangeStart) && !dt.isAfter(_rangeEnd);
        }).toList();

        if (reviews.isEmpty) {
          return _chartCard(
            'Reviews',
            const SizedBox(
              height: 80,
              child: Center(child: Text('No reviews in this period')),
            ),
            isDark,
          );
        }

        final avgRating = reviews
                .map((r) => r.rating ?? 0)
                .reduce((a, b) => a + b) /
            reviews.length;
        final byDay = <String, List<double>>{};
        for (final r in reviews) {
          final ts = r.createdAt;
          if (ts == null) continue;
          final dt = ts.toDate();
          final key =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          byDay.putIfAbsent(key, () => []).add(r.rating ?? 0);
        }
        final sortedDays = byDay.keys.toList()..sort();
        final lineSpots = sortedDays.asMap().entries.map((e) {
          final vals = byDay[e.value]!;
          final dayAvg = vals.isEmpty
              ? 0.0
              : vals.reduce((a, b) => a + b) / vals.length;
          return FlSpot(e.key.toDouble(), dayAvg);
        }).toList();

        final byProduct = <String, List<double>>{};
        for (final r in reviews) {
          final pid = r.productId ?? 'general';
          byProduct.putIfAbsent(pid, () => []).add(r.rating ?? 0);
        }
        final productRows = byProduct.entries.map((e) {
          final avg = e.value.reduce((a, b) => a + b) / e.value.length;
          return MapEntry(e.key, {'avg': avg, 'count': e.value.length});
        }).toList()
          ..sort((a, b) => (b.value['avg']!).compareTo(a.value['avg']!));

        final byStar = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        for (final r in reviews) {
          final star = (r.rating ?? 0).round().clamp(1, 5);
          byStar[star] = (byStar[star] ?? 0) + 1;
        }
        const starColors = [
          Colors.red,
          Colors.orange,
          Colors.amber,
          Colors.lightGreen,
          Colors.green,
        ];
        final pieSections = [1, 2, 3, 4, 5].map((star) {
          final v = byStar[star] ?? 0;
          return PieChartSectionData(
            value: v > 0 ? v.toDouble() : 0.01,
            title: '$v',
            color: starColors[star - 1],
            radius: 40,
            titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
          );
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chartCard(
              'Reviews',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${reviews.length} reviews  •  Avg ${avgRating.toStringAsFixed(1)}★',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (lineSpots.isNotEmpty)
                    SizedBox(
                      height: 140,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          minX: 0,
                          maxX: (lineSpots.length - 1).toDouble(),
                          minY: 0,
                          maxY: 5.5,
                          lineBarsData: [
                            LineChartBarData(
                              spots: lineSpots,
                              isCurved: true,
                              color: Color(COLOR_PRIMARY),
                              barWidth: 2,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Color(COLOR_PRIMARY)
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Rating distribution',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: PieChart(
                            PieChartData(
                              sections: pieSections,
                              sectionsSpace: 2,
                              centerSpaceRadius: 0,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [1, 2, 3, 4, 5].map((star) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    color: starColors[star - 1],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$star★: ${byStar[star] ?? 0}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              isDark,
            ),
            const SizedBox(height: 16),
            _chartCard(
              'Product performance',
              productRows.isEmpty
                  ? const SizedBox(
                      height: 60,
                      child: Center(child: Text('No product data')),
                    )
                  : Column(
                      children: productRows.take(8).map((e) {
                        final pid = e.key.length > 12
                            ? '${e.key.substring(0, 12)}...'
                            : e.key;
                        final avg = (e.value['avg'] as double)
                            .toStringAsFixed(1);
                        final count = e.value['count'] as int;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  pid == 'general' ? 'General' : pid,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$avg★',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(COLOR_PRIMARY),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '($count)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
              isDark,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDemandForecastsSection(bool isDark) {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['Today', 'Tomorrow', 'Next 7 Days'].map((label) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: _forecastRangeLabel == label,
                  onSelected: (_) => _selectForecastRange(label),
                  selectedColor: Color(COLOR_PRIMARY).withValues(alpha: 0.3),
                  checkmarkColor: Color(COLOR_PRIMARY),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (_forecastLoading)
          _chartCard(
            'Demand Forecasts',
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            isDark,
          )
        else if (_demandForecast == null && _forecastAggregates == null)
          _chartCard(
            'Demand Forecasts',
            SizedBox(
              height: 120,
              child: Center(
                child: showEmptyState(
                  'No forecast data',
                  'Forecasts are generated daily. Check back later.',
                  isDarkMode: isDark,
                ),
              ),
            ),
            isDark,
          )
        else
          _buildDemandForecastContent(isDark),
      ],
    );
  }

  Widget _buildDemandForecastContent(bool isDark) {
    final forecast = _demandForecast;
    final aggregates = _forecastAggregates;
    final hourlyPred = forecast?['hourlyPredictions'] as Map<String, dynamic>?;
    final productPred = forecast?['productPredictions'] as Map<String, dynamic>?;

    final predictedSpots = <FlSpot>[];
    final actualSpots = <FlSpot>[];
    double maxY = 1;

    if (hourlyPred != null) {
      for (var h = 0; h < 24; h++) {
        final v = (hourlyPred[ h.toString()] ?? 0) as num;
        predictedSpots.add(FlSpot(h.toDouble(), v.toDouble()));
        if (v.toDouble() > maxY) maxY = v.toDouble();
      }
    }

    if (aggregates != null) {
      final hb = aggregates['hourlyBreakdown'] as Map<String, dynamic>?;
      if (hb != null) {
        for (var h = 0; h < 24; h++) {
          final data = hb[h.toString()] as Map<String, dynamic>?;
          final count = (data?['orderCount'] ?? 0) as num;
          actualSpots.add(FlSpot(h.toDouble(), count.toDouble()));
          if (count.toDouble() > maxY) maxY = count.toDouble();
        }
      }
    }

    final gridColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final hasComparison = actualSpots.any((s) => s.y > 0);

    final productList = <MapEntry<String, dynamic>>[];
    if (productPred != null) {
      for (final e in productPred.entries) {
        final val = e.value;
        if (val is Map) {
          productList.add(MapEntry(e.key, val));
        }
      }
      productList.sort(
        (a, b) =>
            ((b.value as Map)['predictedQty'] as num?)
                ?.compareTo((a.value as Map)['predictedQty'] as num? ?? 0) ??
            0,
      );
    }

    final totalPredicted =
        hourlyPred?.values.fold<int>(0, (s, v) => s + ((v as num?)?.toInt() ?? 0)) ?? 0;
    final peakStart = 18;
    final peakEnd = 20;
    final peakSum = hourlyPred != null
        ? List.generate(peakEnd - peakStart + 1, (i) => peakStart + i)
            .fold<int>(
                0,
                (s, h) =>
                    s +
                    ((hourlyPred[h.toString()] as num?)?.toInt() ?? 0))
        : 0;
    final cooks = peakSum > 30 ? 4 : (peakSum > 15 ? 3 : (peakSum > 5 ? 2 : 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chartCard(
          'Demand Forecasts',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (predictedSpots.isNotEmpty)
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: gridColor,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 4,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}h',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: gridColor),
                      ),
                      minX: 0,
                      maxX: 23,
                      minY: 0,
                      maxY: maxY * 1.1 + 1,
                      lineBarsData: [
                        LineChartBarData(
                          spots: predictedSpots,
                          isCurved: true,
                          color: Color(COLOR_PRIMARY),
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Color(COLOR_PRIMARY).withValues(alpha: 0.15),
                          ),
                        ),
                        if (hasComparison)
                          LineChartBarData(
                            spots: actualSpots,
                            isCurved: true,
                            color: Colors.green,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                          ),
                      ],
                    ),
                  ),
                ),
              if (hasComparison)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        color: Color(COLOR_PRIMARY),
                      ),
                      const SizedBox(width: 4),
                      Text('Predicted', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                      const SizedBox(width: 16),
                      Container(width: 12, height: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('Actual', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                    ],
                  ),
                ),
            ],
          ),
          isDark,
        ),
        const SizedBox(height: 16),
        _chartCard(
          'Staffing recommendation',
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Schedule $cooks cooks between ${peakStart}:00-${peakEnd}:00 based on forecast of $peakSum orders.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          isDark,
        ),
        if (productList.isNotEmpty) ...[
          const SizedBox(height: 16),
          _chartCard(
            'Product demand',
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text('Product', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Predicted', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Level', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600))),
                ],
                rows: productList.take(10).toList().asMap().entries.map((e) {
                  final entry = e.value;
                  final name = (entry.value as Map)['productName'] as String? ?? entry.key;
                  final qty = (entry.value as Map)['predictedQty'] as num? ?? 0;
                  final maxQ = productList.isNotEmpty
                      ? (productList.first.value as Map)['predictedQty'] as num? ?? 1
                      : 1;
                  final pct = maxQ > 0 ? (qty.toDouble() / maxQ.toDouble()) : 0.0;
                  String level;
                  Color levelColor;
                  if (pct >= 0.7) {
                    level = 'High';
                    levelColor = Colors.green;
                  } else if (pct >= 0.4) {
                    level = 'Medium';
                    levelColor = Colors.orange;
                  } else {
                    level = 'Low';
                    levelColor = Colors.blue;
                  }
                  return DataRow(
                    cells: [
                      DataCell(Text(name.length > 20 ? '${name.substring(0, 20)}...' : name, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12))),
                      DataCell(Text('$qty', style: TextStyle(color: Color(COLOR_PRIMARY), fontWeight: FontWeight.w600))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(level, style: TextStyle(color: levelColor, fontSize: 12)),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
            isDark,
          ),
        ],
      ],
    );
  }
}
