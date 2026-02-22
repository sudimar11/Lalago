import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/dispatch_analytics_service.dart';
import 'package:intl/intl.dart';

class DispatchConfigPage extends StatefulWidget {
  const DispatchConfigPage({super.key});

  @override
  State<DispatchConfigPage> createState() =>
      _DispatchConfigPageState();
}

class _DispatchConfigPageState
    extends State<DispatchConfigPage> {
  final _service = DispatchAnalyticsService();
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  double _weightETA = 0.35;
  double _weightWorkload = 0.20;
  double _weightDirection = 0.15;
  double _weightAcceptanceProb = 0.20;
  double _weightFairness = 0.10;

  int _peakHourStart = 11;
  int _peakHourEnd = 14;
  int _peakHourStart2 = 17;
  int _peakHourEnd2 = 21;

  int _maxActiveOrders = 2;
  int _riderTimeoutSeconds = 60;
  double _prepPenaltyBase = 0.05;
  double _prepPenaltyPeak = 0.10;

  // Dynamic capacity fields
  bool _dynamicCapacityEnabled = true;
  String _weatherCondition = 'normal';
  int _complexityThresholdItems = 5;
  int _complexityThresholdHeavy = 8;
  double _performanceBoostThreshold = 90.0;
  double _performancePenaltyThreshold = 65.0;
  double _longDistanceThresholdKm = 5.0;
  int _peakCapacityReduction = 1;

  double _goldThreshold = 90.0;
  double _silverThreshold = 75.0;
  double _bronzeThreshold = 60.0;

  // Operations config (Phase 6)
  int _retryDelaySeconds = 20;
  int _dispatchLockTtlSeconds = 60;
  double _avgSpeedKmPerMin = 0.5;
  double _baseAcceptanceRate = 0.7;
  int _batchStackRadiusMeters = 500;
  int _batchDeliverySpreadMeters = 3000;
  int _restaurantAutoCancelMinutes = 15;

  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _service.getCurrentWeights(),
      _firestore
          .collection('config')
          .doc('dispatch_weights')
          .get(),
      _service.getWeightsHistory(limit: 10),
      _firestore
          .collection('config')
          .doc('performance_tiers')
          .get(),
    ]);

    final weights = results[0] as Map<String, double>;
    final doc = results[1] as DocumentSnapshot;
    final history =
        results[2] as List<Map<String, dynamic>>;
    final tierDoc = results[3] as DocumentSnapshot;

    final tierData =
        tierDoc.data() as Map<String, dynamic>?;

    final data = doc.data() as Map<String, dynamic>?;

    setState(() {
      _weightETA =
          weights['weightETA'] ?? 0.35;
      _weightWorkload =
          weights['weightWorkload'] ?? 0.20;
      _weightDirection =
          weights['weightDirection'] ?? 0.15;
      _weightAcceptanceProb =
          weights['weightAcceptanceProb'] ?? 0.20;
      _weightFairness =
          weights['weightFairness'] ?? 0.10;

      if (data != null) {
        _peakHourStart =
            (data['peakHourStart'] as num?)?.toInt() ??
                11;
        _peakHourEnd =
            (data['peakHourEnd'] as num?)?.toInt() ??
                14;
        _peakHourStart2 =
            (data['peakHourStart2'] as num?)?.toInt() ??
                17;
        _peakHourEnd2 =
            (data['peakHourEnd2'] as num?)?.toInt() ??
                21;
        _maxActiveOrders =
            (data['maxActiveOrdersPerRider'] as num?)
                    ?.toInt() ??
                2;
        _riderTimeoutSeconds =
            (data['riderTimeoutSeconds'] as num?)
                    ?.toInt() ??
                60;
        _prepPenaltyBase =
            (data['prepAlignmentPenaltyBase'] as num?)
                    ?.toDouble() ??
                0.05;
        _prepPenaltyPeak =
            (data['prepAlignmentPenaltyPeak'] as num?)
                    ?.toDouble() ??
                0.10;
        _dynamicCapacityEnabled =
            data['dynamicCapacityEnabled'] as bool? ?? true;
        _weatherCondition =
            data['weatherCondition'] as String? ?? 'normal';
        _complexityThresholdItems =
            (data['complexityThresholdItems'] as num?)
                    ?.toInt() ??
                5;
        _complexityThresholdHeavy =
            (data['complexityThresholdHeavy'] as num?)
                    ?.toInt() ??
                8;
        _performanceBoostThreshold =
            (data['performanceBoostThreshold'] as num?)
                    ?.toDouble() ??
                90.0;
        _performancePenaltyThreshold =
            (data['performancePenaltyThreshold'] as num?)
                    ?.toDouble() ??
                65.0;
        _longDistanceThresholdKm =
            (data['longDistanceThresholdKm'] as num?)
                    ?.toDouble() ??
                5.0;
        _peakCapacityReduction =
            (data['peakCapacityReduction'] as num?)
                    ?.toInt() ??
                1;

        // Operations config
        _retryDelaySeconds =
            (data['retryDelaySeconds'] as num?)
                    ?.toInt() ??
                20;
        _dispatchLockTtlSeconds =
            (data['dispatchLockTtlSeconds'] as num?)
                    ?.toInt() ??
                60;
        _avgSpeedKmPerMin =
            (data['avgSpeedKmPerMin'] as num?)
                    ?.toDouble() ??
                0.5;
        _baseAcceptanceRate =
            (data['baseAcceptanceRate'] as num?)
                    ?.toDouble() ??
                0.7;
        _batchStackRadiusMeters =
            (data['batchStackRadiusMeters'] as num?)
                    ?.toInt() ??
                500;
        _batchDeliverySpreadMeters =
            (data['batchDeliverySpreadMeters'] as num?)
                    ?.toInt() ??
                3000;
        _restaurantAutoCancelMinutes =
            (data['restaurantAutoCancelMinutes'] as num?)
                    ?.toInt() ??
                15;
      }

      if (tierData != null) {
        _goldThreshold =
            (tierData['gold_threshold'] as num?)
                    ?.toDouble() ??
                90.0;
        _silverThreshold =
            (tierData['silver_threshold'] as num?)
                    ?.toDouble() ??
                75.0;
        _bronzeThreshold =
            (tierData['bronze_threshold'] as num?)
                    ?.toDouble() ??
                60.0;
      }

      _history = history;
      _isLoading = false;
    });
  }

  double get _totalWeight =>
      _weightETA +
      _weightWorkload +
      _weightDirection +
      _weightAcceptanceProb +
      _weightFairness;

  void _applyPreset(String preset) {
    setState(() {
      switch (preset) {
        case 'balanced':
          _weightETA = 0.35;
          _weightWorkload = 0.20;
          _weightDirection = 0.15;
          _weightAcceptanceProb = 0.20;
          _weightFairness = 0.10;
          break;
        case 'speed':
          _weightETA = 0.50;
          _weightWorkload = 0.15;
          _weightDirection = 0.20;
          _weightAcceptanceProb = 0.10;
          _weightFairness = 0.05;
          break;
        case 'fairness':
          _weightETA = 0.20;
          _weightWorkload = 0.15;
          _weightDirection = 0.10;
          _weightAcceptanceProb = 0.15;
          _weightFairness = 0.40;
          break;
      }
    });
  }

  void _normalize() {
    final total = _totalWeight;
    if (total <= 0) return;
    setState(() {
      _weightETA /= total;
      _weightWorkload /= total;
      _weightDirection /= total;
      _weightAcceptanceProb /= total;
      _weightFairness /= total;
    });
  }

  Future<void> _save() async {
    _normalize();
    setState(() => _isSaving = true);

    try {
      await _firestore
          .collection('config')
          .doc('dispatch_weights')
          .set({
        'weightETA': _weightETA,
        'weightWorkload': _weightWorkload,
        'weightDirection': _weightDirection,
        'weightAcceptanceProb': _weightAcceptanceProb,
        'weightFairness': _weightFairness,
        'peakHourStart': _peakHourStart,
        'peakHourEnd': _peakHourEnd,
        'peakHourStart2': _peakHourStart2,
        'peakHourEnd2': _peakHourEnd2,
        'maxActiveOrdersPerRider': _maxActiveOrders,
        'riderTimeoutSeconds': _riderTimeoutSeconds,
        'prepAlignmentPenaltyBase': _prepPenaltyBase,
        'prepAlignmentPenaltyPeak': _prepPenaltyPeak,
        'dynamicCapacityEnabled': _dynamicCapacityEnabled,
        'weatherCondition': _weatherCondition,
        'complexityThresholdItems': _complexityThresholdItems,
        'complexityThresholdHeavy': _complexityThresholdHeavy,
        'performanceBoostThreshold': _performanceBoostThreshold,
        'performancePenaltyThreshold':
            _performancePenaltyThreshold,
        'longDistanceThresholdKm': _longDistanceThresholdKm,
        'peakCapacityReduction': _peakCapacityReduction,
        'baseCapacity': _maxActiveOrders,
        'retryDelaySeconds': _retryDelaySeconds,
        'dispatchLockTtlSeconds': _dispatchLockTtlSeconds,
        'avgSpeedKmPerMin': _avgSpeedKmPerMin,
        'baseAcceptanceRate': _baseAcceptanceRate,
        'batchStackRadiusMeters': _batchStackRadiusMeters,
        'batchDeliverySpreadMeters': _batchDeliverySpreadMeters,
        'restaurantAutoCancelMinutes':
            _restaurantAutoCancelMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'admin_ui',
      }, SetOptions(merge: true));

      await _firestore
          .collection('config')
          .doc('performance_tiers')
          .set({
        'gold_threshold': _goldThreshold,
        'silver_threshold': _silverThreshold,
        'bronze_threshold': _bronzeThreshold,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration saved'),
            backgroundColor: Colors.green,
          ),
        );
        _loadConfig();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch Configuration'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildWeightsSection(),
                const SizedBox(height: 24),
                _buildOperationalSection(),
                const SizedBox(height: 24),
                _buildDynamicCapacitySection(),
                const SizedBox(height: 24),
                _buildPerformanceTiersSection(),
                const SizedBox(height: 24),
                _buildOperationsConfigSection(),
                const SizedBox(height: 24),
                _buildHistorySection(),
                const SizedBox(height: 80),
              ],
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
    );
  }

  // --- Section 1: Scoring Weights ---

  Widget _buildWeightsSection() {
    final diff = (_totalWeight - 1.0).abs();
    final isBalanced = diff < 0.01;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scoring Weights',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                        fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Total: ${_totalWeight.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isBalanced
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                if (!isBalanced) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.balance,
                        size: 16),
                    label:
                        const Text('Auto-normalize'),
                    onPressed: _normalize,
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _presetChip('Balanced', 'balanced'),
                _presetChip(
                    'Speed-first', 'speed'),
                _presetChip(
                    'Fairness-first', 'fairness'),
              ],
            ),
            const SizedBox(height: 12),
            _weightSlider('ETA', _weightETA,
                (v) => setState(() => _weightETA = v)),
            _weightSlider(
                'Workload',
                _weightWorkload,
                (v) => setState(
                    () => _weightWorkload = v)),
            _weightSlider(
                'Direction',
                _weightDirection,
                (v) => setState(
                    () => _weightDirection = v)),
            _weightSlider(
                'Acceptance',
                _weightAcceptanceProb,
                (v) => setState(
                    () => _weightAcceptanceProb = v)),
            _weightSlider(
                'Fairness',
                _weightFairness,
                (v) => setState(
                    () => _weightFairness = v)),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, String preset) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () => _applyPreset(preset),
      backgroundColor: Colors.grey.shade200,
    );
  }

  Widget _weightSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: 100,
            onChanged: onChanged,
            activeColor: Colors.black,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // --- Section 2: Operational Parameters ---

  Widget _buildOperationalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peak Hours & Operations',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                        fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _hourRow(
              'Peak Window 1',
              _peakHourStart,
              _peakHourEnd,
              (s) => setState(
                  () => _peakHourStart = s),
              (e) =>
                  setState(() => _peakHourEnd = e),
            ),
            const SizedBox(height: 8),
            _hourRow(
              'Peak Window 2',
              _peakHourStart2,
              _peakHourEnd2,
              (s) => setState(
                  () => _peakHourStart2 = s),
              (e) =>
                  setState(() => _peakHourEnd2 = e),
            ),
            const Divider(height: 24),
            _intStepper(
              'Max Active Orders / Rider',
              _maxActiveOrders,
              1,
              5,
              (v) =>
                  setState(() => _maxActiveOrders = v),
            ),
            const SizedBox(height: 8),
            _intStepper(
              'Rider Timeout (sec)',
              _riderTimeoutSeconds,
              30,
              180,
              (v) => setState(
                  () => _riderTimeoutSeconds = v),
            ),
            const Divider(height: 24),
            _smallSlider(
              'Prep Penalty (base)',
              _prepPenaltyBase,
              (v) => setState(
                  () => _prepPenaltyBase = v),
            ),
            _smallSlider(
              'Prep Penalty (peak)',
              _prepPenaltyPeak,
              (v) => setState(
                  () => _prepPenaltyPeak = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hourRow(
    String label,
    int start,
    int end,
    ValueChanged<int> onStartChanged,
    ValueChanged<int> onEndChanged,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label,
              style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: DropdownButton<int>(
            value: start,
            isExpanded: true,
            items: List.generate(24, (i) {
              return DropdownMenuItem(
                value: i,
                child: Text('${i.toString().padLeft(2, '0')}:00',
                    style:
                        const TextStyle(fontSize: 13)),
              );
            }),
            onChanged: (v) {
              if (v != null) onStartChanged(v);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('to'),
        ),
        Expanded(
          child: DropdownButton<int>(
            value: end,
            isExpanded: true,
            items: List.generate(24, (i) {
              return DropdownMenuItem(
                value: i,
                child: Text('${i.toString().padLeft(2, '0')}:00',
                    style:
                        const TextStyle(fontSize: 13)),
              );
            }),
            onChanged: (v) {
              if (v != null) onEndChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _intStepper(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13)),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline,
              size: 20),
          onPressed: value > min
              ? () => onChanged(value - 1)
              : null,
        ),
        Text('$value',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline,
              size: 20),
          onPressed: value < max
              ? () => onChanged(value + 1)
              : null,
        ),
      ],
    );
  }

  Widget _smallSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 0.5),
            min: 0.0,
            max: 0.5,
            divisions: 50,
            onChanged: onChanged,
            activeColor: Colors.deepPurple,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // --- Section 3: Dynamic Capacity ---

  Widget _buildDynamicCapacitySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dynamic Capacity',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                        fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Adjusts max orders per rider based on '
              'time, performance, and conditions.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Dynamic Capacity',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _dynamicCapacityEnabled
                    ? 'Active — capacity adjusts per-rider'
                    : 'Off — uses static max orders',
                style: const TextStyle(fontSize: 12),
              ),
              value: _dynamicCapacityEnabled,
              activeColor: Colors.black,
              onChanged: (v) =>
                  setState(() => _dynamicCapacityEnabled = v),
            ),
            if (_dynamicCapacityEnabled) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Weather Condition',
                        style: TextStyle(fontSize: 13)),
                  ),
                  DropdownButton<String>(
                    value: _weatherCondition,
                    items: const [
                      DropdownMenuItem(
                          value: 'normal',
                          child: Text('Normal')),
                      DropdownMenuItem(
                          value: 'rain',
                          child: Text('Rain (-1)')),
                      DropdownMenuItem(
                          value: 'storm',
                          child: Text('Storm (-2)')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(
                            () => _weatherCondition = v);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _intStepper(
                'Peak Capacity Reduction',
                _peakCapacityReduction,
                0,
                2,
                (v) => setState(
                    () => _peakCapacityReduction = v),
              ),
              const SizedBox(height: 8),
              _intStepper(
                'Complex Order Threshold',
                _complexityThresholdItems,
                3,
                10,
                (v) => setState(
                    () => _complexityThresholdItems = v),
              ),
              const SizedBox(height: 8),
              _intStepper(
                'Heavy Order Threshold',
                _complexityThresholdHeavy,
                5,
                15,
                (v) => setState(
                    () => _complexityThresholdHeavy = v),
              ),
              const Divider(height: 24),
              _labeledSlider(
                'Performance Boost (>=)',
                _performanceBoostThreshold,
                70,
                100,
                (v) => setState(
                    () => _performanceBoostThreshold = v),
              ),
              _labeledSlider(
                'Performance Penalty (<)',
                _performancePenaltyThreshold,
                50,
                80,
                (v) => setState(() =>
                    _performancePenaltyThreshold = v),
              ),
              _labeledSlider(
                'Long Distance (km)',
                _longDistanceThresholdKm,
                3,
                10,
                (v) => setState(
                    () => _longDistanceThresholdKm = v),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labeledSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(label,
              style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 2).toInt(),
            onChanged: onChanged,
            activeColor: Colors.deepPurple,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(
                value == value.roundToDouble() ? 0 : 1),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // --- Section: Performance Tiers ---

  Widget _buildPerformanceTiersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Tiers',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Define score thresholds for '
              'Gold / Silver / Bronze tiers',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            _labeledSlider(
              'Gold (>=)',
              _goldThreshold,
              80,
              100,
              (v) => setState(() => _goldThreshold = v),
            ),
            _labeledSlider(
              'Silver (>=)',
              _silverThreshold,
              60,
              90,
              (v) => setState(
                  () => _silverThreshold = v),
            ),
            _labeledSlider(
              'Bronze (>=)',
              _bronzeThreshold,
              50,
              80,
              (v) => setState(
                  () => _bronzeThreshold = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Below Bronze threshold = '
              '"Needs Improvement"',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Section: Operations Config ---

  Widget _buildOperationsConfigSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operations',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Retry delays, lock TTLs, and batch parameters',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            _labeledSlider(
              'Retry Delay (seconds)',
              _retryDelaySeconds.toDouble(),
              10,
              60,
              (v) => setState(
                () => _retryDelaySeconds = v.round(),
              ),
            ),
            _labeledSlider(
              'Dispatch Lock TTL (seconds)',
              _dispatchLockTtlSeconds.toDouble(),
              30,
              120,
              (v) => setState(
                () =>
                    _dispatchLockTtlSeconds = v.round(),
              ),
            ),
            _labeledSlider(
              'Avg Speed (km/min)',
              _avgSpeedKmPerMin,
              0.25,
              1.0,
              (v) => setState(
                () => _avgSpeedKmPerMin = v,
              ),
            ),
            _labeledSlider(
              'Base Acceptance Rate',
              _baseAcceptanceRate,
              0.3,
              0.9,
              (v) => setState(
                () => _baseAcceptanceRate = v,
              ),
            ),
            _labeledSlider(
              'Batch Proximity Radius (m)',
              _batchStackRadiusMeters.toDouble(),
              200,
              2000,
              (v) => setState(
                () =>
                    _batchStackRadiusMeters = v.round(),
              ),
            ),
            _labeledSlider(
              'Batch Delivery Spread (m)',
              _batchDeliverySpreadMeters.toDouble(),
              1000,
              5000,
              (v) => setState(
                () => _batchDeliverySpreadMeters =
                    v.round(),
              ),
            ),
            _labeledSlider(
              'Restaurant Auto-Cancel (min)',
              _restaurantAutoCancelMinutes.toDouble(),
              10,
              30,
              (v) => setState(
                () => _restaurantAutoCancelMinutes =
                    v.round(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Section 4: Weight Change History ---

  Widget _buildHistorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weight Change History',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                        fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              const Text('No history available.',
                  style: TextStyle(color: Colors.grey))
            else
              ...(_history.map(_buildHistoryTile)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> h) {
    final ts = h['timestamp'];
    String dateStr = '';
    if (ts is Timestamp) {
      dateStr = DateFormat('yyyy-MM-dd HH:mm')
          .format(ts.toDate());
    }
    final changedBy =
        (h['changedBy'] ?? h['updatedBy'] ?? 'unknown')
            .toString();
    final weights = h['weights'] as Map?;
    final prev = h['previousWeights'] as Map?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(
          changedBy.contains('daily')
              ? Icons.auto_fix_high
              : Icons.person,
          size: 18,
          color: Colors.grey,
        ),
        title: Text(dateStr,
            style: const TextStyle(fontSize: 13)),
        subtitle: Text('By: $changedBy',
            style: const TextStyle(fontSize: 11)),
        children: [
          if (weights != null || prev != null)
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, bottom: 8),
              child: _buildWeightsComparison(
                  prev, weights),
            ),
        ],
      ),
    );
  }

  Widget _buildWeightsComparison(
      Map? prev, Map? curr) {
    final keys = [
      'weightETA',
      'weightWorkload',
      'weightDirection',
      'weightAcceptanceProb',
      'weightFairness',
    ];
    return Column(
      children: keys.map((k) {
        final short = k.replaceFirst('weight', '');
        final p = (prev?[k] as num?)?.toDouble();
        final c = (curr?[k] as num?)?.toDouble();
        return Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(short,
                    style: const TextStyle(
                        fontSize: 11)),
              ),
              if (p != null)
                Text(p.toStringAsFixed(3),
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey)),
              if (p != null && c != null)
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 4),
                  child: Icon(Icons.arrow_forward,
                      size: 12),
                ),
              if (c != null)
                Text(c.toStringAsFixed(3),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: (p != null && c != p)
                          ? Colors.blue
                          : Colors.black,
                    )),
            ],
          ),
        );
      }).toList(),
    );
  }
}
