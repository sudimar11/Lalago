import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/services/helper.dart';

/// Manage incentive rules for driver performance.
class IncentiveRulesScreen extends StatefulWidget {
  const IncentiveRulesScreen({Key? key}) : super(key: key);

  @override
  State<IncentiveRulesScreen> createState() => _IncentiveRulesScreenState();
}

class _IncentiveRulesScreenState extends State<IncentiveRulesScreen> {
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null) return;

    setState(() => _isLoading = true);
    try {
      final snap = await _firestore
          .collection(INCENTIVE_RULES)
          .where('vendorId', isEqualTo: vendorId)
          .get();

      setState(() {
        _rules = snap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addRule() async {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null) return;

    final nameController = TextEditingController();
    final valueController = TextEditingController(text: '90');
    final bonusController = TextEditingController(text: '100');
    String ruleType = 'on_time';
    String operator = '>=';
    String period = 'week';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Add Incentive Rule'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Rule Name',
                      hintText: 'e.g. Top On-Time Bonus',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: ruleType,
                    decoration: const InputDecoration(labelText: 'Metric'),
                    items: const [
                      DropdownMenuItem(
                        value: 'on_time',
                        child: Text('On-time %'),
                      ),
                      DropdownMenuItem(
                        value: 'top_rated',
                        child: Text('Rating'),
                      ),
                      DropdownMenuItem(
                        value: 'acceptance',
                        child: Text('Acceptance Rate'),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => ruleType = v ?? ruleType),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: operator,
                          decoration:
                              const InputDecoration(labelText: 'Operator'),
                          items: const [
                            DropdownMenuItem(value: '>=', child: Text('≥')),
                            DropdownMenuItem(value: '>', child: Text('>')),
                            DropdownMenuItem(value: '<=', child: Text('≤')),
                            DropdownMenuItem(value: '<', child: Text('<')),
                          ],
                          onChanged: (v) =>
                              setDialog(() => operator = v ?? operator),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: valueController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Value'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bonusController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bonus Amount (₱)',
                      hintText: '100',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: period,
                    decoration: const InputDecoration(labelText: 'Period'),
                    items: const [
                      DropdownMenuItem(value: 'week', child: Text('Weekly')),
                      DropdownMenuItem(value: 'month', child: Text('Monthly')),
                    ],
                    onChanged: (v) => setDialog(() => period = v ?? period),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true || nameController.text.trim().isEmpty) return;

    final value = double.tryParse(valueController.text) ?? 90;
    final bonusAmount = double.tryParse(bonusController.text) ?? 100;

    EasyLoading.show(status: 'Saving...');
    try {
      final metric = ruleType == 'on_time'
          ? 'onTimePercentage'
          : ruleType == 'top_rated'
              ? 'customerRating'
              : 'acceptanceRate';
      await _firestore.collection(INCENTIVE_RULES).add({
        'vendorId': vendorId,
        'name': nameController.text.trim(),
        'ruleType': ruleType,
        'condition': {'metric': metric, 'operator': operator, 'value': value},
        'bonusAmount': bonusAmount,
        'period': period,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _loadRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> rule) async {
    final id = rule['id'] as String?;
    if (id == null) return;
    final active = !((rule['active'] as bool?) ?? true);
    try {
      await _firestore.collection(INCENTIVE_RULES).doc(id).update({
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incentive Rules'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      backgroundColor: isDark ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? Center(
                  child: showEmptyState(
                    'No rules yet',
                    'Add a rule to reward drivers based on performance.',
                    isDarkMode: isDark,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rules.length,
                  itemBuilder: (_, i) {
                    final r = _rules[i];
                    final cond = r['condition'] as Map? ?? {};
                    final active = (r['active'] as bool?) ?? true;
                    return Card(
                      color: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
                      child: ListTile(
                        title: Text(
                          (r['name'] ?? '').toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${r['ruleType']} ${cond['operator']} ${cond['value']} → ₱${(r['bonusAmount'] ?? 0)}/${r['period']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        trailing: Switch(
                          value: active,
                          onChanged: (_) => _toggleActive(r),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        backgroundColor: Color(COLOR_PRIMARY),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
