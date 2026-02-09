import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/HappyHourConfig.dart';

class HappyHourService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const String settingsDocId = 'happyHourSettings';
  static const String settingsCollection = 'settings';

  // Get current Happy Hour settings
  static Future<HappyHourSettings> getHappyHourSettings() async {
    try {
      final docSnapshot = await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return HappyHourSettings.empty();
      }

      final data = docSnapshot.data()!;
      return HappyHourSettings.fromJson(data);
    } catch (e) {
      print('Error getting Happy Hour settings: $e');
      return HappyHourSettings.empty();
    }
  }

  // Stream of Happy Hour settings for real-time updates
  static Stream<HappyHourSettings> getHappyHourSettingsStream() {
    return firestore
        .collection(settingsCollection)
        .doc(settingsDocId)
        .snapshots()
        .map((docSnapshot) {
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return HappyHourSettings.empty();
      }

      final data = docSnapshot.data()!;
      return HappyHourSettings.fromJson(data);
    });
  }

  // Save complete Happy Hour settings
  static Future<void> saveHappyHourSettings(HappyHourSettings settings) async {
    try {
      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set(settings.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Error saving Happy Hour settings: $e');
      throw Exception('Failed to save Happy Hour settings: $e');
    }
  }

  // Update master toggle
  static Future<void> updateMasterToggle(bool enabled) async {
    try {
      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set({'enabled': enabled}, SetOptions(merge: true));
    } catch (e) {
      print('Error updating master toggle: $e');
      throw Exception('Failed to update master toggle: $e');
    }
  }

  // Add new Happy Hour configuration
  static Future<void> addHappyHourConfig(HappyHourConfig config) async {
    try {
      if (!config.isValid()) {
        throw Exception('Invalid Happy Hour configuration');
      }

      final settings = await getHappyHourSettings();
      
      // Generate unique ID if not provided
      if (config.id.isEmpty) {
        config.id = firestore.collection('temp').doc().id;
      }

      // Update timestamps
      config.updatedAt = Timestamp.now();
      if (config.createdAt.seconds == 0) {
        config.createdAt = Timestamp.now();
      }

      // Add config to list
      final updatedConfigs = List<HappyHourConfig>.from(settings.configs);
      updatedConfigs.add(config);

      // Save updated settings
      final updatedSettings = HappyHourSettings(
        enabled: settings.enabled,
        configs: updatedConfigs,
      );

      await saveHappyHourSettings(updatedSettings);
    } catch (e) {
      print('Error adding Happy Hour config: $e');
      throw Exception('Failed to add Happy Hour configuration: $e');
    }
  }

  // Update existing Happy Hour configuration
  static Future<void> updateHappyHourConfig(
      String configId, HappyHourConfig config) async {
    try {
      if (!config.isValid()) {
        throw Exception('Invalid Happy Hour configuration');
      }

      final settings = await getHappyHourSettings();
      
      // Ensure ID matches
      config.id = configId;
      config.updatedAt = Timestamp.now();

      // Find and update config in list
      final updatedConfigs = settings.configs.map((c) {
        if (c.id == configId) {
          return config;
        }
        return c;
      }).toList();

      // Save updated settings
      final updatedSettings = HappyHourSettings(
        enabled: settings.enabled,
        configs: updatedConfigs,
      );

      await saveHappyHourSettings(updatedSettings);
    } catch (e) {
      print('Error updating Happy Hour config: $e');
      throw Exception('Failed to update Happy Hour configuration: $e');
    }
  }

  // Delete Happy Hour configuration
  static Future<void> deleteHappyHourConfig(String configId) async {
    try {
      final settings = await getHappyHourSettings();

      // Remove config from list
      final updatedConfigs = settings.configs
          .where((c) => c.id != configId)
          .toList();

      // Save updated settings
      final updatedSettings = HappyHourSettings(
        enabled: settings.enabled,
        configs: updatedConfigs,
      );

      await saveHappyHourSettings(updatedSettings);
    } catch (e) {
      print('Error deleting Happy Hour config: $e');
      throw Exception('Failed to delete Happy Hour configuration: $e');
    }
  }

  // Get the currently active Happy Hour configuration
  static Future<HappyHourConfig?> getActiveHappyHourConfig() async {
    try {
      final settings = await getHappyHourSettings();
      
      if (!settings.enabled || settings.configs.isEmpty) {
        return null;
      }

      final now = DateTime.now();
      final currentDay = now.weekday % 7; // 0=Sunday, 1=Monday, ..., 6=Saturday
      final currentHour = now.hour;
      final currentMinute = now.minute;
      final currentTimeMinutes = currentHour * 60 + currentMinute;

      // Find first active config
      for (var config in settings.configs) {
        // Check if today is an active day
        if (!config.activeDays.contains(currentDay)) {
          continue;
        }

        // Parse start and end times
        final startParts = config.startTime.split(':');
        final endParts = config.endTime.split(':');
        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);
        final endHour = int.parse(endParts[0]);
        final endMinute = int.parse(endParts[1]);
        
        final startTimeMinutes = startHour * 60 + startMinute;
        final endTimeMinutes = endHour * 60 + endMinute;

        // Check if current time is within range
        if (currentTimeMinutes >= startTimeMinutes && currentTimeMinutes < endTimeMinutes) {
          return config;
        }
      }

      return null;
    } catch (e) {
      print('Error checking active Happy Hour: $e');
      return null;
    }
  }

  // Format notification body based on Happy Hour config
  static String formatNotificationBody(HappyHourConfig config) {
    switch (config.promoType) {
      case 'fixed_amount':
        return '₱${config.promoValue.toStringAsFixed(0)} OFF for a limited time';
      
      case 'percentage':
        return '${config.promoValue.toStringAsFixed(0)}% OFF for a limited time';
      
      case 'free_delivery':
        return 'Free Delivery for a limited time';
      
      case 'reduced_delivery':
        return '₱${config.promoValue.toStringAsFixed(0)} delivery discount for a limited time';
      
      default:
        return 'Special discount available for a limited time';
    }
  }
}

