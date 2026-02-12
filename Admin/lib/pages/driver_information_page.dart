import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/driver_location_page.dart';
import 'package:brgy/driver_wallet_details_page.dart';
import 'package:brgy/driver_collection_details_page.dart';
import 'package:intl/intl.dart';

class DriverInformationPage extends StatefulWidget {
  final String driverId;

  const DriverInformationPage({
    Key? key,
    required this.driverId,
  }) : super(key: key);

  @override
  State<DriverInformationPage> createState() => _DriverInformationPageState();
}

class _DriverInformationPageState extends State<DriverInformationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Information'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection(USERS)
            .doc(widget.driverId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorState(
              'Failed to load driver data',
              snapshot.error.toString(),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return _buildErrorState(
              'Driver not found',
              'The driver record may have been deleted or is unavailable.',
            );
          }

          final dataRaw = snapshot.data!.data();
          if (dataRaw == null) {
            return _buildErrorState(
              'Invalid driver data',
              'The driver record exists but contains no data.',
            );
          }

          final data = dataRaw as Map<String, dynamic>;

          final firstName =
              (data['firstName'] ?? '').toString().trim();
          final lastName = (data['lastName'] ?? '').toString().trim();
          final fullName = ('$firstName $lastName').trim();
          final displayName =
              fullName.isEmpty ? 'Unknown Driver' : fullName;
          final phone = (data['phoneNumber'] ?? '').toString();
          final email = (data['email'] ?? '').toString();
          final profilePictureURL =
              (data['profilePictureURL'] ?? '').toString();
          final carName = (data['carName'] ?? 'N/A').toString();
          final carNumber = (data['carNumber'] ?? 'N/A').toString();
          final carPictureURL = (data['carPictureURL'] ?? '').toString();

          final active = (data['active'] ?? data['isActive'] ?? false) == true;
          final isAvailable = (data['isAvailable'] ?? false) == true;
          final checkedInToday = (data['checkedInToday'] ?? false) == true;
          final checkedOutToday = (data['checkedOutToday'] ?? false) == true;
          final multipleOrders = (data['multipleOrders'] ?? false) == true;
          final inProgressOrderID = data['inProgressOrderID'] as List?;
          final activeOrdersCount = inProgressOrderID?.length ?? 0;

          double walletAmount = 0.0;
          final rawWallet = data['wallet_amount'];
          if (rawWallet is num) {
            walletAmount = rawWallet.toDouble();
          } else if (rawWallet is String) {
            walletAmount = double.tryParse(rawWallet) ?? 0.0;
          }
          double walletCredit = 0.0;
          final rawCredit = data['wallet_credit'];
          if (rawCredit is num) {
            walletCredit = rawCredit.toDouble();
          } else if (rawCredit is String) {
            walletCredit = double.tryParse(rawCredit) ?? 0.0;
          }

          double? latitude;
          double? longitude;
          final loc = data['location'];
          if (loc != null) {
            if (loc is GeoPoint) {
              latitude = loc.latitude;
              longitude = loc.longitude;
            } else if (loc is Map) {
              final lat = loc['latitude'];
              final lng = loc['longitude'];
              if (lat != null && lng != null) {
                latitude = (lat is num) ? lat.toDouble() : double.tryParse('$lat');
                longitude =
                    (lng is num) ? lng.toDouble() : double.tryParse('$lng');
              }
            }
          }
          final hasLocation = latitude != null &&
              longitude != null &&
              latitude!.abs() > 0.0001 &&
              longitude!.abs() > 0.0001;

          final createdAt = data['createdAt'] as Timestamp?;

          final driverMap = {
            'id': widget.driverId,
            'firstName': firstName.isEmpty ? 'Unknown' : firstName,
            'lastName': lastName,
            'phoneNumber': phone,
          };

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(
                  displayName,
                  profilePictureURL,
                  createdAt,
                ),
                const SizedBox(height: 16),
                _buildBasicInfoCard(displayName, email, phone),
                const SizedBox(height: 16),
                _buildVehicleCard(
                  carName,
                  carNumber,
                  carPictureURL,
                ),
                const SizedBox(height: 16),
                _buildStatusCard(
                  active,
                  isAvailable,
                  checkedInToday,
                  checkedOutToday,
                  multipleOrders,
                  activeOrdersCount,
                ),
                const SizedBox(height: 16),
                _buildWalletCard(walletAmount, walletCredit),
                const SizedBox(height: 16),
                _buildQuickActionsCard(
                  context,
                  displayName,
                  hasLocation,
                  latitude,
                  longitude,
                  driverMap,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(
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
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                'Driver',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange[800],
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
            _buildInfoRow(
              Icons.email,
              'Email',
              email.isEmpty ? 'N/A' : email,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.phone,
              'Phone Number',
              phone.isEmpty ? 'No number' : phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(
    String carName,
    String carNumber,
    String carPictureURL,
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
              'Vehicle',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (carPictureURL.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  carPictureURL,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildInfoRow(Icons.directions_car, 'Car Name', carName),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.confirmation_number, 'Car Number', carNumber),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    bool active,
    bool isAvailable,
    bool checkedInToday,
    bool checkedOutToday,
    bool multipleOrders,
    int activeOrdersCount,
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
              'Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              Icons.check_circle,
              'Active',
              active ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.schedule,
              'Available',
              isAvailable ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.login,
              'Checked in today',
              checkedInToday ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.logout,
              'Checked out today',
              checkedOutToday ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.reorder,
              'Multiple orders allowed',
              multipleOrders ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.local_shipping,
              'Active orders',
              activeOrdersCount.toString(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard(double walletAmount, double walletCredit) {
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
              'Wallet Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              Icons.account_balance_wallet,
              'Balance (wallet_amount)',
              '₱${walletAmount.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.credit_card,
              'Credit (wallet_credit)',
              '₱${walletCredit.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    String fullName,
    bool hasLocation,
    double? latitude,
    double? longitude,
    Map<String, dynamic> driverMap,
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
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: hasLocation
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DriverLocationPage(
                                driverName: fullName,
                                latitude: latitude!,
                                longitude: longitude!,
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.location_on, size: 18),
                  label: const Text('View location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DriverWalletDetailsPage(
                          driver: driverMap,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet, size: 18),
                  label: const Text('Wallet details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DriverCollectionDetailsPage(
                          driverId: widget.driverId,
                          driverName: fullName,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Collection history'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
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
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
}
