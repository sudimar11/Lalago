import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:brgy/model/bundle_model.dart';

class BundleEditPage extends StatefulWidget {
  final BundleModel? bundle;

  const BundleEditPage({super.key, this.bundle});

  @override
  State<BundleEditPage> createState() => _BundleEditPageState();
}

class _BundleEditPageState extends State<BundleEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _imageController = TextEditingController();
  final _bundlePriceController = TextEditingController();

  List<Map<String, dynamic>> _vendors = [];
  String? _selectedRestaurantId;
  List<Map<String, dynamic>> _products = [];
  final Map<String, int> _selectedProductQty = {};
  final Set<String> _selectedProductIds = {};
  bool _loadingVendors = true;
  bool _loadingProducts = false;
  bool _saving = false;
  String? _status;
  DateTime? _startDate;
  DateTime? _endDate;
  int? _maxPurchasesPerCustomer;

  @override
  void initState() {
    super.initState();
    _loadVendors();
    if (widget.bundle != null) {
      final b = widget.bundle!;
      _nameController.text = b.name;
      _descController.text = b.description;
      _imageController.text = b.imageUrl ?? '';
      _bundlePriceController.text = b.bundlePrice.toStringAsFixed(2);
      _selectedRestaurantId = b.restaurantId;
      _status = b.status;
      _startDate = b.startDate?.toDate();
      _endDate = b.endDate?.toDate();
      _maxPurchasesPerCustomer = b.maxPurchasesPerCustomer;
      for (final item in b.items) {
        _selectedProductIds.add(item.productId);
        _selectedProductQty[item.productId] = item.quantity;
      }
      _loadProducts();
    } else {
      _status = 'active';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _imageController.dispose();
    _bundlePriceController.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    setState(() => _loadingVendors = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('vendors')
          .orderBy('title')
          .get();
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': (data['title'] ?? data['authorName'] ?? 'Restaurant').toString(),
        };
      }).toList();
      if (mounted) setState(() {
        _vendors = list;
        _loadingVendors = false;
        if (_selectedRestaurantId == null && _vendors.isNotEmpty && widget.bundle == null) {
          _selectedRestaurantId = _vendors.first['id'] as String?;
          _loadProducts();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadingVendors = false);
    }
  }

  String _productVendorId(Map<String, dynamic> data) {
    for (final k in ['vendorId', 'vendorID', 'vendor_id']) {
      final v = data[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  String _productName(Map<String, dynamic> data) {
    return (data['name'] ?? data['title'] ?? data['productName'] ?? 'Product').toString();
  }

  String _productPhoto(Map<String, dynamic> data) {
    return (data['photo'] ?? data['imageUrl'] ?? data['image'] ?? '').toString();
  }

  double _productPrice(Map<String, dynamic> data) {
    final p = data['price'] ?? data['discountedPrice'] ?? data['amount'];
    if (p == null) return 0.0;
    if (p is num) return p.toDouble();
    return double.tryParse(p.toString()) ?? 0.0;
  }

  Future<void> _loadProducts() async {
    if (_selectedRestaurantId == null || _selectedRestaurantId!.isEmpty) {
      setState(() => _products = []);
      return;
    }
    setState(() => _loadingProducts = true);
    try {
      final id = _selectedRestaurantId!;
      final coll = FirebaseFirestore.instance.collection('vendor_products');
      final q1 = coll.where('vendorId', isEqualTo: id).get();
      final q2 = coll.where('vendorID', isEqualTo: id).get();
      final q3 = coll.where('vendor_id', isEqualTo: id).get();
      final results = await Future.wait([q1, q2, q3]);
      final Map<String, Map<String, dynamic>> byId = {};
      for (final snap in results) {
        for (final doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          byId[doc.id] = data;
        }
      }
      final list = byId.values.toList();
      if (mounted) setState(() {
        _products = list;
        _loadingProducts = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _products = [];
        _loadingProducts = false;
      });
    }
  }

  Map<String, dynamic>? _productById(String pid) {
    try {
      return _products.firstWhere((e) => e['id'] == pid);
    } catch (_) {
      return null;
    }
  }

  double get _computedRegularPrice {
    double sum = 0.0;
    for (final pid in _selectedProductIds) {
      final p = _productById(pid);
      if (p == null) continue;
      final qty = _selectedProductQty[pid] ?? 1;
      sum += _productPrice(p) * qty;
    }
    return sum;
  }

  bool get _allSameVendor {
    if (_selectedProductIds.isEmpty) return true;
    String? vid;
    for (final pid in _selectedProductIds) {
      final p = _productById(pid);
      if (p == null) continue;
      final v = _productVendorId(p);
      if (vid != null && v != vid) return false;
      vid = v;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRestaurantId == null || _selectedRestaurantId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a restaurant')),
      );
      return;
    }
    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one product')),
      );
      return;
    }
    if (!_allSameVendor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('All selected products must be from the same restaurant')),
      );
      return;
    }

    final bundlePrice = double.tryParse(_bundlePriceController.text.trim());
    if (bundlePrice == null || bundlePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid bundle price')),
      );
      return;
    }

    final regularPrice = _computedRegularPrice;
    final savingsAmount = (regularPrice - bundlePrice).clamp(0.0, double.infinity);
    final savingsPercentage = regularPrice > 0
        ? ((savingsAmount / regularPrice) * 100).clamp(0.0, 100.0)
        : 0.0;

    final items = <BundleItemModel>[];
    for (final pid in _selectedProductIds) {
      final p = _productById(pid);
      if (p == null) continue;
      final qty = _selectedProductQty[pid] ?? 1;
      items.add(BundleItemModel(
        productId: pid,
        productName: _productName(p),
        quantity: qty,
        priceAtCreation: _productPrice(p),
      ));
    }

    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final createdBy = FirebaseAuth.instance.currentUser?.uid;

      if (widget.bundle != null) {
        await FirebaseFirestore.instance
            .collection('bundles')
            .doc(widget.bundle!.bundleId)
            .update({
          'restaurantId': _selectedRestaurantId,
          'name': _nameController.text.trim(),
          'description': _descController.text.trim(),
          'imageUrl': _imageController.text.trim().isEmpty
              ? null
              : _imageController.text.trim(),
          'items': items.map((e) => e.toMap()).toList(),
          'regularPrice': regularPrice,
          'bundlePrice': bundlePrice,
          'savingsAmount': savingsAmount,
          'savingsPercentage': savingsPercentage,
          'status': _status ?? 'active',
          'startDate': _startDate != null
              ? Timestamp.fromDate(_startDate!)
              : null,
          'endDate':
              _endDate != null ? Timestamp.fromDate(_endDate!) : null,
          'maxPurchasesPerCustomer': _maxPurchasesPerCustomer,
          'updatedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bundle updated')),
          );
          Navigator.pop(context, true);
        }
      } else {
        final ref =
            FirebaseFirestore.instance.collection('bundles').doc();
        await ref.set({
          'bundleId': ref.id,
          'restaurantId': _selectedRestaurantId,
          'name': _nameController.text.trim(),
          'description': _descController.text.trim(),
          'imageUrl': _imageController.text.trim().isEmpty
              ? null
              : _imageController.text.trim(),
          'items': items.map((e) => e.toMap()).toList(),
          'regularPrice': regularPrice,
          'bundlePrice': bundlePrice,
          'savingsAmount': savingsAmount,
          'savingsPercentage': savingsPercentage,
          'status': _status ?? 'active',
          'startDate': _startDate != null
              ? Timestamp.fromDate(_startDate!)
              : null,
          'endDate':
              _endDate != null ? Timestamp.fromDate(_endDate!) : null,
          'maxPurchasesPerCustomer': _maxPurchasesPerCustomer,
          'totalPurchasesCount': 0,
          'createdAt': now,
          'updatedAt': now,
          if (createdBy != null) 'createdBy': createdBy,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bundle created')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bundle == null ? 'New Bundle' : 'Edit Bundle'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _selectedRestaurantId,
              decoration: const InputDecoration(labelText: 'Restaurant'),
              items: _vendors
                  .map((v) => DropdownMenuItem<String>(
                        value: v['id'] as String,
                        child: Text((v['title'] ?? '').toString()),
                      ))
                  .toList(),
              onChanged: _loadingProducts
                  ? null
                  : (v) {
                      setState(() {
                        _selectedRestaurantId = v;
                        _selectedProductIds.clear();
                        _selectedProductQty.clear();
                        _loadProducts();
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Bundle name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imageController,
              decoration: const InputDecoration(
                  labelText: 'Image URL (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bundlePriceController,
              decoration: const InputDecoration(labelText: 'Bundle price (₱)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.trim()) == null) return 'Invalid number';
                return null;
              },
            ),
            if (_selectedProductIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Regular price (sum of items): ₱${_computedRegularPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Products (same restaurant only)',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            if (!_allSameVendor)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'All selected products must be from the same restaurant.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (_loadingProducts)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No products found for this restaurant.'),
              )
            else
              ..._products.map((p) {
                final id = (p['id'] ?? '').toString();
                final name = _productName(p);
                final price = _productPrice(p);
                final selected = _selectedProductIds.contains(id);
                final qty = _selectedProductQty[id] ?? 1;
                return CheckboxListTile(
                  value: selected,
                  title: Text(name),
                  subtitle: Text('₱${price.toStringAsFixed(2)}'),
                  secondary: selected
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                setState(() {
                                  if (qty > 1) {
                                    _selectedProductQty[id] = qty - 1;
                                  }
                                });
                              },
                            ),
                            Text('$qty'),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                setState(() {
                                  _selectedProductQty[id] = qty + 1;
                                });
                              },
                            ),
                          ],
                        )
                      : null,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedProductIds.add(id);
                        _selectedProductQty[id] = 1;
                      } else {
                        _selectedProductIds.remove(id);
                        _selectedProductQty.remove(id);
                      }
                    });
                  },
                );
              }),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Bundle'),
            ),
          ],
        ),
      ),
    );
  }
}
