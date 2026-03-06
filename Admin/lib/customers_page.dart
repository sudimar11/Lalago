import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/pages/customer_information_page.dart';
import 'package:brgy/services/user_segment_service.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, this.initialSegment});

  final String? initialSegment;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectedSegment = 'all';

  @override
  void initState() {
    super.initState();
    _selectedSegment = widget.initialSegment ?? 'all';
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true);
    if (_selectedSegment != 'all') {
      query = query.where('segment', isEqualTo: _selectedSegment);
    }
    return query.orderBy('engagementScore', descending: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String name,
    String userId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text(
          'Remove "$name" from customers? This will deactivate the account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance.collection(USERS).doc(userId).update({
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name has been removed')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search name or number',
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
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: _selectedSegment,
                  isExpanded: true,
                  hint: const Text('Filter by segment'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('All Segments'),
                    ),
                    ...UserSegmentService.segments.map(
                      (segment) => DropdownMenuItem<String>(
                        value: segment,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: UserSegmentService.getSegmentColor(
                                  segment,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              UserSegmentService.getSegmentDisplayName(
                                segment,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSegment = value);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load customers'));
                }

                final docs = snapshot.data?.docs ?? const [];
                final totalCustomers = docs.length;

                final filtered = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final firstName = (data['firstName'] ?? '').toString();
                  final lastName = (data['lastName'] ?? '').toString();
                  final phone = (data['phoneNumber'] ?? '').toString();
                  final name = ('$firstName $lastName').trim();

                  return {
                    'doc': doc,
                    'name': name.isEmpty ? 'Unknown User' : name,
                    'phone': phone,
                  };
                }).where((item) {
                  if (_query.isEmpty) return true;
                  final q = _query;
                  return item['name'].toString().toLowerCase().contains(q) ||
                      item['phone'].toString().toLowerCase().contains(q);
                }).toList();

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.blue,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Total Customers: $totalCustomers',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No customers found'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(
                                height: 12,
                              ),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final name = item['name'] as String;
                                final phone = item['phone'] as String;
                                final doc = item['doc'] as DocumentSnapshot;
                                final userId = doc.id;

                                return Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CustomerInformationPage(
                                            userId: userId,
                                          ),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        children: [
                                          const CircleAvatar(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            radius: 28,
                                            child: Icon(
                                              Icons.person,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  phone.isEmpty
                                                      ? 'No number'
                                                      : phone,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _confirmDelete(
                                              context,
                                              name,
                                              userId,
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
