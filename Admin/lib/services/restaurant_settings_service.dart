import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Settings for order dispatch per restaurant (device status, SMS, timeout).
class RestaurantOrderSettings {
  RestaurantOrderSettings({
    required this.hasDevice,
    this.deviceType,
    this.contactNumber,
    this.smsTimeoutMinutes = 5,
    required this.allowAdminOverride,
    this.updatedAt,
    this.updatedBy,
  });

  final bool hasDevice;
  final String? deviceType; // mobile_app | web_portal | tablet
  final String? contactNumber; // +639171234567
  final int smsTimeoutMinutes;
  final bool allowAdminOverride;
  final Timestamp? updatedAt;
  final String? updatedBy;

  factory RestaurantOrderSettings.fromFirestore(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return RestaurantOrderSettings(
        hasDevice: true,
        allowAdminOverride: false,
      );
    }
    return RestaurantOrderSettings(
      hasDevice: data['hasDevice'] as bool? ?? true,
      deviceType: data['deviceType'] as String?,
      contactNumber: (data['contactNumber'] as String?)?.trim(),
      smsTimeoutMinutes: (data['smsTimeoutMinutes'] as num?)?.toInt() ?? 5,
      allowAdminOverride: data['allowAdminOverride'] as bool? ?? false,
      updatedAt: data['updatedAt'] as Timestamp?,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'hasDevice': hasDevice,
        'deviceType': deviceType,
        'contactNumber': contactNumber,
        'smsTimeoutMinutes': smsTimeoutMinutes,
        'allowAdminOverride': allowAdminOverride,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      };

  RestaurantOrderSettings copyWith({
    bool? hasDevice,
    String? deviceType,
    String? contactNumber,
    int? smsTimeoutMinutes,
    bool? allowAdminOverride,
  }) =>
      RestaurantOrderSettings(
        hasDevice: hasDevice ?? this.hasDevice,
        deviceType: deviceType ?? this.deviceType,
        contactNumber: contactNumber ?? this.contactNumber,
        smsTimeoutMinutes: smsTimeoutMinutes ?? this.smsTimeoutMinutes,
        allowAdminOverride: allowAdminOverride ?? this.allowAdminOverride,
        updatedAt: this.updatedAt,
        updatedBy: this.updatedBy,
      );
}

/// Service for reading and writing restaurant order settings.
class RestaurantSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _docId = 'order_config';

  DocumentReference _settingsRef(String vendorId) =>
      _firestore.collection('vendors').doc(vendorId).collection('settings').doc(_docId);

  /// Get settings for a vendor. Returns defaults if document is missing.
  Future<RestaurantOrderSettings> getSettings(String vendorId) async {
    final doc = await _settingsRef(vendorId).get();
    if (!doc.exists || doc.data() == null) {
      return RestaurantOrderSettings(
        hasDevice: true,
        allowAdminOverride: false,
      );
    }
    return RestaurantOrderSettings.fromFirestore(
      doc.data() as Map<String, dynamic>,
    );
  }

  /// Stream settings for real-time UI updates.
  Stream<RestaurantOrderSettings> streamSettings(String vendorId) {
    return _settingsRef(vendorId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return RestaurantOrderSettings(
          hasDevice: true,
          allowAdminOverride: false,
        );
      }
      return RestaurantOrderSettings.fromFirestore(
        snap.data() as Map<String, dynamic>,
      );
    });
  }

  /// Save settings to Firestore.
  Future<void> saveSettings(
    String vendorId,
    RestaurantOrderSettings settings,
  ) async {
    await _settingsRef(vendorId).set(
      settings.toFirestore(),
      SetOptions(merge: true),
    );
  }

  /// Update acceptance settings on the vendor document.
  Future<void> updateAcceptanceSettings(
    String vendorId, {
    required bool autoPauseEnabled,
    int consecutiveMissesThreshold = 2,
    int timerSeconds = 180,
  }) async {
    await _firestore.collection('vendors').doc(vendorId).update({
      'acceptanceSettings.autoPauseEnabled': autoPauseEnabled,
      'acceptanceSettings.consecutiveMissesThreshold':
          consecutiveMissesThreshold,
      'acceptanceSettings.timerSeconds': timerSeconds,
    });
  }
}
