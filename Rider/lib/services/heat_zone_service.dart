import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// Service to manage and populate driver heat zones for the Hotspots feature
class HeatZoneService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'driver_heat_zones';

  /// Initialize heat zones - creates sample data if collection is empty
  static Future<void> initializeHeatZones() async {
    try {
      print('🗺️ Checking driver_heat_zones collection...');

      final snapshot = await _firestore
          .collection(_collectionName)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        print('📍 driver_heat_zones is empty. Creating sample data...');
        await _createSampleHeatZones();
      } else {
        print('✅ driver_heat_zones already has data (${snapshot.docs.length}+ documents)');
      }
    } catch (e) {
      print('❌ Error initializing heat zones: $e');
      // Non-blocking - app continues even if this fails
    }
  }

  /// Create sample heat zone data for testing
  static Future<void> _createSampleHeatZones() async {
    try {
      final batch = _firestore.batch();
      final now = DateTime.now();
      final random = Random();

      // Base coordinates (Manila area - adjust based on your location)
      final List<Map<String, dynamic>> sampleZones = [
        {
          'lat': 14.5995,
          'lng': 120.9842,
          'weight': 5,
          'timeSlot': 'all',
          'description': 'Makati CBD',
        },
        {
          'lat': 14.6091,
          'lng': 121.0223,
          'weight': 4,
          'timeSlot': 'lunch',
          'description': 'Ortigas Center',
        },
        {
          'lat': 14.5547,
          'lng': 121.0244,
          'weight': 3,
          'timeSlot': 'dinner',
          'description': 'BGC',
        },
        {
          'lat': 14.5764,
          'lng': 121.0851,
          'weight': 4,
          'timeSlot': 'all',
          'description': 'Eastwood City',
        },
        {
          'lat': 14.6488,
          'lng': 121.0509,
          'weight': 5,
          'timeSlot': 'dinner',
          'description': 'Quezon City Circle',
        },
        {
          'lat': 14.5529,
          'lng': 121.0473,
          'weight': 3,
          'timeSlot': 'lunch',
          'description': 'Makati Avenue',
        },
        {
          'lat': 14.5899,
          'lng': 120.9797,
          'weight': 2,
          'timeSlot': 'all',
          'description': 'Manila Bay Area',
        },
        {
          'lat': 14.6760,
          'lng': 121.0437,
          'weight': 4,
          'timeSlot': 'dinner',
          'description': 'SM North EDSA',
        },
        {
          'lat': 14.5378,
          'lng': 121.0199,
          'weight': 3,
          'timeSlot': 'lunch',
          'description': 'Rockwell Center',
        },
        {
          'lat': 14.6507,
          'lng': 121.0494,
          'weight': 2,
          'timeSlot': 'all',
          'description': 'Cubao',
        },
      ];

      // Create documents with timestamps spread over last 7-10 days
      for (int i = 0; i < sampleZones.length; i++) {
        final zone = sampleZones[i];
        final docRef = _firestore.collection(_collectionName).doc();
        
        // Random date within last 7-10 days
        final daysAgo = 7 + random.nextInt(4); // 7 to 10 days ago
        final timestamp = now.subtract(Duration(days: daysAgo));

        batch.set(docRef, {
          'lat': zone['lat'],
          'lng': zone['lng'],
          'weight': zone['weight'],
          'timeSlot': zone['timeSlot'],
          'lastUpdated': Timestamp.fromDate(timestamp),
          'description': zone['description'], // Optional field for reference
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('✅ Created ${sampleZones.length} sample heat zones');
    } catch (e) {
      print('❌ Error creating sample heat zones: $e');
    }
  }

  /// Update or add a heat zone based on completed order location
  /// This can be called after an order is completed to build real heat map data
  static Future<void> addHeatZoneFromOrder({
    required double lat,
    required double lng,
    required String timeSlot, // 'lunch', 'dinner', or 'all'
    int weight = 1,
  }) async {
    try {
      // Check if a nearby zone already exists (within ~500m)
      final nearbyZones = await _firestore
          .collection(_collectionName)
          .where('lat', isGreaterThan: lat - 0.005)
          .where('lat', isLessThan: lat + 0.005)
          .get();

      DocumentReference? existingZone;
      for (var doc in nearbyZones.docs) {
        final data = doc.data();
        final zoneLng = data['lng'] as double;
        if ((zoneLng - lng).abs() < 0.005 && data['timeSlot'] == timeSlot) {
          existingZone = doc.reference;
          break;
        }
      }

      if (existingZone != null) {
        // Update existing zone - increment weight (max 5)
        final doc = await existingZone.get();
        final currentWeight = (doc.data() as Map<String, dynamic>)['weight'] as int;
        final newWeight = (currentWeight + 1).clamp(1, 5);
        
        await existingZone.update({
          'weight': newWeight,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('📍 Updated existing heat zone with new weight: $newWeight');
      } else {
        // Create new zone
        await _firestore.collection(_collectionName).add({
          'lat': lat,
          'lng': lng,
          'weight': weight.clamp(1, 5),
          'timeSlot': timeSlot,
          'lastUpdated': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('📍 Created new heat zone at ($lat, $lng)');
      }
    } catch (e) {
      print('❌ Error adding heat zone from order: $e');
    }
  }

  /// Clean up old heat zones (older than 30 days)
  static Future<void> cleanupOldHeatZones() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final oldZones = await _firestore
          .collection(_collectionName)
          .where('lastUpdated', isLessThan: Timestamp.fromDate(thirtyDaysAgo))
          .get();

      if (oldZones.docs.isEmpty) {
        print('🧹 No old heat zones to clean up');
        return;
      }

      final batch = _firestore.batch();
      for (var doc in oldZones.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('🧹 Cleaned up ${oldZones.docs.length} old heat zones');
    } catch (e) {
      print('❌ Error cleaning up old heat zones: $e');
    }
  }

  /// Get time slot based on current hour
  static String getCurrentTimeSlot() {
    final hour = DateTime.now().hour;
    if (hour >= 11 && hour < 15) {
      return 'lunch';
    } else if (hour >= 17 && hour < 22) {
      return 'dinner';
    } else {
      return 'all';
    }
  }
}

