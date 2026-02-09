import 'package:flutter/material.dart';
import 'package:brgy/services/referral_service.dart';
import 'package:intl/intl.dart';

class ReferralRelationshipsPage extends StatefulWidget {
  const ReferralRelationshipsPage({super.key});

  @override
  State<ReferralRelationshipsPage> createState() =>
      _ReferralRelationshipsPageState();
}

class _ReferralRelationshipsPageState
    extends State<ReferralRelationshipsPage> {
  String _searchQuery = '';
  String _statusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Relationships'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Referrer or Referred User ID...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Status',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Status')),
                    DropdownMenuItem(
                        value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(
                        value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _statusFilter = value ?? 'all';
                    });
                  },
                ),
              ],
            ),
          ),

          // Relationships List
          Expanded(
            child: StreamBuilder<List<ReferralRelationship>>(
              stream: ReferralService.getReferralRelationshipsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error loading relationships: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final relationships = snapshot.data ?? [];

                // Filter relationships
                final filtered = relationships.where((rel) {
                  // Status filter
                  if (_statusFilter != 'all' && rel.status != _statusFilter) {
                    return false;
                  }

                  // Search filter
                  if (_searchQuery.isNotEmpty) {
                    final query = _searchQuery.toLowerCase();
                return rel.referrerId.toLowerCase().contains(query) ||
                    rel.referredUserId.toLowerCase().contains(query) ||
                    rel.referralCode.toLowerCase().contains(query);
              }

              return true;
            }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty || _statusFilter != 'all'
                              ? Icons.search_off
                              : Icons.link_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _statusFilter != 'all'
                              ? 'No relationships match your filters'
                              : 'No referral relationships found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final relationship = filtered[index];
                    return _RelationshipCard(relationship: relationship);
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

class _RelationshipCard extends StatelessWidget {
  final ReferralRelationship relationship;

  const _RelationshipCard({required this.relationship});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(relationship.status)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(relationship.status),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    relationship.status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(relationship.status),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (relationship.creditedAmount > 0)
                  Text(
                    '₱${relationship.creditedAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Referrer ID',
              value: relationship.referrerId.length > 20
                  ? '${relationship.referrerId.substring(0, 20)}...'
                  : relationship.referrerId,
            ),
            _InfoRow(
              label: 'Referred User ID',
              value: relationship.referredUserId.length > 20
                  ? '${relationship.referredUserId.substring(0, 20)}...'
                  : relationship.referredUserId,
            ),
            _InfoRow(
              label: 'Referral Code',
              value: relationship.referralCode,
            ),
            if (relationship.triggeringOrderId != null)
              _InfoRow(
                label: 'Triggering Order',
                value: relationship.triggeringOrderId!.length > 20
                    ? '${relationship.triggeringOrderId!.substring(0, 20)}...'
                    : relationship.triggeringOrderId!,
              ),
            _InfoRow(
              label: 'Created',
              value: DateFormat('MMM dd, yyyy HH:mm')
                  .format(relationship.createdAt.toDate()),
            ),
            if (relationship.creditedAt != null)
              _InfoRow(
                label: 'Credited',
                value: DateFormat('MMM dd, yyyy HH:mm')
                    .format(relationship.creditedAt!.toDate()),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

