import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/working_hours_model.dart';
import 'pages/edit_restaurant_schedule_page.dart';
import 'services/vendor_service.dart';

class RestaurantInfoPage extends StatefulWidget {
  const RestaurantInfoPage({
    super.key,
    required this.vendorId,
    required this.vendorData,
  });

  final String vendorId;
  final Map<String, dynamic> vendorData;

  @override
  State<RestaurantInfoPage> createState() => _RestaurantInfoPageState();
}

class _RestaurantInfoPageState extends State<RestaurantInfoPage> {
  String? _ownerEmail;
  bool _loadingEmail = true;
  late Map<String, dynamic> _vendorData;
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
    _vendorData = Map<String, dynamic>.from(widget.vendorData);
    _fetchOwnerEmail();
  }

  Future<void> _refetchVendor() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(widget.vendorId)
          .get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        setState(() {
          _vendorData = Map<String, dynamic>.from(doc.data()!);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to refresh restaurant data.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<WorkingHoursModel> _parseWorkingHours() {
    final raw = _vendorData['workingHours'];
    if (raw == null || raw is! List || raw.isEmpty) {
      return [
        WorkingHoursModel(day: 'Monday', timeslot: []),
        WorkingHoursModel(day: 'Tuesday', timeslot: []),
        WorkingHoursModel(day: 'Wednesday', timeslot: []),
        WorkingHoursModel(day: 'Thursday', timeslot: []),
        WorkingHoursModel(day: 'Friday', timeslot: []),
        WorkingHoursModel(day: 'Saturday', timeslot: []),
        WorkingHoursModel(day: 'Sunday', timeslot: []),
      ];
    }
    final result = <WorkingHoursModel>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          result.add(WorkingHoursModel.fromJson(item));
        } catch (_) {
          // skip malformed
        }
      }
    }
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final byDay = {for (final wh in result) wh.day: wh};
    return days
        .map((d) => byDay[d] ?? WorkingHoursModel(day: d, timeslot: []))
        .toList();
  }

  Future<void> _fetchOwnerEmail() async {
    final author = widget.vendorData['author'];
    if (author == null || author.toString().trim().isEmpty) {
      if (mounted) setState(() => _loadingEmail = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(author.toString())
          .get();
      if (!mounted) return;
      final email = doc.data()?['email']?.toString().trim();
      setState(() {
        _ownerEmail = email?.isNotEmpty == true ? email : null;
        _loadingEmail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _ownerEmail;
    if (email == null || email.isEmpty) return;
    try {
      await auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent.'),
          backgroundColor: Colors.green,
        ),
      );
    } on auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to send reset email'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static String _str(dynamic v) {
    if (v == null) return '—';
    return v.toString().trim();
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _openMaps(BuildContext context, double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unable to open location'),
          content: const Text('Could not open maps.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).maybePop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: SelectableText('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).maybePop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value.isEmpty ? '—' : value),
          ),
        ],
      ),
    );
  }

  Future<void> _onStatusChanged(bool value) async {
    setState(() => _updatingStatus = true);
    try {
      await VendorService().updateVendorStatus(widget.vendorId, value);
      if (!mounted) return;
      setState(() {
        _vendorData['reststatus'] = value;
        _updatingStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Restaurant is now open.' : 'Restaurant is now closed.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _updatingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorData = _vendorData;
    final title = _str(
      vendorData['title'] ?? vendorData['authorName'] ?? 'Restaurant',
    );
    final logo = _str(
      vendorData['photo'] ?? vendorData['logo'] ?? vendorData['imageUrl'],
    );
    final address = _str(
      vendorData['address'] ??
          vendorData['addressLine'] ??
          vendorData['location'] ??
          vendorData['address_line'],
    );
    final phone = _str(vendorData['phonenumber'] ?? vendorData['phone']);
    final lat = _asDouble(vendorData['latitude']);
    final lng = _asDouble(vendorData['longitude']);
    final hasLocation = lat != null &&
        lng != null &&
        lat != 0 &&
        lng != 0;

    final emailDisplay = _loadingEmail
        ? '…'
        : (_ownerEmail ?? _str(vendorData['email']));
    final emailValue = emailDisplay.isEmpty || emailDisplay == '—'
        ? 'Not linked'
        : emailDisplay;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (logo.isNotEmpty && logo != '—')
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      logo,
                      height: 160,
                      width: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.store,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            _row('Vendor ID', widget.vendorId),
            _row('Name', title),
            _row('Address', address),
            _row('Phone', phone),
            _row('Email', emailValue),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 120,
                    child: Text(
                      'Password',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SelectableText(
                          'Stored in Firebase Auth (not visible).',
                        ),
                        if (_ownerEmail != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _sendPasswordResetEmail,
                            icon: const Icon(Icons.email_outlined, size: 18),
                            label: const Text('Send password reset email'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _row('Latitude', lat?.toString() ?? '—'),
            _row('Longitude', lng?.toString() ?? '—'),
            if (hasLocation)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: OutlinedButton.icon(
                  onPressed: () => _openMaps(context, lat, lng),
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Open in maps'),
                ),
              ),
            const SizedBox(height: 24),
            _buildScheduleSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSection() {
    final restStatus = _vendorData['reststatus'] == true;
    final workingHours = _parseWorkingHours();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Restaurant open for orders',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Switch(
                  value: restStatus,
                  onChanged: _updatingStatus ? null : _onStatusChanged,
                ),
              ],
            ),
            const Divider(),
            const Text(
              'Schedule',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            ...workingHours.map((wh) {
              final slots = wh.timeslot;
              final text = slots.isEmpty
                  ? 'Closed'
                  : slots
                      .map((s) =>
                          '${s.from ?? ''} – ${s.to ?? ''}')
                      .join(', ');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        wh.day ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: slots.isEmpty ? Colors.grey : null,
                          fontStyle: slots.isEmpty ? FontStyle.italic : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => EditRestaurantSchedulePage(
                      vendorId: widget.vendorId,
                      initialWorkingHours: _parseWorkingHours(),
                      restaurantName: _str(
                        _vendorData['title'] ??
                            _vendorData['authorName'] ??
                            'Restaurant',
                      ),
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  _refetchVendor();
                }
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Edit Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
