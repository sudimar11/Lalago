import 'dart:io';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/advertisement.dart';

class AdsService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final Reference storage = FirebaseStorage.instance.ref();

  // Get all ads, ordered by priority
  static Future<List<Advertisement>> getAds({bool includeDeleted = false}) async {
    try {
      Query query = firestore.collection(ADVERTISEMENTS);
      
      if (!includeDeleted) {
        query = query.where('is_deleted', isEqualTo: false);
      }
      
      query = query.orderBy('priority', descending: false);
      
      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Advertisement.fromJson(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      print('Error getting ads: $e');
      return [];
    }
  }

  // Stream of ads for real-time updates
  static Stream<List<Advertisement>> getAdsStream({bool includeDeleted = false}) {
    Query query = firestore.collection(ADVERTISEMENTS);
    
    if (!includeDeleted) {
      query = query.where('is_deleted', isEqualTo: false);
    }
    
    query = query.orderBy('priority', descending: false);
    
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Advertisement.fromJson(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    });
  }

  // Create new ad
  static Future<String> createAd(Advertisement ad) async {
    try {
      log('--- START: Creating new ad in Firestore ---');
      final docRef = firestore.collection(ADVERTISEMENTS).doc();
      ad.id = docRef.id;
      ad.updatedAt = DateTime.now();
      
      log('Document ID: ${docRef.id}');
      log('Collection: $ADVERTISEMENTS');
      log('Ad data: ${ad.toJson()}');
      
      log('Saving to Firestore...');
      await docRef.set(ad.toJson());
      
      log('--- SUCCESS: Ad created successfully with ID: ${docRef.id} ---');
      return docRef.id;
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to create ad in Firestore ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to create ad: $e');
    }
  }

  // Update existing ad
  static Future<void> updateAd(Advertisement ad) async {
    try {
      log('--- START: Updating existing ad in Firestore ---');
      ad.updatedAt = DateTime.now();
      
      log('Document ID: ${ad.id}');
      log('Collection: $ADVERTISEMENTS');
      log('Ad data: ${ad.toJson()}');
      
      log('Updating in Firestore...');
      await firestore.collection(ADVERTISEMENTS).doc(ad.id).update(ad.toJson());
      
      log('--- SUCCESS: Ad updated successfully ---');
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to update ad in Firestore ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to update ad: $e');
    }
  }

  // Soft delete ad
  static Future<void> deleteAd(String adId) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'is_deleted': true,
        'updated_at': Timestamp.now(),
      });
    } catch (e) {
      print('Error deleting ad: $e');
      throw Exception('Failed to delete ad: $e');
    }
  }

  // Toggle enable/disable
  static Future<void> toggleEnabled(String adId, bool isEnabled) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'is_enabled': isEnabled,
        'updated_at': Timestamp.now(),
      });
    } catch (e) {
      print('Error toggling ad enabled: $e');
      throw Exception('Failed to toggle ad: $e');
    }
  }

  // Reorder ad by swapping priority with adjacent ad
  static Future<void> reorderAd(String adId, bool moveUp) async {
    try {
      final ads = await getAds();
      final currentIndex = ads.indexWhere((ad) => ad.id == adId);
      
      if (currentIndex == -1) {
        throw Exception('Ad not found');
      }
      
      int targetIndex;
      if (moveUp) {
        if (currentIndex == 0) return; // Already at top
        targetIndex = currentIndex - 1;
      } else {
        if (currentIndex == ads.length - 1) return; // Already at bottom
        targetIndex = currentIndex + 1;
      }
      
      final currentAd = ads[currentIndex];
      final targetAd = ads[targetIndex];
      
      // Swap priorities
      final tempPriority = currentAd.priority;
      currentAd.priority = targetAd.priority;
      targetAd.priority = tempPriority;
      
      // Update both ads
      await Future.wait([
        firestore.collection(ADVERTISEMENTS).doc(currentAd.id).update({
          'priority': currentAd.priority,
          'updated_at': Timestamp.now(),
        }),
        firestore.collection(ADVERTISEMENTS).doc(targetAd.id).update({
          'priority': targetAd.priority,
          'updated_at': Timestamp.now(),
        }),
      ]);
    } catch (e) {
      print('Error reordering ad: $e');
      throw Exception('Failed to reorder ad: $e');
    }
  }

  // Upload ad image to Firebase Storage
  static Future<String> uploadAdImage(dynamic image) async {
    try {
      log('--- START: Uploading ad image to Firebase Storage ---');
      final uuid = const Uuid().v4();
      log('Generated UUID: $uuid');
      
      final storagePath = '$STORAGE_ADS/$uuid.jpg';
      log('Storage path: $storagePath');
      final Reference upload = storage.child(storagePath);
      
      log('Creating upload task with metadata...');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );
      
      UploadTask uploadTask;
      
      if (kIsWeb) {
        // For web: read as bytes and upload
        log('Platform: Web - Using bytes upload');
        final XFile xFile = image is XFile ? image : XFile(image.path);
        final bytes = await xFile.readAsBytes();
        uploadTask = upload.putData(bytes, metadata);
      } else {
        // For mobile: compress and upload file
        log('Platform: Mobile - Compressing image...');
        final File file = image is File ? image : File((image as XFile).path);
        final compressedImage = await _compressImage(file);
        log('Image compressed successfully: ${compressedImage.path}');
        uploadTask = upload.putFile(compressedImage, metadata);
      }
      
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
      log('--- SUCCESS: Ad image uploaded successfully ---');
      
      return downloadUrl.toString();
    } catch (e, stackTrace) {
      log('--- ERROR: Failed to upload ad image ---');
      log('Error: $e');
      log('Error Type: ${e.runtimeType}');
      log('StackTrace: $stackTrace');
      throw Exception('Failed to upload ad image: $e');
    }
  }

  // Delete image from Firebase Storage
  static Future<void> deleteAdImage(String imageUrl) async {
    try {
      // Extract path from URL
      final uri = Uri.parse(imageUrl);
      final path = uri.pathSegments.last;
      final fullPath = '$STORAGE_ADS/$path';
      
      await storage.child(fullPath).delete();
    } catch (e) {
      print('Error deleting ad image: $e');
      // Don't throw - image might already be deleted
    }
  }

  // Increment impressions (for customer app integration)
  static Future<void> incrementImpressions(String adId) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'impressions': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error incrementing impressions: $e');
      throw Exception('Failed to increment impressions: $e');
    }
  }

  // Increment clicks (for customer app integration)
  static Future<void> incrementClicks(String adId) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'clicks': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error incrementing clicks: $e');
      throw Exception('Failed to increment clicks: $e');
    }
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
      print('Error compressing image: $e');
      return file;
    }
  }
}

