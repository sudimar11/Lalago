import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/VoucherRule.dart';
import '../constants.dart';

class VoucherRewardService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch driver incentive rules from Firebase
  static Future<DriverIncentiveRules?> getDriverIncentiveRules() async {
    print('🔥🔥🔥 DEBUG: getDriverIncentiveRules() CALLED!!! 🔥🔥🔥');
    try {
      print('🔍 DEBUG: Fetching driver_incentive_rules from Firebase...');

      final doc = await _firestore
          .collection(Setting)
          .doc('driver_incentive_rules')
          .get();

      print('🔍 DEBUG: Document exists: ${doc.exists}');

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        print('🔍 DEBUG: Raw data from Firebase: $data');

        // Try both versions (with and without space) to handle trailing spaces in Firebase field names
        final active = data['active'] ?? data['active '];
        final attendanceWindow =
            data['attendanceWindow'] ?? data['attendanceWindow '];
        final voucherRules = data['voucherRules'] ?? data['voucherRules '];

        print('🔍 DEBUG: active field: $active');
        print('🔍 DEBUG: attendanceWindow field: $attendanceWindow');
        print('🔍 DEBUG: voucherRules field: $voucherRules');

        // Create the data map with clean keys
        final cleanedData = {
          'active': active,
          'attendanceWindow': attendanceWindow,
          'voucherRules': voucherRules,
        };

        final rules = DriverIncentiveRules.fromJson(cleanedData);

        // ADD THESE DEBUG LINES:
        print('🔍 DEBUG: Raw voucherRules from Firebase: $voucherRules');
        if (voucherRules is List) {
          print(
              '🔍 DEBUG: voucherRules is List with ${voucherRules.length} items');
          for (int i = 0; i < voucherRules.length; i++) {
            print('🔍 DEBUG: Rule $i raw data: ${voucherRules[i]}');
          }
        } else {
          print(
              '🔍 DEBUG: voucherRules is not a List, it is: ${voucherRules.runtimeType}');
        }

        print('🔍 DEBUG: Parsed rules - active: ${rules.active}');
        print(
            '🔍 DEBUG: Parsed rules - attendanceWindow: ${rules.attendanceWindow}');
        print(
            '🔍 DEBUG: Parsed rules - voucherRules count: ${rules.voucherRules.length}');
        print('🔍 DEBUG: Parsed rules details:');
        for (int i = 0; i < rules.voucherRules.length; i++) {
          final rule = rules.voucherRules[i];
          print(
              '🔍 DEBUG:   Parsed Rule $i: min=${rule.minDeliveries}, max=${rule.maxDeliveries}, amount=${rule.voucherAmount}');
        }

        // Check if voucher rules are empty and provide fallback
        if (rules.voucherRules.isEmpty) {
          print(
              '⚠️ WARNING: No voucher rules found in Firebase, using default rules');
          return _getDefaultDriverIncentiveRules();
        }

        return rules;
      } else {
        print(
            '❌ DEBUG: Document does not exist or has no data, using default rules');
        return _getDefaultDriverIncentiveRules();
      }
    } catch (e) {
      print('❌ Error fetching driver incentive rules: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      print('⚠️ Using default rules as fallback');
      return _getDefaultDriverIncentiveRules();
    }
  }

  /// Get default driver incentive rules when Firebase document is missing or empty
  static DriverIncentiveRules _getDefaultDriverIncentiveRules() {
    print('🔧 Creating default driver incentive rules...');

    final defaultRules = DriverIncentiveRules(
      active: true,
      attendanceWindow: 6,
      voucherRules: [
        VoucherRule(
          minDeliveries: 5,
          maxDeliveries: 9,
          voucherAmount: 100.0,
        ),
        VoucherRule(
          minDeliveries: 10,
          maxDeliveries: 14,
          voucherAmount: 200.0,
        ),
        VoucherRule(
          minDeliveries: 15,
          maxDeliveries: 19,
          voucherAmount: 300.0,
        ),
        VoucherRule(
          minDeliveries: 20,
          maxDeliveries: 24,
          voucherAmount: 500.0,
        ),
        VoucherRule(
          minDeliveries: 25,
          maxDeliveries: 999,
          voucherAmount: 750.0,
        ),
      ],
    );

    print(
        '✅ Default rules created with ${defaultRules.voucherRules.length} voucher rules');
    return defaultRules;
  }

  /// Create sample voucher rules document in Firebase if it doesn't exist
  static Future<void> createSampleVoucherRulesDocument() async {
    try {
      print('🔧 Creating sample voucher rules document in Firebase...');

      final docRef =
          _firestore.collection(Setting).doc('driver_incentive_rules');
      final doc = await docRef.get();

      if (!doc.exists) {
        final sampleRules = _getDefaultDriverIncentiveRules();
        await docRef.set(sampleRules.toJson());
        print('✅ Sample voucher rules document created successfully');
      } else {
        print('ℹ️ Voucher rules document already exists');
      }
    } catch (e) {
      print('❌ Error creating sample voucher rules document: $e');
    }
  }

  /// Count completed deliveries for a driver today
  static Future<int> getTodayDeliveryCount(String driverId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      final querySnapshot = await _firestore
          .collection(ORDERS)
          .where('driverID', isEqualTo: driverId)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .get();

      // Filter by date manually to handle cases where deliveredAt might not be set
      final filteredDocs = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final deliveredAt = data['deliveredAt'] as Timestamp?;
        final createdAt = data['createdAt'] as Timestamp?;
        final triggerDelivery = data['triggerDelevery'] as Timestamp?;

        // Use deliveredAt if available, otherwise fall back to createdAt or triggerDelivery
        final timestamp = deliveredAt ?? createdAt ?? triggerDelivery;

        if (timestamp == null) {
          return false;
        }

        final orderDate = timestamp.toDate();
        return orderDate.isAfter(startOfDay) && orderDate.isBefore(endOfDay);
      }).toList();

      return filteredDocs.length;
    } catch (e) {
      print('❌ Error counting today deliveries: $e');
      return 0;
    }
  }

  /// Count completed deliveries for a driver within attendance window
  static Future<int> getAttendanceWindowDeliveryCount(
      String driverId, int windowDays) async {
    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: windowDays - 1));
      final startOfWindow =
          DateTime(startDate.year, startDate.month, startDate.day);

      print('🔍 DEBUG: ===== VOUCHER SERVICE DEBUG START =====');
      print('🔍 DEBUG: Driver ID: $driverId');
      print('🔍 DEBUG: Collection: $ORDERS');
      print('🔍 DEBUG: Status: $ORDER_STATUS_COMPLETED');
      print('🔍 DEBUG: Window days: $windowDays');
      print('🔍 DEBUG: Start of window: ${startOfWindow.toIso8601String()}');
      print('🔍 DEBUG: Current time: ${now.toIso8601String()}');

      final querySnapshot = await _firestore
          .collection(ORDERS)
          .where('driverID', isEqualTo: driverId)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .get();

      print(
          '🔍 DEBUG: Found ${querySnapshot.docs.length} completed orders (without date filter)');

      // Debug all completed orders first
      print('🔍 DEBUG: All completed orders for this driver:');
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print('🔍 DEBUG: Order ${doc.id}:');
        print('🔍 DEBUG:   - driverID: ${data['driverID']}');
        print('🔍 DEBUG:   - status: ${data['status']}');
        print('🔍 DEBUG:   - deliveredAt: ${data['deliveredAt']}');
        print('🔍 DEBUG:   - createdAt: ${data['createdAt']}');
        print('🔍 DEBUG:   - triggerDelevery: ${data['triggerDelevery']}');
      }

      // Filter by date manually to handle cases where deliveredAt might not be set
      final filteredDocs = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final deliveredAt = data['deliveredAt'] as Timestamp?;
        final createdAt = data['createdAt'] as Timestamp?;
        final triggerDelivery = data['triggerDelevery'] as Timestamp?;

        // Use deliveredAt if available, otherwise fall back to createdAt or triggerDelivery
        final timestamp = deliveredAt ?? createdAt ?? triggerDelivery;

        if (timestamp == null) {
          print(
              '🔍 DEBUG: Order ${doc.id} has no deliveredAt, createdAt, or triggerDelevery field');
          return false;
        }

        final deliveredDate = timestamp.toDate();
        final isInRange = deliveredDate.isAfter(startOfWindow) ||
            deliveredDate.isAtSameMomentAs(startOfWindow);

        if (!isInRange) {
          print(
              '🔍 DEBUG: Order ${doc.id} timestamp ${deliveredDate.toIso8601String()} is outside range');
        }

        return isInRange;
      }).toList();

      print(
          '🔍 DEBUG: Found ${filteredDocs.length} completed orders (with date filter)');

      // Debug: Print filtered order details
      print('🔍 DEBUG: Orders that passed the date filter:');
      for (var doc in filteredDocs) {
        final data = doc.data();
        final deliveredAt = data['deliveredAt'] as Timestamp?;
        final createdAt = data['createdAt'] as Timestamp?;
        final triggerDelivery = data['triggerDelevery'] as Timestamp?;
        final timestamp = deliveredAt ?? createdAt ?? triggerDelivery;

        String timestampSource = 'unknown';
        if (deliveredAt != null)
          timestampSource = 'deliveredAt';
        else if (createdAt != null)
          timestampSource = 'createdAt';
        else if (triggerDelivery != null) timestampSource = 'triggerDelevery';

        print(
            '🔍 DEBUG: Order ${doc.id} - driverID: ${data['driverID']}, status: ${data['status']}, timestamp: ${timestamp?.toDate().toIso8601String()} (from $timestampSource)');
      }

      print('🔍 DEBUG: ===== VOUCHER SERVICE DEBUG END =====');
      return filteredDocs.length;
    } catch (e) {
      print('❌ Error counting attendance window deliveries: $e');
      return 0;
    }
  }

  /// Calculate voucher amount based on delivery count and rules
  static Future<double> calculateVoucherAmount(String driverId) async {
    try {
      print('🎁 DEBUG: Calculating voucher amount for driver: $driverId');

      final rules = await getDriverIncentiveRules();
      if (rules == null || !rules.active) {
        print('⚠️ Driver incentive rules not active or not found');
        return 0.0;
      }

      print(
          '🎁 DEBUG: Rules found - active: ${rules.active}, window: ${rules.attendanceWindow} days');
      print('🎁 DEBUG: Voucher rules: ${rules.voucherRules.length} rules');

      // Count deliveries within the attendance window
      final deliveryCount = await getAttendanceWindowDeliveryCount(
          driverId, rules.attendanceWindow);

      print(
          '📊 Driver $driverId has $deliveryCount deliveries in ${rules.attendanceWindow} days');

      // Find matching voucher rule
      final voucherRule = rules.getVoucherRuleForDeliveryCount(deliveryCount);
      if (voucherRule != null) {
        print(
            '🎁 Voucher rule matched: ${voucherRule.minDeliveries}-${voucherRule.maxDeliveries} deliveries = ₱${voucherRule.voucherAmount}');
        return voucherRule.voucherAmount;
      }

      print('❌ No voucher rule matched for $deliveryCount deliveries');
      print('🎁 Available rules:');
      for (var rule in rules.voucherRules) {
        print(
            '🎁   - ${rule.minDeliveries}-${rule.maxDeliveries} deliveries = ₱${rule.voucherAmount}');
      }

      return 0.0;
    } catch (e) {
      print('❌ Error calculating voucher amount: $e');
      return 0.0;
    }
  }

  /// Award voucher to driver and update their wallet
  static Future<bool> awardVoucherToDriver(
      String driverId, double voucherAmount) async {
    try {
      if (voucherAmount <= 0) {
        print('⚠️ Voucher amount is zero or negative, skipping award');
        return false;
      }

      final userRef = _firestore.collection(USERS).doc(driverId);

      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
          throw Exception('User document not found');
        }

        final userData = userDoc.data()!;
        final currentWalletAmount =
            (userData['wallet_amount'] ?? 0.0).toDouble();
        final currentTotalVouchers =
            (userData['totalVouchers'] ?? 0.0).toDouble();
        final currentTodayVoucherEarned =
            (userData['todayVoucherEarned'] ?? 0.0).toDouble();

        // Update wallet amount
        transaction.update(userRef, {
          'wallet_amount': currentWalletAmount + voucherAmount,
          'totalVouchers': currentTotalVouchers + voucherAmount,
          'todayVoucherEarned': currentTodayVoucherEarned + voucherAmount,
        });

        // Log voucher transaction
        final voucherLogRef = _firestore.collection(Wallet).doc();
        transaction.set(voucherLogRef, {
          'user_id': driverId,
          'amount': voucherAmount,
          'date': Timestamp.fromDate(DateTime.now()),
          'payment_method': 'Voucher Reward',
          'payment_status': 'success',
          'transactionUser': 'driver',
          'isTopUp': true,
          'note': 'Driver Incentive Voucher',
          'driverEarnings': voucherAmount,
          'walletType': 'earning',
        });
      });

      print(
          '✅ Voucher of ₱${voucherAmount.toStringAsFixed(0)} awarded to driver $driverId');
      return true;
    } catch (e) {
      print('❌ Error awarding voucher to driver: $e');
      return false;
    }
  }

  /// Process voucher reward when driver checks out
  static Future<Map<String, dynamic>> processCheckOutVoucher(
      String driverId) async {
    try {
      print('🔄 Processing checkout voucher for driver: $driverId');

      final voucherAmount = await calculateVoucherAmount(driverId);
      bool voucherAwarded = false;

      if (voucherAmount > 0) {
        voucherAwarded = await awardVoucherToDriver(driverId, voucherAmount);
      }

      return {
        'voucherAmount': voucherAmount,
        'voucherAwarded': voucherAwarded,
        'success': true,
      };
    } catch (e) {
      print('❌ Error processing checkout voucher: $e');
      return {
        'voucherAmount': 0.0,
        'voucherAwarded': false,
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get voucher summary for display
  static Future<Map<String, dynamic>> getVoucherSummary(String driverId) async {
    try {
      print('🔍 DEBUG: getVoucherSummary called for driver: $driverId');

      print('🔍 DEBUG: About to call getDriverIncentiveRules()...');
      DriverIncentiveRules? rules;
      try {
        rules = await getDriverIncentiveRules();
        print(
            '🔍 DEBUG: getDriverIncentiveRules() completed, rules: ${rules != null ? "found" : "null"}');
        print('🔍 DEBUG: Driver incentive rules: ${rules?.active}');
      } catch (e) {
        print('❌ ERROR in getDriverIncentiveRules(): $e');
        print('❌ Stack trace: ${StackTrace.current}');
        // Use default rules as fallback
        rules = _getDefaultDriverIncentiveRules();
      }

      // Use the actual attendance window from Firebase rules, fallback to default
      int attendanceWindow = rules?.attendanceWindow ?? 6;

      print(
          '🔍 DEBUG: Calling getAttendanceWindowDeliveryCount with window: $attendanceWindow');
      final deliveryCount =
          await getAttendanceWindowDeliveryCount(driverId, attendanceWindow);
      print('🔍 DEBUG: Final delivery count: $deliveryCount');

      // If no rules or inactive, return delivery count with inactive status
      if (rules == null || !rules.active) {
        print(
            '🔍 DEBUG: Voucher system is not active, but delivery count calculated');
        return {
          'active': false,
          'deliveryCount': deliveryCount,
          'attendanceWindow': attendanceWindow, // Use actual window
          'currentVoucherAmount': 0.0,
          'nextVoucherRule': null,
          'qualifiesForVoucher': false,
        };
      }

      final voucherRule = rules.getVoucherRuleForDeliveryCount(deliveryCount);
      final nextRule = _getNextVoucherRule(rules.voucherRules, deliveryCount);

      // ADD THESE DEBUG LINES:
      print('🔍 DEBUG: Delivery count: $deliveryCount');
      print('🔍 DEBUG: Available voucher rules:');
      for (int i = 0; i < rules.voucherRules.length; i++) {
        final rule = rules.voucherRules[i];
        print(
            '🔍 DEBUG:   Rule $i: minDeliveries=${rule.minDeliveries}, maxDeliveries=${rule.maxDeliveries}, amount=${rule.voucherAmount}');
        print(
            '🔍 DEBUG:   Does ${deliveryCount} match? ${rule.appliesToDeliveryCount(deliveryCount)}');
      }
      print(
          '🔍 DEBUG: Matched voucher rule: ${voucherRule?.voucherAmount ?? "NULL"}');
      print('🔍 DEBUG: Qualifies for voucher: ${voucherRule != null}');

      return {
        'active': true,
        'deliveryCount': deliveryCount,
        'attendanceWindow': attendanceWindow, // Use actual window
        'currentVoucherAmount': voucherRule?.voucherAmount ?? 0.0,
        'nextVoucherRule': nextRule,
        'qualifiesForVoucher': voucherRule != null,
      };
    } catch (e) {
      print('❌ Error getting voucher summary: $e');
      return {
        'active': false,
        'error': e.toString(),
      };
    }
  }

  /// Helper method to find the next voucher rule
  static VoucherRule? _getNextVoucherRule(
      List<VoucherRule> rules, int currentCount) {
    // Sort rules by minDeliveries
    final sortedRules = List<VoucherRule>.from(rules);
    sortedRules.sort((a, b) => a.minDeliveries.compareTo(b.minDeliveries));

    // Find the next rule that the driver hasn't reached yet
    for (var rule in sortedRules) {
      if (rule.minDeliveries > currentCount) {
        return rule;
      }
    }

    return null; // Driver has reached the highest tier
  }
}
