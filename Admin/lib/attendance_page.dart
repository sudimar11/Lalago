import 'package:flutter/material.dart';
import 'package:brgy/services/attendance_service.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  List<AttendanceRiderSummary> _riders = [];
  List<AttendanceRiderSummary> _filtered = [];
  bool _isLoading = true;
  String? _error;
  String _nameQuery = '';
  String _statusFilter = 'all';
  bool _activeTodayOnly = false;
  String _rangeStart = '';
  String _rangeEnd = '';
  Map<String, AttendanceRangeSummary> _rangeSummaryMap = {};
  bool _rangeLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRiders();
    _applyThisMonth();
  }

  Future<void> _loadRiders() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final riders = await AttendanceService.fetchRiders();
      setState(() {
        _riders = riders;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load riders: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _applyLast30Days() async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 29));
    await _loadRange(_formatDate(start), _formatDate(end));
  }

  Future<void> _applyThisMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    await _loadRange(_formatDate(start), _formatDate(now));
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final start = _rangeStart.isNotEmpty ? _parseDate(_rangeStart) ?? now : now.subtract(const Duration(days: 29));
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: start,
        end: _rangeEnd.isNotEmpty ? _parseDate(_rangeEnd) ?? now : now,
      ),
    );
    if (pickedRange == null) return;
    await _loadRange(
        _formatDate(pickedRange.start), _formatDate(pickedRange.end));
  }

  DateTime? _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  Future<void> _loadRange(String startDate, String endDate) async {
    setState(() {
      _rangeLoading = true;
      _rangeStart = startDate;
      _rangeEnd = endDate;
    });
    try {
      final map = await AttendanceService.fetchAttendanceStatusForDateRange(
        startDate,
        endDate,
      );
      if (mounted) {
        setState(() {
          _rangeSummaryMap = map;
          _rangeLoading = false;
        });
      }
    } catch (e, st) {
      // Firestore index errors include a clickable URL - log to console
      final fullError = '$e\n$st';
      final uriMatch = RegExp(
        r'https://console\.firebase\.google\.com/[^\s\)\]]+',
      ).firstMatch(fullError);
      if (uriMatch != null) {
        print('[Attendance] Create Firestore index (click to open):');
        print(uriMatch.group(0));
      }
      if (mounted) {
        setState(() {
          _rangeSummaryMap = {};
          _rangeLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load range: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearDateRange() {
    setState(() {
      _rangeStart = '';
      _rangeEnd = '';
      _rangeSummaryMap = {};
    });
  }

  void _applyFilters() {
    final query = _nameQuery.toLowerCase().trim();
    _filtered = _riders.where((rider) {
      final matchesName =
          query.isEmpty || rider.name.toLowerCase().contains(query);
      final matchesStatus = _statusFilter == 'all' ||
          rider.attendanceStatus == _statusFilter ||
          (rider.suspended && _statusFilter == 'suspended');
      final matchesActiveToday =
          !_activeTodayOnly || rider.activeToday;
      return matchesName && matchesStatus && matchesActiveToday;
    }).toList();
  }

  Future<void> _showRiderDetails(AttendanceRiderSummary rider) async {
    final records =
        await AttendanceService.fetchAttendanceHistory(rider.riderId);
    if (!mounted) return;

    final displayStatus =
        rider.suspended ? 'suspended' : rider.attendanceStatus;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(rider.name),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusRow('Checked in today', rider.activeToday ? 'Yes' : 'No'),
                _statusRow('Last Active', rider.lastActiveDate),
                _statusRow(
                  'Consecutive Absences',
                  rider.consecutiveAbsenceCount.toString(),
                ),
                _statusRow('Status', displayStatus),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent Attendance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (records.isEmpty)
                  const Text('No attendance records yet.')
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return ListTile(
                          dense: true,
                          title: Text(record.date),
                          subtitle: Text(
                            'Status: ${record.status} '
                            '| ${record.attendanceStatus}',
                          ),
                          trailing: Text(
                            'Absences: ${record.consecutiveAbsenceCount}',
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemCount: records.length,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showStatusDialog(rider);
              },
              child: const Text('Update Status'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showStatusDialog(AttendanceRiderSummary rider) async {
    String selectedStatus = rider.attendanceStatus;
    final reasonController = TextEditingController();
    bool resetAbsences = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Update ${rider.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    items: const [
                      DropdownMenuItem(
                        value: 'active',
                        child: Text('Active'),
                      ),
                      DropdownMenuItem(
                        value: 'warned',
                        child: Text('Warned'),
                      ),
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspended'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedStatus = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Status',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: resetAbsences,
                    onChanged: (value) {
                      setDialogState(() {
                        resetAbsences = value == true;
                      });
                    },
                    title: const Text(
                      'Reset absence count and warning flags',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (reasonController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reason is required.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    await AttendanceService.applyManualStatusChange(
      riderId: rider.riderId,
      newStatus: selectedStatus,
      reason: reasonController.text.trim(),
      resetAbsences: resetAbsences,
    );

    await _loadRiders();
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Text(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Matches Rider app tiers: Excellent (≥90), Good (≥75), Fair (≥60), Needs Improvement (<60).
  String _performanceLabel(double score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 60) return 'Fair';
    return 'Needs Improvement';
  }

  Color _performanceColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.orange;
    if (score >= 60) return Colors.amber;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Filter by rider name',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _nameQuery = value;
                        _applyFilters();
                      });
                    },
                    ),
                  ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'warned', child: Text('Warned')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _statusFilter = value;
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Active today (checked in)'),
                  selected: _activeTodayOnly,
                  onSelected: (selected) {
                    setState(() {
                      _activeTodayOnly = selected;
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _rangeLoading ? null : _applyLast30Days,
                  child: const Text('Last 30 days'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _rangeLoading ? null : _applyThisMonth,
                  child: const Text('This month'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _rangeLoading ? null : _pickDateRange,
                  child: const Text('Pick range'),
                ),
                if (_rangeStart.isNotEmpty && _rangeEnd.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('$_rangeStart to $_rangeEnd', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearDateRange,
                    tooltip: 'Clear range',
                  ),
                ],
              ],
            ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(child: Text(_error!)),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return _AttendanceTable(
                      riders: _filtered,
                      rangeSummaryMap: _rangeSummaryMap,
                      hasDateRange:
                          _rangeStart.isNotEmpty && _rangeEnd.isNotEmpty,
                      performanceLabel: _performanceLabel,
                      performanceColor: _performanceColor,
                      onRiderTap: _showRiderDetails,
                      viewportWidth: constraints.maxWidth,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Table layout with column headers for easy scanning.
class _AttendanceTable extends StatelessWidget {
  const _AttendanceTable({
    required this.riders,
    required this.rangeSummaryMap,
    required this.hasDateRange,
    required this.performanceLabel,
    required this.performanceColor,
    required this.onRiderTap,
    this.viewportWidth,
  });

  final List<AttendanceRiderSummary> riders;
  final Map<String, AttendanceRangeSummary> rangeSummaryMap;
  final bool hasDateRange;
  final String Function(double) performanceLabel;
  final Color Function(double) performanceColor;
  final void Function(AttendanceRiderSummary) onRiderTap;
  final double? viewportWidth;

  static const double _colName = 160;
  static const double _colLastActive = 110;
  static const double _colLastCheckIn = 115;
  static const double _colAbsences = 72;
  static const double _colPresent = 72;
  static const double _colPerformance = 140;
  static const double _colPeriod = 180;
  static const double _colStatus = 95;
  static const double _cellPadding = 12;
  static const double _tableMinWidth = _colName + _colLastActive +
      _colLastCheckIn + _colAbsences + _colPresent + _colPerformance +
      _colPeriod + _colStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = viewportWidth != null && viewportWidth! > _tableMinWidth
        ? viewportWidth!
        : _tableMinWidth;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Table(
            columnWidths: {
              0: const FlexColumnWidth(1),
              1: const FixedColumnWidth(_colLastActive),
              2: const FixedColumnWidth(_colLastCheckIn),
              3: const FixedColumnWidth(_colAbsences),
              4: const FixedColumnWidth(_colPresent),
              5: const FixedColumnWidth(_colPerformance),
              6: const FlexColumnWidth(1),
              7: const FixedColumnWidth(_colStatus),
            },
          border: TableBorder(
            horizontalInside: BorderSide(color: theme.dividerColor),
            verticalInside: BorderSide(color: theme.dividerColor),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
              children: [
                _headerCell(context, 'Name'),
                _headerCell(context, 'Last active'),
                _headerCell(context, 'Last check-in'),
                _headerCell(context, 'Absences'),
                _headerCell(context, 'Present'),
                _headerCell(context, 'Performance'),
                _headerCell(context, hasDateRange ? 'Period' : '—'),
                _headerCell(context, 'Status'),
              ],
            ),
            ...riders.map((rider) => _dataRow(context, rider, theme)),
          ],
        ),
        ),
      ),
    );
  }

  /// Today's date + time when rider has checked in today; otherwise "—".
  String _lastCheckInDisplay(String timeOnly) {
    if (timeOnly.isEmpty) return '—';
    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return '$d $timeOnly';
  }

  Widget _headerCell(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _cellPadding,
        vertical: 10,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  TableRow _dataRow(
    BuildContext context,
    AttendanceRiderSummary rider,
    ThemeData theme,
  ) {
    // Status column: Active when checked in today, Not Active otherwise.
    final displayStatus = rider.activeToday ? 'Active' : 'Not Active';
    String periodText = '—';
    int absencesDisplay = rider.consecutiveAbsenceCount;
    String presentDisplay = '—';
    if (hasDateRange) {
      final summary = rangeSummaryMap[rider.riderId];
      periodText = summary != null
          ? summary.toDisplayString()
          : 'No records';
      if (summary != null) {
        absencesDisplay = summary.absentDays;
        presentDisplay = summary.presentDays.toString();
      }
    }

    final onTap = () => onRiderTap(rider);
    return TableRow(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? theme.colorScheme.surface
            : null,
      ),
      children: [
        _cellText(context, rider.name, onTap: onTap),
        _cellText(
          context,
          rider.lastActiveDate.isEmpty ? '—' : rider.lastActiveDate,
          onTap: onTap,
        ),
        _cellText(
          context,
          _lastCheckInDisplay(rider.lastCheckedInTime),
          onTap: onTap,
        ),
        _cellText(
          context,
          absencesDisplay.toString(),
          onTap: onTap,
        ),
        _cellText(context, presentDisplay, onTap: onTap),
        _cellChild(
          context,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: performanceColor(rider.performance).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${rider.performance.toStringAsFixed(0)}% '
              '(${performanceLabel(rider.performance)})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: performanceColor(rider.performance),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          onTap: onTap,
        ),
        _cellText(context, periodText, onTap: onTap),
        _cellText(
          context,
          displayStatus,
          onTap: onTap,
          color: rider.activeToday ? Colors.green : Colors.grey,
        ),
      ],
    );
  }

  Widget _cellText(
    BuildContext context,
    String text, {
    VoidCallback? onTap,
    Color? color,
  }) {
    final style = color != null
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          )
        : Theme.of(context).textTheme.bodyMedium;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _cellPadding,
          vertical: 10,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ),
    );
  }

  Widget _cellChild(
    BuildContext context,
    Widget child, {
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _cellPadding,
        vertical: 8,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
    if (onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }
    return content;
  }
}
