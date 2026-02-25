import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:brgy/model/addon_promo_model.dart';

class AddonEditPage extends StatefulWidget {
  final AddonPromoModel? promo;

  const AddonEditPage({super.key, this.promo});

  @override
  State<AddonEditPage> createState() => _AddonEditPageState();
}

class _AddonEditPageState extends State<AddonEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _addonNameController = TextEditingController();
  final _addonDescController = TextEditingController();
  final _addonPriceController = TextEditingController();
  final _maxQtyController = TextEditingController(text: '1');

  List<Map<String, dynamic>> _vendors = [];
  String? _selectedRestaurantId;
  List<Map<String, dynamic>> _products = [];
  String? _triggerType = 'product';
  String? _triggerProductId;
  String? _addonProductId;
  bool _loadingVendors = true;
  bool _loadingProducts = false;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadVendors();
    if (widget.promo != null) {
      final p = widget.promo!;
      _addonNameController.text = p.addonName;
      _addonDescController.text = p.addonDescription;
      _addonPriceController.text = p.addonPrice.toStringAsFixed(2);
      _maxQtyController.text = p.maxQuantityPerOrder.toString();
      _selectedRestaurantId = p.restaurantId;
      _triggerType = p.triggerType;
      _triggerProductId = p.triggerProductId;
      _addonProductId = p.addonProductId;
      _status = p.status;
      _loadProducts();
    } else {
      _status = 'active';
    }
  }

  @override
  void dispose() {
    _addonNameController.dispose();
    _addonDescController.dispose();
    _addonPriceController.dispose();
    _maxQtyController.dispose();
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
          'title': (data['title'] ?? data['authorName'] ?? 'Restaurant')
              .toString(),
        };
      }).toList();
      if (mounted) {
        setState(() {
          _vendors = list;
          _loadingVendors = false;
          if (_selectedRestaurantId == null &&
              _vendors.isNotEmpty &&
              widget.promo == null) {
            _selectedRestaurantId = _vendors.first['id'] as String?;
            _loadProducts();
          }
        });
      }
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
    return (data['name'] ?? data['title'] ?? data['productName'] ?? 'Product')
        .toString();
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
      if (mounted) {
        setState(() {
          _products = list;
          _loadingProducts = false;
          if (_triggerProductId != null &&
              !list.any((e) => (e['id'] ?? '').toString() == _triggerProductId)) {
            _triggerProductId = null;
          }
          if (_addonProductId != null &&
              !list.any((e) => (e['id'] ?? '').toString() == _addonProductId)) {
            _addonProductId = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _products = [];
          _loadingProducts = false;
        });
      }
    }
  }

  Map<String, dynamic>? _productById(String? pid) {
    if (pid == null || pid.isEmpty) return null;
    try {
      return _products.firstWhere((e) => (e['id'] ?? '').toString() == pid);
    } catch (_) {
      return null;
    }
  }

  double? get _regularPrice {
    final p = _productById(_addonProductId);
    if (p == null) return null;
    return _productPrice(p);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRestaurantId == null || _selectedRestaurantId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a restaurant')),
      );
      return;
    }
    if (_triggerProductId == null || _triggerProductId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select trigger product')),
      );
      return;
    }
    if (_addonProductId == null || _addonProductId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select add-on product')),
      );
      return;
    }
    if (_triggerProductId == _addonProductId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trigger and add-on must be different products'),
        ),
      );
      return;
    }

    final regularPrice = _regularPrice ?? 0.0;
    final addonPrice = double.tryParse(_addonPriceController.text.trim());
    if (addonPrice == null || addonPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid add-on price')),
      );
      return;
    }
    if (addonPrice >= regularPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add-on price must be lower than regular price'),
        ),
      );
      return;
    }

    final maxQty = int.tryParse(_maxQtyController.text.trim()) ?? 1;
    if (maxQty < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max quantity must be at least 1')),
      );
      return;
    }

    final triggerProduct = _productById(_triggerProductId);
    final addonProduct = _productById(_addonProductId);
    if (triggerProduct == null || addonProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected products not found')),
      );
      return;
    }
    if (_productVendorId(triggerProduct) != _selectedRestaurantId ||
        _productVendorId(addonProduct) != _selectedRestaurantId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trigger and add-on must be from selected restaurant'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final createdBy = FirebaseAuth.instance.currentUser?.uid;
      final triggerName = _productName(triggerProduct);
      final addonProductName = _productName(addonProduct);

      if (widget.promo != null) {
        await FirebaseFirestore.instance
            .collection('addon_promos')
            .doc(widget.promo!.addonPromoId)
            .update({
          'restaurantId': _selectedRestaurantId,
          'triggerType': _triggerType ?? 'product',
          'triggerProductId': _triggerProductId,
          'triggerProductName': triggerName,
          'addonProductId': _addonProductId,
          'addonProductName': addonProductName,
          'addonName': _addonNameController.text.trim(),
          'addonDescription': _addonDescController.text.trim(),
          'regularPrice': regularPrice,
          'addonPrice': addonPrice,
          'maxQuantityPerOrder': maxQty,
          'status': _status ?? 'active',
          'updatedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add-on promo updated')),
          );
          Navigator.pop(context, true);
        }
      } else {
        final ref =
            FirebaseFirestore.instance.collection('addon_promos').doc();
        await ref.set({
          'restaurantId': _selectedRestaurantId,
          'triggerType': _triggerType ?? 'product',
          'triggerProductId': _triggerProductId,
          'triggerProductName': triggerName,
          'addonProductId': _addonProductId,
          'addonProductName': addonProductName,
          'addonName': _addonNameController.text.trim(),
          'addonDescription': _addonDescController.text.trim(),
          'regularPrice': regularPrice,
          'addonPrice': addonPrice,
          'maxQuantityPerOrder': maxQty,
          'status': _status ?? 'active',
          'createdAt': now,
          'updatedAt': now,
          if (createdBy != null) 'createdBy': createdBy,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add-on promo created')),
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
    final regularPrice = _regularPrice;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.promo == null ? 'New Add-on Promo' : 'Edit Add-on Promo',
        ),
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
                        _triggerProductId = null;
                        _addonProductId = null;
                        _loadProducts();
                      });
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _triggerType,
              decoration: const InputDecoration(labelText: 'Trigger type'),
              items: const [
                DropdownMenuItem(value: 'product', child: Text('Product')),
              ],
              onChanged: (v) => setState(() => _triggerType = v ?? 'product'),
            ),
            const SizedBox(height: 12),
            if (_products.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _triggerProductId,
                decoration: const InputDecoration(
                  labelText: 'Trigger product',
                ),
                items: _products
                    .map((p) {
                      final id = (p['id'] ?? '').toString();
                      final name = _productName(p);
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(name),
                      );
                    })
                    .toList(),
                onChanged: (v) => setState(() => _triggerProductId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _addonProductId,
                decoration: const InputDecoration(
                  labelText: 'Add-on product',
                ),
                items: _products
                    .map((p) {
                      final id = (p['id'] ?? '').toString();
                      final name = _productName(p);
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(name),
                      );
                    })
                    .toList(),
                onChanged: (v) => setState(() => _addonProductId = v),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _addonNameController,
              decoration: const InputDecoration(labelText: 'Add-on name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addonDescController,
              decoration: const InputDecoration(labelText: 'Add-on description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            if (regularPrice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Regular price (from product): '
                  '₱${regularPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            TextFormField(
              controller: _addonPriceController,
              decoration: const InputDecoration(
                labelText: 'Add-on price (₱) - must be lower than regular',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.trim()) == null) return 'Invalid number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxQtyController,
              decoration: const InputDecoration(
                labelText: 'Max quantity per order',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = int.tryParse(v.trim());
                if (n == null || n < 1) return 'Must be at least 1';
                return null;
              },
            ),
            if (_loadingProducts)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_products.isEmpty && _selectedRestaurantId != null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No products found for this restaurant.'),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Add-on Promo'),
            ),
          ],
        ),
      ),
    );
  }
}
