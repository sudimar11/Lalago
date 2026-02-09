import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FoodsPage extends StatefulWidget {
  const FoodsPage({super.key});

  @override
  State<FoodsPage> createState() => _FoodsPageState();
}

class _FoodsPageState extends State<FoodsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<String> _updatingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _readName(Map<String, dynamic> data) {
    final value = (data['name'] ??
            data['title'] ??
            data['product_name'] ??
            data['productName'] ??
            'Food')
        .toString();
    return value.isEmpty ? 'Food' : value;
  }

  String _readVendor(Map<String, dynamic> data) {
    final vendor = (data['vendorTitle'] ??
            data['vendor']?['title'] ??
            data['vendor']?['name'] ??
            data['vendorName'] ??
            data['restaurantTitle'] ??
            data['restaurantName'] ??
            data['restaurant']?['title'] ??
            data['restaurant']?['name'] ??
            data['storeName'] ??
            data['store']?['name'] ??
            data['authorName'] ??
            '')
        .toString();
    return vendor;
  }

  String _readPrice(Map<String, dynamic> data) {
    final price = data['price'] ?? data['discountedPrice'] ?? data['amount'];
    if (price == null) return '';
    try {
      final num p = (price is num) ? price : num.parse(price.toString());
      return '₱${p.toStringAsFixed(2)}';
    } catch (_) {
      return price.toString();
    }
  }

  String _readImage(Map<String, dynamic> data) {
    final image = (data['photo'] ??
            data['image'] ??
            data['imageUrl'] ??
            data['thumbnail'] ??
            data['picture'] ??
            '')
        .toString();
    return image;
  }

  bool _readPublished(Map<String, dynamic> data) {
    final keys = [
      'isPublished',
      'published',
      'publish',
      'is_public',
      'isVisible',
      'visible',
    ];
    for (final k in keys) {
      if (data.containsKey(k)) {
        final v = data[k];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) return v.toLowerCase() == 'true' || v == '1';
      }
    }
    return false;
  }

  String _publishFieldName(Map<String, dynamic> data) {
    final keys = [
      'isPublished',
      'published',
      'publish',
      'is_public',
      'isVisible',
      'visible',
    ];
    for (final k in keys) {
      if (data.containsKey(k)) return k;
    }
    return 'isPublished';
  }

  String _readVendorId(Map<String, dynamic> data) {
    final candidates = [
      data['vendorId'],
      data['vendorID'],
      data['vendor_id'],
      data['vendor'] is Map
          ? (data['vendor']['id'] ?? data['vendor']['vendorId'])
          : null,
      data['restaurantId'],
      data['restaurant'] is Map ? data['restaurant']['id'] : null,
      data['storeId'],
      data['store'] is Map ? data['store']['id'] : null,
    ];
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final Query foodsQuery =
        FirebaseFirestore.instance.collection('vendor_products');
    final Query vendorsQuery = FirebaseFirestore.instance.collection('vendors');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Foods'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search foods',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: vendorsQuery.snapshots(),
              builder: (context, vendorsSnap) {
                if (vendorsSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vendorsSnap.hasError) {
                  return const Center(child: Text('Failed to load vendors'));
                }

                final vendorsDocs = vendorsSnap.data?.docs ?? const [];
                final Map<String, String> vendorIdToTitle = {
                  for (final v in vendorsDocs)
                    v.id: ((v.data() as Map<String, dynamic>)['title'] ??
                            (v.data() as Map<String, dynamic>)['authorName'] ??
                            'Restaurant')
                        .toString()
                };

                return StreamBuilder<QuerySnapshot>(
                  stream: foodsQuery.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return const Center(child: Text('Failed to load foods'));
                    }

                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No foods found'));
                    }

                    final filtered = docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final name = _readName(data).toLowerCase();
                      String vendor = _readVendor(data).toLowerCase();
                      if (vendor.isEmpty) {
                        final vid = _readVendorId(data);
                        vendor = vendorIdToTitle[vid]?.toLowerCase() ?? '';
                      }
                      if (_query.isEmpty) return true;
                      return name.contains(_query) || vendor.contains(_query);
                    }).toList();

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final title = _readName(data);
                        String vendor = _readVendor(data);
                        if (vendor.isEmpty) {
                          final vid = _readVendorId(data);
                          vendor = vendorIdToTitle[vid] ?? '';
                        }
                        final price = _readPrice(data);
                        final image = _readImage(data);
                        final published = _readPublished(data);
                        final isUpdating = _updatingIds.contains(doc.id);

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.orange,
                            backgroundImage:
                                (image.isNotEmpty) ? NetworkImage(image) : null,
                            child: image.isEmpty
                                ? const Icon(Icons.fastfood,
                                    color: Colors.white)
                                : null,
                          ),
                          title: Text(title),
                          subtitle: (vendor.isEmpty && price.isEmpty)
                              ? null
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (vendor.isNotEmpty)
                                      Text('Restaurant: $vendor'),
                                    if (price.isNotEmpty) Text(price),
                                  ],
                                ),
                          trailing: Switch(
                            value: published,
                            onChanged: isUpdating
                                ? null
                                : (value) async {
                                    setState(() {
                                      _updatingIds.add(doc.id);
                                    });
                                    try {
                                      final field = _publishFieldName(data);
                                      await FirebaseFirestore.instance
                                          .collection('vendor_products')
                                          .doc(doc.id)
                                          .set({field: value},
                                              SetOptions(merge: true));
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content:
                                                  Text('Failed to update: $e')),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _updatingIds.remove(doc.id);
                                        });
                                      }
                                    }
                                  },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
