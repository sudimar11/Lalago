import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/bundle_model.dart';
import 'package:brgy/pages/bundle_edit_page.dart';

class BundlesPage extends StatefulWidget {
  const BundlesPage({super.key});

  @override
  State<BundlesPage> createState() => _BundlesPageState();
}

class _BundlesPageState extends State<BundlesPage> {
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

  Future<void> _toggleStatus(BundleModel bundle) async {
    if (_updatingIds.contains(bundle.bundleId)) return;
    setState(() => _updatingIds.add(bundle.bundleId));
    try {
      final next =
          bundle.status == 'active' ? 'inactive' : 'active';
      await FirebaseFirestore.instance
          .collection('bundles')
          .doc(bundle.bundleId)
          .update({
        'status': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundle set to $next')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(bundle.bundleId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundlesQuery =
        FirebaseFirestore.instance.collection('bundles').orderBy('createdAt');
    final vendorsQuery = FirebaseFirestore.instance.collection('vendors');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bundle Deals'),
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
                hintText: 'Search bundles',
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
                final vendorsDocs = vendorsSnap.data?.docs ?? const [];
                final Map<String, String> vendorIdToTitle = {
                  for (final v in vendorsDocs)
                    v.id: ((v.data() as Map<String, dynamic>)['title'] ??
                            (v.data() as Map<String, dynamic>)['authorName'] ??
                            'Restaurant')
                        .toString()
                };

                return StreamBuilder<QuerySnapshot>(
                  stream: bundlesQuery.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                          child: Text('Failed to load bundles: ${snap.error}'));
                    }

                    final docs = snap.data?.docs ?? const [];
                    final bundles = docs
                        .map((d) => BundleModel.fromFirestore(d))
                        .where((b) {
                      if (_query.isEmpty) return true;
                      final name = b.name.toLowerCase();
                      final rest =
                          vendorIdToTitle[b.restaurantId]?.toLowerCase() ?? '';
                      return name.contains(_query) || rest.contains(_query);
                    }).toList();

                    if (bundles.isEmpty) {
                      return const Center(child: Text('No bundles found'));
                    }

                    return ListView.separated(
                      itemCount: bundles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final bundle = bundles[index];
                        final restName =
                            vendorIdToTitle[bundle.restaurantId] ?? '—';
                        final isUpdating =
                            _updatingIds.contains(bundle.bundleId);

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.orange.shade100,
                            backgroundImage: bundle.imageUrl != null &&
                                    bundle.imageUrl!.isNotEmpty
                                ? NetworkImage(bundle.imageUrl!)
                                : null,
                            child: bundle.imageUrl == null ||
                                    bundle.imageUrl!.isEmpty
                                ? const Icon(Icons.inventory_2,
                                    color: Colors.orange)
                                : null,
                          ),
                          title: Text(bundle.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Restaurant: $restName'),
                              Text(
                                '₱${bundle.bundlePrice.toStringAsFixed(2)} '
                                '(${bundle.items.length} items) · ${bundle.status}',
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  final updated = await Navigator.push(
                                    context,
                                    MaterialPageRoute<bool>(
                                      builder: (context) =>
                                          BundleEditPage(bundle: bundle),
                                    ),
                                  );
                                  if (updated == true && mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                              Switch(
                                value: bundle.status == 'active',
                                onChanged: isUpdating
                                    ? null
                                    : (_) => _toggleStatus(bundle),
                              ),
                            ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => const BundleEditPage(bundle: null),
            ),
          );
          if (created == true && mounted) setState(() {});
        },
        child: const Icon(Icons.add),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
