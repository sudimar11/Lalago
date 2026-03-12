import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';
import 'package:foodie_restaurant/services/helper.dart';

/// Locations management for chain admins.
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({Key? key}) : super(key: key);

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final _firestore = FirebaseFirestore.instance;
  List<VendorModel> _locations = [];
  Map<String, int> _todayOrderCounts = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final chainId = MyAppState.currentUser?.chainId;
    if (chainId == null || chainId.isEmpty) {
      setState(() {
        _error = 'Not a chain admin';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    EasyLoading.show(status: 'Loading...');

    try {
      final vendorsSnap = await _firestore
          .collection(VENDORS)
          .where('chainId', isEqualTo: chainId)
          .get();

      final locations = vendorsSnap.docs
          .map((d) => VendorModel.fromJson({...d.data(), 'id': d.id}))
          .toList();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      final counts = <String, int>{};
      for (final v in locations) {
        final ordersSnap = await _firestore
            .collection(ORDERS)
            .where('vendorID', isEqualTo: v.id)
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('createdAt', isLessThan: Timestamp.fromDate(todayEnd))
            .get();
        counts[v.id] = ordersSnap.docs.length;
      }

      if (mounted) {
        setState(() {
          _locations = locations;
          _todayOrderCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locations'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      backgroundColor: isDark ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLocations,
                  color: Color(COLOR_PRIMARY),
                  child: _locations.isEmpty
                      ? Center(
                          child: showEmptyState(
                            'No locations',
                            'Add locations to your chain in Admin.',
                            isDarkMode: isDark,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _locations.length,
                          itemBuilder: (_, i) {
                            final v = _locations[i];
                            final count = _todayOrderCounts[v.id] ?? 0;
                            final isOpen = v.restStatus;
                            return Card(
                              color: isDark
                                  ? Color(DARK_CARD_BG_COLOR)
                                  : Colors.white,
                              child: ListTile(
                                title: Text(
                                  v.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                subtitle: Text(
                                  '${isOpen ? "Open" : "Closed"} • '
                                  'Today: $count orders',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Color(COLOR_PRIMARY).withValues(alpha: 0.3),
                                  child: Icon(
                                    Icons.store,
                                    color: Color(COLOR_PRIMARY),
                                  ),
                                ),
                                trailing: Icon(
                                  isOpen
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: isOpen
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
