import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/analytics_helper.dart';
import 'package:foodie_restaurant/utils/date_utils.dart' as app_date_utils;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

Future<void> showExportOrdersSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ExportOrdersSheet(),
  );
}

class _ExportOrdersSheet extends StatefulWidget {
  @override
  State<_ExportOrdersSheet> createState() => _ExportOrdersSheetState();
}

class _ExportOrdersSheetState extends State<_ExportOrdersSheet> {
  String _datePreset = 'Today';
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _loading = false;

  (DateTime, DateTime) get _dateRange {
    final now = DateTime.now();
    switch (_datePreset) {
      case 'This Week':
        return app_date_utils.DateUtils.getThisWeekRange();
      case 'This Month':
        return app_date_utils.DateUtils.getThisMonthRange();
      case 'Custom':
        if (_customStart != null && _customEnd != null) {
          return (_customStart!, _customEnd!);
        }
        return (now, now);
      default:
        return app_date_utils.DateUtils.getTodayRange();
    }
  }

  Future<List<OrderModel>> _fetchOrders() async {
    final vid = MyAppState.currentUser?.vendorID;
    if (vid == null) return [];
    final (start, end) = _dateRange;
    return FireStoreUtils.getOrdersInDateRange(vid, start, end);
  }

  Future<void> _exportCsv() async {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    EasyLoading.show();
    try {
      final orders = await _fetchOrders();
      if (orders.isEmpty) {
        if (mounted) showAlertDialog(context, 'No Data', 'No orders in this range.', false);
        return;
      }
      final csv = await FireStoreUtils.exportOrdersToCsv(orders);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/orders_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) showAlertDialog(context, 'Export Failed', e.toString(), false);
    } finally {
      EasyLoading.dismiss();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    EasyLoading.show();
    try {
      final orders = await _fetchOrders();
      if (orders.isEmpty) {
        if (mounted) showAlertDialog(context, 'No Data', 'No orders in this range.', false);
        return;
      }
      double totalRevenue = 0;
      final orderTotals = <OrderModel, double>{};
      for (final o in orders.take(50)) {
        final t = await AnalyticsHelper.calculateOrderNetTotal(o);
        totalRevenue += t;
        orderTotals[o] = t;
      }
      for (final o in orders.skip(50)) {
        totalRevenue += await AnalyticsHelper.calculateOrderNetTotal(o);
      }
      final (start, end) = _dateRange;
      final doc = pw.Document();
      final restaurantName = orders.isNotEmpty ? orders.first.vendor.title : 'Restaurant';

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Orders Summary',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  restaurantName,
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Total Orders: ${orders.length}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  'Total Revenue: \₱${totalRevenue.toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  'Avg Order: \₱${orders.isNotEmpty ? (totalRevenue / orders.length).toStringAsFixed(2) : '0.00'}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 16),
                pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('Order ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('Customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                    ...orderTotals.entries.map((e) {
                      final o = e.key;
                      final total = e.value;
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(o.id.length >= 8 ? o.id.substring(0, 8) : o.id, style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(DateFormat('MM/dd HH:mm').format(o.createdAt.toDate()), style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('${o.author.firstName} ${o.author.lastName}', style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(o.status, style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('\₱${total.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final output = await doc.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/orders_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(output);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) showAlertDialog(context, 'Export Failed', e.toString(), false);
    } finally {
      EasyLoading.dismiss();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printSummary() async {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    EasyLoading.show();
    try {
      final orders = await _fetchOrders();
      if (orders.isEmpty) {
        if (mounted) showAlertDialog(context, 'No Data', 'No orders in this range.', false);
        return;
      }
      final status = await PrintBluetoothThermal.connectionStatus;
      if (status != true) {
        if (mounted) showAlertDialog(context, 'Not Connected', 'Please connect to a printer first.', false);
        return;
      }
      double totalRevenue = 0;
      for (final o in orders) {
        totalRevenue += await AnalyticsHelper.calculateOrderNetTotal(o);
      }
      final (start, end) = _dateRange;
      final CapabilityProfile profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];
      bytes += generator.text('Orders Summary', styles: const PosStyles(align: PosAlign.center, bold: true), linesAfter: 1);
      bytes += generator.text('${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();
      bytes += generator.text('Total Orders: ${orders.length}', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text('Total Revenue: \₱${totalRevenue.toStringAsFixed(2)}', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.hr();
      for (final o in orders.take(30)) {
        final t = await AnalyticsHelper.calculateOrderNetTotal(o);
        bytes += generator.text('${o.id.substring(0, 8)} \₱${t.toStringAsFixed(2)}', styles: const PosStyles(align: PosAlign.left));
      }
      bytes += generator.hr();
      bytes += generator.text('Thank you!', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.cut();
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      if (result == true && mounted) {
        showAlertDialog(context, 'Success', 'Summary printed successfully.', true);
      } else if (mounted) {
        showAlertDialog(context, 'Error', 'Failed to print.', false);
      }
    } catch (e) {
      if (mounted) showAlertDialog(context, 'Print Failed', e.toString(), false);
    } finally {
      EasyLoading.dismiss();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: dark ? const Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Export Orders',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: dark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ['Today', 'This Week', 'This Month', 'Custom'].map((p) {
                final sel = _datePreset == p;
                return FilterChip(
                  label: Text(p),
                  selected: sel,
                  onSelected: (_) => setState(() => _datePreset = p),
                );
              }).toList(),
            ),
            if (_datePreset == 'Custom') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _customStart ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _customStart = d);
                    },
                    child: Text(_customStart != null ? DateFormat('MMM d').format(_customStart!) : 'Start'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _customEnd ?? DateTime.now(),
                        firstDate: _customStart ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _customEnd = d);
                    },
                    child: Text(_customEnd != null ? DateFormat('MMM d').format(_customEnd!) : 'End'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportCsv,
                      icon: const Icon(Icons.table_chart),
                      label: const Text('CSV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _printSummary,
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
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
