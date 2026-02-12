import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class OrderStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Counts active customers who have no orders in restaurant_orders
  // Uses parallel batch processing to keep UI responsive
  Future<int> countActiveCustomersWithZeroOrders({
    Function(int current, int total)? onProgress,
  }) async {
    // Use COUNT to get total active customers (much faster than reading all documents)
    final AggregateQuerySnapshot totalCustomersSnap = await _firestore
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true)
        .count()
        .get();

    final totalCustomers = totalCustomersSnap.count ?? 0;

    if (totalCustomers == 0) {
      if (onProgress != null) {
        onProgress(0, 0);
      }
      return 0;
    }

    // Get customer IDs (we need IDs to check orders)
    final QuerySnapshot usersSnap = await _firestore
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true)
        .get();

    final customerIds = usersSnap.docs.map((doc) => doc.id).toList();

    if (customerIds.isEmpty) {
      if (onProgress != null) {
        onProgress(0, 0);
      }
      return 0;
    }

    int zeroCount = 0;
    int processed = 0;

    developer.log(
      "Starting zero orders count for $totalCustomers customers",
      name: "OrderStatsService",
    );

    // Report initial progress immediately (0% with total) - this is critical!
    // Call it synchronously before any delays
    if (onProgress != null) {
      onProgress(0, totalCustomers);
      // Small delay to ensure UI can process the callback
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Process in parallel batches to keep UI responsive
    const batchSize = 20; // Process 20 customers in parallel per batch
    final batches = <List<String>>[];

    // Split into batches
    for (int i = 0; i < customerIds.length; i += batchSize) {
      final end = (i + batchSize < customerIds.length)
          ? i + batchSize
          : customerIds.length;
      batches.add(customerIds.sublist(i, end));
    }

    // Process each batch in parallel
    for (final batch in batches) {
      // Process all customers in this batch in parallel
      final results = await Future.wait(
        batch.map((userId) => _checkCustomerHasOrders(userId)),
        eagerError: false, // Continue even if some fail
      );

      // Count zeros in this batch
      int batchZeroCount = 0;
      for (final hasOrders in results) {
        if (hasOrders == false) {
          zeroCount++;
          batchZeroCount++;
        }
        processed++;
      }

      // Log batch progress
      if (batchZeroCount > 0) {
        developer.log(
          "Batch processed: $batchZeroCount customers with zero orders (Total: $zeroCount/$processed)",
          name: "OrderStatsService",
        );
      }

      // Report progress and yield to UI thread
      if (onProgress != null) {
        onProgress(processed, totalCustomers);
        // Yield to UI thread between batches
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    developer.log(
      "Zero orders count completed: $zeroCount out of $totalCustomers customers",
      name: "OrderStatsService",
    );

    return zeroCount;
  }

  // Helper method to check if a customer has orders in restaurant_orders collection
  // Returns true if customer HAS orders, false if NO orders
  Future<bool> _checkCustomerHasOrders(String userId) async {
    try {
      // Prevent empty/invalid ID crash
      if (userId.isEmpty) {
        developer.log(
          "Empty userId provided to _checkCustomerHasOrders",
          name: "OrderStatsService",
        );
        return false; // Empty ID = no orders
      }

      // Add a tiny delay so low-end devices don't overload CPU
      await Future.delayed(const Duration(milliseconds: 50));

      // CRITICAL: Check restaurant_orders collection for this customer
      // Query: restaurant_orders where author.id == userId
      final AggregateQuerySnapshot orderCountSnap = await _firestore
          .collection('restaurant_orders')
          .where('author.id', isEqualTo: userId)
          .count()
          .get()
          .timeout(
        const Duration(seconds: 5), // Increased timeout
        onTimeout: () {
          developer.log(
            "Timeout checking orders for user: $userId",
            name: "OrderStatsService",
          );
          throw TimeoutException("Query timeout for user $userId");
        },
      );

      // Firestore snapshot might be null or missing count → guard it
      final int orderCount = (orderCountSnap.count ?? 0);

      // Return true if customer HAS orders, false if NO orders
      return orderCount > 0;
    } catch (e) {
      // CRITICAL FIX: Return false on error instead of true
      // This way, if there's an error checking, we assume NO orders
      // Better to undercount than overcount for zero orders
      developer.log(
        "Error checking orders for user $userId: $e",
        name: "OrderStatsService",
        error: e,
      );

      // Return false = assume NO orders (safer for zero count)
      return false;
    }
  }

  // Calculates customer repeat rate
  // Returns map with repeatCount and totalCount
  Future<Map<String, int>> calculateCustomerRepeatRate({
    Function(int current, int total)? onProgress,
  }) async {
    // Get all active customers
    final QuerySnapshot usersSnap = await _firestore
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true)
        .get();

    final totalCustomers = usersSnap.docs.length;

    if (totalCustomers == 0) {
      if (onProgress != null) {
        onProgress(0, 0);
      }
      return {'repeatCount': 0, 'totalCount': 0};
    }

    // Report initial progress
    if (onProgress != null) {
      onProgress(0, totalCustomers);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    int repeatCount = 0;
    int processed = 0;

    developer.log(
      "Starting repeat rate calculation for $totalCustomers customers",
      name: "OrderStatsService",
    );

    // Process in batches
    const batchSize = 20;
    final customerIds = usersSnap.docs.map((doc) => doc.id).toList();
    final batches = <List<String>>[];

    for (int i = 0; i < customerIds.length; i += batchSize) {
      final end = (i + batchSize < customerIds.length)
          ? i + batchSize
          : customerIds.length;
      batches.add(customerIds.sublist(i, end));
    }

    // Process each batch in parallel
    for (final batch in batches) {
      final results = await Future.wait(
        batch.map((userId) => _checkCustomerIsRepeat(userId)),
        eagerError: false,
      );

      for (final isRepeat in results) {
        if (isRepeat == true) {
          repeatCount++;
        }
        processed++;
      }

      if (onProgress != null) {
        onProgress(processed, totalCustomers);
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    developer.log(
      "Repeat rate calculation completed: $repeatCount out of $totalCustomers customers",
      name: "OrderStatsService",
    );

    return {'repeatCount': repeatCount, 'totalCount': totalCustomers};
  }

  // Helper method to check if a customer has made repeat orders within 14 days
  Future<bool> _checkCustomerIsRepeat(String userId) async {
    try {
      if (userId.isEmpty) return false;

      await Future.delayed(const Duration(milliseconds: 50));

      // Get orders for this customer in last 14 days, sorted by date
      final DateTime fourteenDaysAgo =
          DateTime.now().subtract(const Duration(days: 14)).toUtc();

      final QuerySnapshot ordersSnap = await _firestore
          .collection('restaurant_orders')
          .where('author.id', isEqualTo: userId)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(fourteenDaysAgo))
          .orderBy('createdAt')
          .get()
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException("Query timeout for user $userId");
        },
      );

      // Customer is a repeat customer if they have 2+ orders in last 14 days
      return ordersSnap.docs.length >= 2;
    } catch (e) {
      developer.log(
        "Error checking repeat status for user $userId: $e",
        name: "OrderStatsService",
        error: e,
      );
      return false;
    }
  }
}
