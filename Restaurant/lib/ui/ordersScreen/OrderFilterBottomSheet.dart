import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/date_utils.dart' as app_date_utils;
import 'package:intl/intl.dart';

class OrderFilterState {
  final Set<String> selectedStatuses;
  final String dateRangePreset;
  final DateTime? customStart;
  final DateTime? customEnd;
  final double? minAmount;
  final double? maxAmount;
  final Set<String> orderTypes;

  const OrderFilterState({
    this.selectedStatuses = const {},
    this.dateRangePreset = 'Today',
    this.customStart,
    this.customEnd,
    this.minAmount,
    this.maxAmount,
    this.orderTypes = const {},
  });

  OrderFilterState copyWith({
    Set<String>? selectedStatuses,
    String? dateRangePreset,
    DateTime? customStart,
    DateTime? customEnd,
    double? minAmount,
    double? maxAmount,
    Set<String>? orderTypes,
  }) =>
      OrderFilterState(
        selectedStatuses: selectedStatuses ?? this.selectedStatuses,
        dateRangePreset: dateRangePreset ?? this.dateRangePreset,
        customStart: customStart ?? this.customStart,
        customEnd: customEnd ?? this.customEnd,
        minAmount: minAmount ?? this.minAmount,
        maxAmount: maxAmount ?? this.maxAmount,
        orderTypes: orderTypes ?? this.orderTypes,
      );

  bool get hasActiveFilters =>
      selectedStatuses.isNotEmpty ||
      dateRangePreset != 'Today' ||
      minAmount != null ||
      maxAmount != null ||
      orderTypes.isNotEmpty;
}

const _statuses = [
  'Order Placed',
  'Order Accepted',
  'Driver Assigned',
  'Driver Accepted',
  'Driver Rejected',
  'Order Shipped',
  'In Transit',
  'Order Completed',
  'Order Delivered',
  'Order Rejected',
];

Future<OrderFilterState?> showOrderFilterBottomSheet(
  BuildContext context, {
  required OrderFilterState initial,
}) async {
  return showModalBottomSheet<OrderFilterState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OrderFilterSheet(initial: initial),
  );
}

class _OrderFilterSheet extends StatefulWidget {
  final OrderFilterState initial;

  const _OrderFilterSheet({required this.initial});

  @override
  State<_OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends State<_OrderFilterSheet> {
  late Set<String> _selectedStatuses;
  late String _dateRangePreset;
  DateTime? _customStart;
  DateTime? _customEnd;
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  late Set<String> _orderTypes;

  @override
  void initState() {
    super.initState();
    _selectedStatuses = Set.from(widget.initial.selectedStatuses);
    _dateRangePreset = widget.initial.dateRangePreset;
    _customStart = widget.initial.customStart;
    _customEnd = widget.initial.customEnd;
    _orderTypes = Set.from(widget.initial.orderTypes);
    if (widget.initial.minAmount != null) {
      _minController.text = widget.initial.minAmount.toString();
    }
    if (widget.initial.maxAmount != null) {
      _maxController.text = widget.initial.maxAmount.toString();
    }
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStart ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
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
    if (picked != null) setState(() => _customStart = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? (_customStart ?? DateTime.now()),
      firstDate: _customStart ?? DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
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
    if (picked != null) setState(() => _customEnd = picked);
  }

  void _apply() {
    final min = double.tryParse(_minController.text.trim());
    final max = double.tryParse(_maxController.text.trim());
    final state = OrderFilterState(
      selectedStatuses: _selectedStatuses,
      dateRangePreset: _dateRangePreset,
      customStart: _customStart,
      customEnd: _customEnd,
      minAmount: min,
      maxAmount: max,
      orderTypes: _orderTypes,
    );
    Navigator.pop(context, state);
  }

  void _clear() {
    setState(() {
      _selectedStatuses = {};
      _dateRangePreset = 'Today';
      _customStart = null;
      _customEnd = null;
      _minController.clear();
      _maxController.clear();
      _orderTypes = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
                TextButton(
                  onPressed: _clear,
                  child: Text(
                    'Clear All',
                    style: TextStyle(color: Color(COLOR_PRIMARY)),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Status'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _statuses.map((s) {
                      final selected = _selectedStatuses.contains(s);
                      return FilterChip(
                        label: Text(s),
                        selected: selected,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (selected) {
                              _selectedStatuses.remove(s);
                            } else {
                              _selectedStatuses.add(s);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Date Range'),
                  ...[
                    'Today',
                    'This Week',
                    'This Month',
                    'Custom Range',
                  ].map((preset) {
                    final sel = _dateRangePreset == preset;
                    return RadioListTile<String>(
                      title: Text(preset),
                      value: preset,
                      groupValue: _dateRangePreset,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _dateRangePreset = v ?? preset);
                      },
                    );
                  }),
                  if (_dateRangePreset == 'Custom Range') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pickStartDate,
                            child: Text(
                              _customStart != null
                                  ? DateFormat('MMM d').format(_customStart!)
                                  : 'Start',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pickEndDate,
                            child: Text(
                              _customEnd != null
                                  ? DateFormat('MMM d').format(_customEnd!)
                                  : 'End',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle('Amount Range'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Min',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Max',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Order Type'),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Delivery'),
                        selected: _orderTypes.contains('delivery'),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_orderTypes.contains('delivery')) {
                              _orderTypes.remove('delivery');
                            } else {
                              _orderTypes.add('delivery');
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      FilterChip(
                        label: const Text('Takeaway'),
                        selected: _orderTypes.contains('takeaway'),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_orderTypes.contains('takeaway')) {
                              _orderTypes.remove('takeaway');
                            } else {
                              _orderTypes.add('takeaway');
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDarkMode(context) ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
