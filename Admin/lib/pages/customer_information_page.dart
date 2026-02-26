import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class CustomerInformationPage extends StatefulWidget {
  final String userId;

  const CustomerInformationPage({
    super.key,
    required this.userId,
  });

  @override
  State<CustomerInformationPage> createState() =>
      _CustomerInformationPageState();
}

class _CustomerInformationPageState extends State<CustomerInformationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Information'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection(USERS)
            .doc(widget.userId)
            .get(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (userSnapshot.hasError) {
            return _buildErrorState(
              'Failed to load customer data',
              userSnapshot.error.toString(),
            );
          }

          if (!userSnapshot.hasData || userSnapshot.data == null) {
            return _buildErrorState(
              'Failed to load',
              'Could not load customer data. Please try again.',
            );
          }

          final docSnapshot = userSnapshot.data!;
          if (!docSnapshot.exists) {
            return _buildErrorState(
              'Customer not found',
              'No account exists for this user. They may have left feedback '
              'before signing up, or their account was removed.',
            );
          }

          final userDataRaw = docSnapshot.data() as Map<String, dynamic>?;
          if (userDataRaw == null || userDataRaw.isEmpty) {
            return _buildErrorState(
              'No profile data',
              'This user has no profile information on file.',
            );
          }

          final userData = userDataRaw;

          // Safely extract fields with null handling
          final firstName = (userData['firstName'] ?? '').toString();
          final lastName = (userData['lastName'] ?? '').toString();
          final fullName = ('$firstName $lastName').trim();
          final displayName = fullName.isEmpty ? 'Unknown User' : fullName;
          final email = (userData['email'] ?? '').toString();
          final phone = (userData['phoneNumber'] ?? '').toString();
          final profilePictureURL =
              (userData['profilePictureURL'] ?? '').toString();
          final createdAt = userData['createdAt'] as Timestamp?;

          // Note: We intentionally do NOT display sensitive fields like:
          // - wallet_amount
          // - role (admin/internal flags)
          // - active status (internal flag)
          // - lastOnlineTimestamp (internal data)

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                _buildHeaderSection(
                  displayName,
                  profilePictureURL,
                  createdAt,
                ),
                const SizedBox(height: 24),

                // Basic Information Card
                _buildBasicInfoCard(
                  displayName,
                  email,
                  phone,
                ),
                const SizedBox(height: 16),

                // Account Information Card
                _buildAccountInfoCard(
                  widget.userId,
                  createdAt,
                ),
                const SizedBox(height: 16),

                // Activity Snapshot Card
                _buildActivitySnapshotCard(),
                const SizedBox(height: 16),

                // Preference Profile Card
                _buildPreferenceProfileCard(userData),
                const SizedBox(height: 16),

                // Order History Section
                _buildOrderHistorySection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderSection(
    String name,
    String profilePictureURL,
    Timestamp? createdAt,
  ) {
    String joinDateText = 'Unknown';
    if (createdAt != null) {
      final date = createdAt.toDate();
      joinDateText = DateFormat('MMMM dd, yyyy').format(date);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              backgroundImage: profilePictureURL.isNotEmpty
                  ? NetworkImage(profilePictureURL)
                  : null,
              child: profilePictureURL.isEmpty
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                'Customer Account',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue[700],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Joined: $joinDateText',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard(
    String fullName,
    String email,
    String phone,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.person, 'Full Name', fullName),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.email, 'Email', email.isEmpty ? 'N/A' : email),
            const SizedBox(height: 12),
            _buildInfoRowWithCopy(
              Icons.phone,
              'Phone Number',
              phone.isEmpty ? 'No number' : phone,
              phone.isNotEmpty ? phone : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard(
    String userId,
    Timestamp? createdAt,
  ) {
    String shortenedUserId = userId.length > 12
        ? '${userId.substring(0, 12)}...'
        : userId;

    String creationDateText = 'Unknown';
    if (createdAt != null) {
      final date = createdAt.toDate();
      creationDateText = DateFormat('MMMM dd, yyyy').format(date);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRowWithCopy(
              Icons.badge,
              'User ID',
              shortenedUserId,
              userId,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.calendar_today,
              'Account Creation Date',
              creationDateText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceProfileCard(Map<String, dynamic> userData) {
    final prefs = userData['preferenceProfile'] as Map<String, dynamic>?;
    if (prefs == null || prefs.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No preference data yet'),
          ),
        ),
      );
    }

    final cuisinePrefs = prefs['cuisinePreferences'] as Map? ?? {};
    final avgSpend = prefs['avgSpend'];
    final preferredTimes = prefs['preferredTimes'] as List? ?? [];
    final favoriteRestaurants = prefs['favoriteRestaurants'] as List? ?? [];
    final lastUpdated = prefs['lastUpdated'];

    String lastUpdatedStr = 'Unknown';
    if (lastUpdated != null && lastUpdated is Timestamp) {
      lastUpdatedStr =
          DateFormat.yMd().add_Hm().format(lastUpdated.toDate());
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Preference Profile',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (cuisinePrefs.isNotEmpty) ...[
              Text(
                'Cuisine Preferences',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              ...cuisinePrefs.entries.map((e) {
                final v = e.value is num ? (e.value as num).toDouble() : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(e.key.toString()),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: v.clamp(0.0, 1.0),
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${(v * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Average Spend'),
              trailing: Text(
                avgSpend != null
                    ? '₱${(avgSpend is num ? avgSpend : 0).toStringAsFixed(2)}'
                    : 'N/A',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preferred Times'),
              trailing: Text(
                preferredTimes.isNotEmpty
                    ? preferredTimes.join(', ')
                    : 'N/A',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Favorite Restaurants'),
              subtitle: Text('${favoriteRestaurants.length} restaurants'),
            ),
            const SizedBox(height: 8),
            Text(
              'Last Updated: $lastUpdatedStr',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRowWithCopy(
    IconData icon,
    String label,
    String displayValue,
    String? copyValue,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayValue,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        if (copyValue != null && copyValue.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            color: Colors.grey[600],
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copyToClipboard(copyValue, label),
            tooltip: 'Copy $label',
          ),
      ],
    );
  }

  Future<void> _copyToClipboard(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy $label'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildErrorState(String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySnapshotCard() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('author.id', isEqualTo: widget.userId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange[300], size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Unable to load activity snapshot',
                    style: TextStyle(
                      color: Colors.red[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please try again later',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final orders = snapshot.data?.docs ?? [];
        final totalOrders = orders.length;

        Timestamp? lastOrderDate;
        DateTime? lastOrderDateTime;

        for (final doc in orders) {
          final data = doc.data() as Map<String, dynamic>;
          final createdAt = data['createdAt'] as Timestamp?;
          if (createdAt != null) {
            final orderDate = createdAt.toDate();
            if (lastOrderDateTime == null ||
                orderDate.isAfter(lastOrderDateTime)) {
              lastOrderDateTime = orderDate;
              lastOrderDate = createdAt;
            }
          }
        }

        String lastOrderText = 'No orders yet';
        if (lastOrderDate != null) {
          final date = lastOrderDate.toDate();
          lastOrderText = DateFormat('MMMM dd, yyyy').format(date);
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity Snapshot',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.shopping_cart,
                  'Total Orders',
                  totalOrders.toString(),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.calendar_today,
                  'Last Order Date',
                  lastOrderText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order History',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('restaurant_orders')
              .where('author.id', isEqualTo: widget.userId)
              .orderBy('createdAt', descending: true)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange[300], size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Unable to load order history',
                        style: TextStyle(
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please try again later',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final orders = snapshot.data?.docs ?? [];

            if (orders.isEmpty) {
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No orders found'),
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = orders[index];
                final data = doc.data() as Map<String, dynamic>;
                final orderId = doc.id;
                final status = (data['status'] ?? 'Unknown').toString();
                final createdAt = data['createdAt'] as Timestamp?;
                final total = data['total'];
                final vendor = data['vendor'] as Map<String, dynamic>?;
                final products = data['products'] as List<dynamic>? ?? [];

                double orderTotal = 0.0;
                if (total != null) {
                  if (total is num) {
                    orderTotal = total.toDouble();
                  } else if (total is String) {
                    orderTotal = double.tryParse(total) ?? 0.0;
                  }
                }

                final restaurantName =
                    vendor?['title']?.toString() ?? 'Unknown Restaurant';
                final itemCount = products.length;

                String orderDateText = 'Unknown date';
                if (createdAt != null) {
                  final date = createdAt.toDate();
                  orderDateText = DateFormat('MMM dd, yyyy • hh:mm a').format(
                    date,
                  );
                }

                final truncatedOrderId = orderId.length > 12
                    ? '${orderId.substring(0, 12)}...'
                    : orderId;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      // Could navigate to order details if needed
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      restaurantName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Order #$truncatedOrderId',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text(
                                orderDateText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.shopping_bag,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text(
                                '$itemCount item${itemCount != 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '₱${orderTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('completed') ||
        lowerStatus.contains('delivered')) {
      return Colors.green;
    } else if (lowerStatus.contains('rejected') ||
        lowerStatus.contains('cancelled')) {
      return Colors.red;
    } else if (lowerStatus.contains('pending') ||
        lowerStatus.contains('preparing')) {
      return Colors.orange;
    }
    return Colors.blue;
  }
}

