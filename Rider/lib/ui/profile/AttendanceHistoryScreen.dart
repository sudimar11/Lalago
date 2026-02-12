import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/widgets/performance_bar_chart.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({Key? key}) : super(key: key);

  @override
  _AttendanceHistoryScreenState createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  Future<List<Map<String, dynamic>>>? _attendanceRecordsFuture;
  Future<Map<String, double>>? _weeklyPerformanceScoresFuture;
  Future<double>? _currentPerformanceFuture;

  @override
  void initState() {
    super.initState();
    _attendanceRecordsFuture = _fetchAttendanceRecords();
    _loadWeeklyPerformanceData();
  }

  Future<void> _loadWeeklyPerformanceData() async {
    final driverId = MyAppState.currentUser?.userID;
    if (driverId == null || driverId.isEmpty) {
      return;
    }

    final weekDates = _getCurrentWeekDates();
    final mondayDateString = weekDates['monday']!;
    final sundayDateString = weekDates['sunday']!;

    setState(() {
      _weeklyPerformanceScoresFuture = DriverPerformanceService
          .getWeeklyPerformanceScores(
              driverId, mondayDateString, sundayDateString);
      _currentPerformanceFuture =
          DriverPerformanceService.getCurrentPerformance(driverId);
    });
  }

  /// Calculate Monday and Sunday of the current week
  Map<String, String> _getCurrentWeekDates() {
    final now = DateTime.now();
    // Get the weekday (1 = Monday, 7 = Sunday)
    final weekday = now.weekday;
    // Calculate days to subtract to get to Monday
    final daysToMonday = weekday - 1;
    final monday = now.subtract(Duration(days: daysToMonday));
    // Calculate days to add to get to Sunday
    final daysToSunday = 7 - weekday;
    final sunday = now.add(Duration(days: daysToSunday));

    return {
      'monday': DateFormat('yyyy-MM-dd').format(monday),
      'sunday': DateFormat('yyyy-MM-dd').format(sunday),
    };
  }

  Future<List<Map<String, dynamic>>> _fetchAttendanceRecords(
      {bool skipDetection = false}) async {
    try {
      final driverId = MyAppState.currentUser?.userID;
      if (driverId == null || driverId.isEmpty) {
        return [];
      }

      // Detect and mark missing absences before fetching records
      // Skip detection on refresh to avoid repeated calls
      if (!skipDetection) {
        try {
          await DriverPerformanceService.detectAndMarkMissingAbsences(driverId);
        } catch (e) {
          // Handle errors gracefully - don't block UI if detection fails
          print('⚠️ Error during absence detection (non-blocking): $e');
        }
      }

      // Get current week dates (Monday to Sunday)
      final weekDates = _getCurrentWeekDates();
      final mondayDateString = weekDates['monday']!;
      final sundayDateString = weekDates['sunday']!;

      // Query Firestore with date range filters at database level
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(driverId)
          .collection('attendance_history')
          .where('date', isGreaterThanOrEqualTo: mondayDateString)
          .where('date', isLessThanOrEqualTo: sundayDateString)
          .get();

      final records = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        records.add(data);
      }

      // Sort by date (newest first) - date is in 'yyyy-MM-dd' format
      records.sort((a, b) {
        final dateA = a['date'] as String? ?? '';
        final dateB = b['date'] as String? ?? '';
        return dateB.compareTo(dateA); // Descending order
      });

      return records;
    } catch (e) {
      print('❌ Error fetching attendance records: $e');
      return [];
    }
  }

  Future<void> _refreshAttendanceRecords() async {
    setState(() {
      // Skip detection on refresh to avoid repeated calls
      _attendanceRecordsFuture = _fetchAttendanceRecords(skipDetection: true);
    });
    await _attendanceRecordsFuture;
    await _loadWeeklyPerformanceData();
  }

  String _getAttendanceStatus(Map<String, dynamic> record) {
    final isExcused = record['isExcused'] as bool? ?? false;
    final isAbsent = record['isAbsent'] as bool? ?? false;
    final isLate = record['isLate'] as bool? ?? false;
    final isUndertime = record['isUndertime'] as bool? ?? false;
    final isOnTime = record['isOnTime'] as bool? ?? false;
    final workHoursMinutes = record['workHours'] as int? ?? 0;
    final workHours = workHoursMinutes / 60.0;

    // Calculate net performance impact
    double impact = 0.0;

    // Handle excused and absent first (these are exclusive)
    if (isExcused) {
      return 'EXCUSED (0.0 pts)';
    }

    if (isAbsent) {
      impact = DriverPerformanceService.ADJUSTMENT_ABSENT;
      final impactStr = impact >= 0
          ? '+${impact.toStringAsFixed(1)} pts'
          : '${impact.toStringAsFixed(1)} pts';
      return 'ABSENT ($impactStr)';
    }

    // Build composite status from applicable conditions
    final statusParts = <String>[];

    if (isLate) {
      statusParts.add('LATE');
      impact += DriverPerformanceService.ADJUSTMENT_LATE_CHECKIN;
    } else if (isOnTime) {
      statusParts.add('ON-TIME');
      impact += DriverPerformanceService.ADJUSTMENT_ON_TIME_CHECKIN;
    }

    if (isUndertime) {
      statusParts.add('UNDER-TIME');
      impact += DriverPerformanceService.ADJUSTMENT_UNDERTIME;
    }

    // Check for 5-hour bonus
    if (workHours >= 5.0) {
      impact += DriverPerformanceService.ADJUSTMENT_COMPLETE_5_HOURS;
    }

    // Build final status string
    String statusText;
    if (statusParts.isEmpty) {
      statusText = 'UNKNOWN';
    } else if (statusParts.length == 1) {
      statusText = statusParts[0];
      // Use "PRESENT" instead of "ON-TIME" for single status
      if (statusText == 'ON-TIME') {
        statusText = 'PRESENT';
      }
    } else {
      statusText = statusParts.join(' + ');
    }

    // Format impact string
    final impactStr = impact >= 0
        ? '+${impact.toStringAsFixed(1)} pts'
        : '${impact.toStringAsFixed(1)} pts';

    return '$statusText ($impactStr)';
  }

  Color _getStatusColor(String status) {
    // Remove performance impact text for color determination
    final statusWithoutImpact = status.split(' (').first;

    // Check for worst condition (priority order: ABSENT > UNDER-TIME > LATE > PRESENT/ON-TIME > EXCUSED)
    if (statusWithoutImpact.contains('ABSENT')) {
      return Colors.red;
    } else if (statusWithoutImpact.contains('UNDER-TIME')) {
      return Colors.amber;
    } else if (statusWithoutImpact.contains('LATE')) {
      return Colors.orange;
    } else if (statusWithoutImpact.contains('PRESENT') ||
        statusWithoutImpact.contains('ON-TIME')) {
      return Colors.green;
    } else if (statusWithoutImpact.contains('EXCUSED')) {
      return Colors.blue;
    } else {
      return Colors.grey;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('EEE, MMM d, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatHours(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else if (mins > 0) {
      return '${mins}m';
    } else {
      return '0h';
    }
  }

  Map<String, dynamic> _calculateTotals(List<Map<String, dynamic>> records) {
    int totalMinutes = 0;
    int totalAbsences = 0;
    double totalPerformanceImpact = 0.0;

    for (var record in records) {
      final workHoursMinutes = record['workHours'] as int? ?? 0;
      totalMinutes += workHoursMinutes;

      final isAbsent = record['isAbsent'] as bool? ?? false;
      final isExcused = record['isExcused'] as bool? ?? false;
      if (isAbsent && !isExcused) {
        totalAbsences++;
        totalPerformanceImpact += DriverPerformanceService.ADJUSTMENT_ABSENT;
      }
    }

    return {
      'totalHours': totalMinutes,
      'totalAbsences': totalAbsences,
      'totalPerformanceImpact': totalPerformanceImpact,
    };
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      appBar: AppBar(
        centerTitle: true,
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        backgroundColor: Color(COLOR_PRIMARY),
        title: Text(
          'Attendance History',
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAttendanceRecords,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _attendanceRecordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading attendance records',
                          style: TextStyle(
                            fontSize: 18,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: showEmptyState(
                      'No Attendance Records',
                      description:
                          'Your attendance history will appear here once you start checking in.',
                    ),
                  ),
                ],
              );
            }

            // Calculate totals for current week
            final weekTotals = _calculateTotals(records);

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: 1 + records.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<Map<String, double>>(
                        future: _weeklyPerformanceScoresFuture,
                        builder: (context, scoresSnapshot) {
                          return FutureBuilder<double>(
                            future: _currentPerformanceFuture,
                            builder: (context, perfSnapshot) {
                              if (scoresSnapshot.connectionState ==
                                      ConnectionState.waiting ||
                                  perfSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                return const SizedBox.shrink();
                              }

                              final weeklyScores =
                                  scoresSnapshot.data ?? <String, double>{};
                              final currentPerformance =
                                  perfSnapshot.data ?? 100.0;

                              return _buildPerformanceChartCard(
                                context,
                                weeklyScores,
                                currentPerformance,
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildSummaryCard(
                        context,
                        'This Week',
                        weekTotals,
                        Colors.blue,
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }
                return _buildAttendanceCard(context, records[index - 1]);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPerformanceChartCard(
    BuildContext context,
    Map<String, double> weeklyScores,
    double currentPerformance,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weekly Performance Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(COLOR_PRIMARY).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Color(COLOR_PRIMARY), width: 1),
                  ),
                  child: Text(
                    '${currentPerformance.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PerformanceBarChart(
              dailyScores: weeklyScores,
              currentPerformance: currentPerformance,
              isDarkMode: isDarkMode(context),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(context, Colors.green, 'Gain'),
                const SizedBox(width: 16),
                _buildLegendItem(context, Colors.red, 'Loss'),
                const SizedBox(width: 16),
                _buildLegendItem(
                  context,
                  isDarkMode(context)
                      ? Colors.grey.shade600
                      : Colors.grey.shade400,
                  'No Change',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDarkMode(context)
                ? Colors.grey.shade400
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    Map<String, dynamic> totals,
    Color accentColor,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  context,
                  'Total Hours',
                  _formatHours(totals['totalHours'] as int),
                  Icons.access_time,
                  Colors.blue,
                ),
                _buildSummaryItem(
                  context,
                  'Absences',
                  '${totals['totalAbsences']}',
                  Icons.event_busy,
                  Colors.red,
                ),
                _buildSummaryItem(
                  context,
                  'Performance Impact',
                  '${(totals['totalPerformanceImpact'] as double).toStringAsFixed(1)}',
                  Icons.trending_down,
                  Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 28,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDarkMode(context)
                ? Colors.grey.shade400
                : Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final date = record['date'] as String? ?? '';
    final status = _getAttendanceStatus(record);
    final statusColor = _getStatusColor(status);
    final workHoursMinutes = record['workHours'] as int? ?? 0;
    final actualCheckInTime = record['actualCheckInTime'] as String?;
    final actualCheckOutTime = record['actualCheckOutTime'] as String?;
    final isAbsent = record['isAbsent'] as bool? ?? false;
    final isExcused = record['isExcused'] as bool? ?? false;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatDate(date),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1.5),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (actualCheckInTime != null || actualCheckOutTime != null) ...[
              if (actualCheckInTime != null)
                _buildTimeRow(context, 'Check-in', actualCheckInTime),
              if (actualCheckOutTime != null)
                _buildTimeRow(context, 'Check-out', actualCheckOutTime),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: isDarkMode(context)
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Hours Rendered:',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode(context)
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatHours(workHoursMinutes),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            if (isAbsent && !isExcused) ...[
              const SizedBox(height: 12),
              FutureBuilder<int>(
                future: DriverPerformanceService.getConsecutiveAbsenceCount(
                  MyAppState.currentUser?.userID ?? '',
                  date,
                ),
                builder: (context, snapshot) {
                  final consecutiveCount = snapshot.data ?? 0;
                  if (consecutiveCount > 1) {
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You\'ve been absent for $consecutiveCount consecutive days',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.trending_down,
                    size: 16,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Performance Impact:',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode(context)
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DriverPerformanceService.ADJUSTMENT_ABSENT.toStringAsFixed(1)} points',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<String?>(
                future: DriverPerformanceService.getDisputeStatus(
                  MyAppState.currentUser?.userID ?? '',
                  date,
                ),
                builder: (context, snapshot) {
                  final disputeStatus = snapshot.data;
                  if (disputeStatus == null) {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showDisputeDialog(context, date),
                        icon: Icon(Icons.report_problem, size: 16),
                        label: Text('Report Issue'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: BorderSide(color: Colors.orange),
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Dispute Status: ${disputeStatus.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDisputeDialog(BuildContext context, String date) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Absence Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Date: ${_formatDate(date)}'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Please explain the issue...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please provide a reason'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                final driverId = MyAppState.currentUser?.userID;
                if (driverId != null) {
                  await DriverPerformanceService.reportAbsenceIssue(
                    driverId,
                    date,
                    reasonController.text.trim(),
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Issue reported successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Refresh to show dispute status
                  _refreshAttendanceRecords();
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error reporting issue: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow(BuildContext context, String label, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDarkMode(context)
                  ? Colors.grey.shade400
                  : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
