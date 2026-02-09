import 'dart:io';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/coupon.dart';

class CouponService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final Reference storage = FirebaseStorage.instance.ref();
  static const String ordersCollection = 'restaurant_orders';

  // Get all coupons, ordered by creation date
  static Future<List<Coupon>> getCoupons({bool includeDeleted = false}) async {
    try {
      Query query = firestore.collection(COUPONS);

      if (!includeDeleted) {
        query = query.where('isDeleted', isEqualTo: false);
      }

      query = query.orderBy('createdAt', descending: true);

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Coupon.fromJson(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      log('Error getting coupons: $e');
      return [];
    }
  }

  // Stream of coupons for real-time updates
  static Stream<List<Coupon>> getCouponsStream({bool includeDeleted = false}) {
    Query query = firestore.collection(COUPONS);

    if (!includeDeleted) {
      query = query.where('isDeleted', isEqualTo: false);
    }

    query = query.orderBy('createdAt', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Coupon.fromJson(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    });
  }

  // Get single coupon by ID
  static Future<Coupon?> getCoupon(String couponId) async {
    try {
      final doc = await firestore.collection(COUPONS).doc(couponId).get();
      if (doc.exists && doc.data() != null) {
        return Coupon.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      log('Error getting coupon: $e');
      return null;
    }
  }

  // Get coupon by code
  static Future<Coupon?> getCouponByCode(String code) async {
    try {
      final snapshot = await firestore
          .collection(COUPONS)
          .where('code', isEqualTo: code)
          .where('isDeleted', isEqualTo: false)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return Coupon.fromJson(doc.data(), doc.id);
      }
      return null;
    } catch (e) {
      log('Error getting coupon by code: $e');
      return null;
    }
  }

  // Create new coupon
  static Future<String> createCoupon(Coupon coupon) async {
    try {
      log('--- START: Creating new coupon in Firestore ---');
      if (!coupon.isValid()) {
        throw Exception('Invalid coupon data');
      }

      // Check if code already exists
      final existingCoupon = await getCouponByCode(coupon.code);
      if (existingCoupon != null) {
        throw Exception('Coupon code already exists');
      }

      final docRef = firestore.collection(COUPONS).doc();
      coupon.id = docRef.id;
      coupon.createdAt = Timestamp.now();
      coupon.updatedAt = Timestamp.now();

      log('Document ID: ${docRef.id}');
      log('Collection: $COUPONS');
      log('Coupon data: ${coupon.toJson()}');

      log('Saving to Firestore...');
      await docRef.set(coupon.toJson());

      log('--- SUCCESS: Coupon created successfully with ID: ${docRef.id} ---');
      return docRef.id;
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to create coupon in Firestore ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to create coupon: $e');
    }
  }

  // Update existing coupon
  static Future<void> updateCoupon(Coupon coupon) async {
    try {
      log('--- START: Updating existing coupon in Firestore ---');
      if (!coupon.isValid()) {
        throw Exception('Invalid coupon data');
      }

      // Check if code already exists (excluding current coupon)
      final existingCoupon = await getCouponByCode(coupon.code);
      if (existingCoupon != null && existingCoupon.id != coupon.id) {
        throw Exception('Coupon code already exists');
      }

      coupon.updatedAt = Timestamp.now();

      log('Document ID: ${coupon.id}');
      log('Collection: $COUPONS');
      log('Coupon data: ${coupon.toJson()}');

      log('Updating in Firestore...');
      await firestore.collection(COUPONS).doc(coupon.id).update(coupon.toJson());

      log('--- SUCCESS: Coupon updated successfully ---');
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to update coupon in Firestore ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to update coupon: $e');
    }
  }

  // Soft delete coupon
  static Future<void> deleteCoupon(String couponId) async {
    try {
      await firestore.collection(COUPONS).doc(couponId).update({
        'isDeleted': true,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      log('Error deleting coupon: $e');
      throw Exception('Failed to delete coupon: $e');
    }
  }

  // Toggle enable/disable
  static Future<void> toggleEnabled(String couponId, bool isEnabled) async {
    try {
      await firestore.collection(COUPONS).doc(couponId).update({
        'isEnabled': isEnabled,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      log('Error toggling coupon enabled: $e');
      throw Exception('Failed to toggle coupon: $e');
    }
  }

  // Upload coupon image to Firebase Storage
  static Future<String> uploadCouponImage(File image) async {
    try {
      log('--- START: Uploading coupon image to Firebase Storage ---');
      final uuid = const Uuid().v4();
      log('Generated UUID: $uuid');
      log('Original image path: ${image.path}');

      log('Compressing image...');
      final compressedImage = await _compressImage(image);
      log('Image compressed successfully: ${compressedImage.path}');

      final storagePath = '$STORAGE_COUPONS/$uuid.jpg';
      log('Storage path: $storagePath');
      final Reference upload = storage.child(storagePath);

      log('Creating upload task with metadata...');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final UploadTask uploadTask = upload.putFile(compressedImage, metadata);
      log('Upload task created successfully');

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        log('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      log('Waiting for upload to complete...');
      await uploadTask.whenComplete(() {});
      log('Upload completed, getting download URL...');

      final downloadUrl = await (await uploadTask).ref.getDownloadURL();
      log('Download URL obtained: $downloadUrl');
      log('--- SUCCESS: Coupon image uploaded successfully ---');

      return downloadUrl.toString();
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to upload coupon image ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to upload coupon image: $e');
    }
  }

  // Delete image from Firebase Storage
  static Future<void> deleteCouponImage(String imageUrl) async {
    try {
      // Extract path from URL
      final uri = Uri.parse(imageUrl);
      final path = uri.pathSegments.last;
      final fullPath = '$STORAGE_COUPONS/$path';

      await storage.child(fullPath).delete();
    } catch (e) {
      log('Error deleting coupon image: $e');
      // Don't throw - image might already be deleted
    }
  }

  // Get usage statistics
  static Future<CouponUsageStats> getCouponUsageStats(String couponCode) async {
    try {
      // Query completed orders with the coupon applied
      final querySnapshot = await firestore
          .collection(ordersCollection)
          .where('status', isEqualTo: 'Order Completed')
          .where('appliedCouponId', isEqualTo: couponCode)
          .get();

      final orders = querySnapshot.docs;
      final totalUsage = orders.length;

      // Extract unique user IDs
      final userIds = <String>{};
      double totalDiscountCost = 0.0;
      final affectedOrders = <Map<String, dynamic>>[];

      for (var orderDoc in orders) {
        final orderData = orderDoc.data();
        final userId = orderData['authorID'] ??
            orderData['userId'] ??
            orderData['user_id'] ??
            '';
        if (userId.isNotEmpty) {
          userIds.add(userId);
        }

        final discountAmount = (orderData['couponDiscountAmount'] is num)
            ? (orderData['couponDiscountAmount'] as num).toDouble()
            : 0.0;
        totalDiscountCost += discountAmount;

        affectedOrders.add({
          'orderId': orderDoc.id,
          'userId': userId,
          'discountAmount': discountAmount,
          'createdAt': orderData['createdAt'],
          'deliveredAt': orderData['deliveredAt'] ?? orderData['completedAt'],
          'orderTotal': orderData['total'] ?? orderData['orderTotal'] ?? 0.0,
          'couponImageUrl': orderData['couponImageUrl'],
        });
      }

      // Sort orders by date (newest first)
      affectedOrders.sort((a, b) {
        final aDate = _getTimestamp(a['deliveredAt'] ?? a['createdAt']);
        final bDate = _getTimestamp(b['deliveredAt'] ?? b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return CouponUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    } catch (e) {
      log('Error getting coupon usage stats: $e');
      return CouponUsageStats(
        totalUsage: 0,
        uniqueUsers: 0,
        totalDiscountCost: 0.0,
        affectedOrders: [],
        userIds: [],
      );
    }
  }

  // Get stream of usage statistics
  static Stream<CouponUsageStats> getCouponUsageStatsStream(
      String couponCode) {
    return firestore
        .collection(ordersCollection)
        .where('status', isEqualTo: 'Order Completed')
        .where('appliedCouponId', isEqualTo: couponCode)
        .snapshots()
        .asyncMap((snapshot) async {
      final orders = snapshot.docs;
      final totalUsage = orders.length;

      final userIds = <String>{};
      double totalDiscountCost = 0.0;
      final affectedOrders = <Map<String, dynamic>>[];

      for (var orderDoc in orders) {
        final orderData = orderDoc.data();
        final userId = orderData['authorID'] ??
            orderData['userId'] ??
            orderData['user_id'] ??
            '';
        if (userId.isNotEmpty) {
          userIds.add(userId);
        }

        final discountAmount = (orderData['couponDiscountAmount'] is num)
            ? (orderData['couponDiscountAmount'] as num).toDouble()
            : 0.0;
        totalDiscountCost += discountAmount;

        affectedOrders.add({
          'orderId': orderDoc.id,
          'userId': userId,
          'discountAmount': discountAmount,
          'createdAt': orderData['createdAt'],
          'deliveredAt': orderData['deliveredAt'] ?? orderData['completedAt'],
          'orderTotal': orderData['total'] ?? orderData['orderTotal'] ?? 0.0,
          'couponImageUrl': orderData['couponImageUrl'],
        });
      }

      affectedOrders.sort((a, b) {
        final aDate = _getTimestamp(a['deliveredAt'] ?? a['createdAt']);
        final bDate = _getTimestamp(b['deliveredAt'] ?? b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return CouponUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    });
  }

  // Helper to extract Timestamp from various formats
  static DateTime? _getTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is Map) {
      try {
        final ts = Timestamp(
          timestamp['_seconds'] ?? 0,
          timestamp['_nanoseconds'] ?? 0,
        );
        return ts.toDate();
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Compress image before upload
  static Future<File> _compressImage(File file) async {
    try {
      final targetPath = '${file.path}_compressed.jpg';
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1200,
        minHeight: 800,
        quality: 85,
      );
      if (result != null) {
        final targetFile = File(targetPath);
        await targetFile.writeAsBytes(result);
        return targetFile;
      } else {
        return file;
      }
    } catch (e) {
      log('Error compressing image: $e');
      return file;
    }
  }
}

// Usage statistics model
class CouponUsageStats {
  final int totalUsage;
  final int uniqueUsers;
  final double totalDiscountCost;
  final List<Map<String, dynamic>> affectedOrders;
  final List<String> userIds;

  CouponUsageStats({
    required this.totalUsage,
    required this.uniqueUsers,
    required this.totalDiscountCost,
    required this.affectedOrders,
    required this.userIds,
  });
}

