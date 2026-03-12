import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/addon_promo_model.dart';
import 'package:brgy/pages/addon_edit_page.dart';

class AddonsPage extends StatefulWidget {
  const AddonsPage({super.key});

  @override
  State<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends State<AddonsPage> {
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

  Future<void> _toggleStatus(AddonPromoModel promo) async {
    if (_updatingIds.contains(promo.addonPromoId)) return;
    setState(() => _updatingIds.add(promo.addonPromoId));
    try {
      final next =
          promo.status == 'active' ? 'inactive' : 'active';
      await FirebaseFirestore.instance
          .collection('addon_promos')
          .doc(promo.addonPromoId)
          .update({
        'status': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add-on promo set to $next')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(promo.addonPromoId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final promosQuery = FirebaseFirestore.instance
        .collection('addon_promos')
        .orderBy('createdAt');
    final vendorsQuery = FirebaseFirestore.instance.collection('vendors');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add-on Promos'),
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
                hintText: 'Search add-on promos',
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
                  stream: promosQuery.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load add-on promos: ${snap.error}',
                        ),
                      );
                    }

                    final docs = snap.data?.docs ?? const [];
                    final promos = docs
                        .map((d) => AddonPromoModel.fromFirestore(d))
                        .where((p) {
                      if (_query.isEmpty) return true;
                      final name = p.addonName.toLowerCase();
                      final rest =
                          vendorIdToTitle[p.restaurantId]?.toLowerCase() ?? '';
                      return name.contains(_query) || rest.contains(_query);
                    }).toList();

                    if (promos.isEmpty) {
                      return const Center(
                        child: Text('No add-on promos found'),
                      );
                    }

                    return ListView.separated(
                      itemCount: promos.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final promo = promos[index];
                        final restName =
                            vendorIdToTitle[promo.restaurantId] ?? '—';
                        final isUpdating =
                            _updatingIds.contains(promo.addonPromoId);

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.green.shade100,
                            backgroundImage: promo.imageUrl != null &&
                                    promo.imageUrl!.isNotEmpty
                                ? NetworkImage(promo.imageUrl!)
                                : null,
                            child: promo.imageUrl == null ||
                                    promo.imageUrl!.isEmpty
                                ? const Icon(Icons.add_circle_outline,
                                    color: Colors.green)
                                : null,
                          ),
                          title: Text(promo.addonName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Restaurant: $restName'),
                              Text(
                                '${promo.triggerProductName} → ${promo.addonProductName}',
                              ),
                              Text(
                                '₱${promo.regularPrice.toStringAsFixed(2)} → '
                                '₱${promo.addonPrice.toStringAsFixed(2)} '
                                '(max ${promo.maxQuantityPerOrder}) · '
                                '${promo.status}',
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
                                          AddonEditPage(promo: promo),
                                    ),
                                  );
                                  if (updated == true && mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                              Switch(
                                value: promo.status == 'active',
                                onChanged: isUpdating
                                    ? null
                                    : (_) => _toggleStatus(promo),
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
              builder: (context) => const AddonEditPage(promo: null),
            ),
          );
          if (created == true && mounted) setState(() {});
        },
        child: const Icon(Icons.add),
        backgroundColor: Colors.green,
      ),
    );
  }
}
