import 'package:firebase_auth/firebase_auth.dart';

/**
 * Cloud Function service for referral code management
 * Provides the most reliable way to ensure referral codes with automatic authentication
 * 
 * To use this service:
 * 1. Add cloud_functions: ^4.6.0 to pubspec.yaml
 * 2. Deploy the cloud functions from backend/functions/
 * 3. Replace BackendService calls with ReferralCloudService calls
 */
class ReferralCloudService {
  // Note: Uncomment these imports and methods when cloud_functions dependency is added
  // import 'package:cloud_functions/cloud_functions.dart';
  // static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Ensures a user has a referral code when accessing referral screen
  /// This is the most reliable method with automatic Firebase authentication
  static Future<String?> ensureReferralCodeForScreen(String userId) async {
    try {
      // Verify user is authenticated
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print(
            '⚠️ No authenticated user for cloud function call (soft failure)');
        return null;
      }

      if (currentUser.uid != userId) {
        print('⚠️ User ID mismatch for cloud function call (soft failure)');
        return null;
      }

      print('🔐 Calling cloud function for user: $userId');

      // Uncomment when cloud_functions dependency is added:
      /*
      final callable = _functions.httpsCallable('ensureReferralCode');
      
      final result = await callable.call({
        'userId': userId,
      });

      final data = result.data;
      if (data['success'] == true) {
        final referralData = data['data'];
        if (referralData['disabled'] == true) {
          print('ℹ️ Referral code generation is disabled');
          return null;
        }
        if (referralData['referralCode'] != null) {
          print('✅ Cloud function ensured referral code: ${referralData['referralCode']}');
          return referralData['referralCode'];
        }
      }

      print('⚠️ Cloud function returned unsuccessful result (soft failure)');
      return null;
      */

      // Temporary fallback - remove when cloud functions are enabled
      print('⚠️ Cloud functions not enabled - falling back to HTTP service');
      return null;
    } catch (e) {
      // Handle Firebase function errors as soft failures
      print('⚠️ Cloud function error: $e (soft failure)');
      return null;
    }
  }

  /// Ensures a user has a referral code during login
  static Future<String?> ensureReferralCodeOnLogin(String userId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print(
            '⚠️ No authenticated user for login cloud function call (soft failure)');
        return null;
      }

      if (currentUser.uid != userId) {
        print(
            '⚠️ User ID mismatch for login cloud function call (soft failure)');
        return null;
      }

      print('🔐 Calling login cloud function for user: $userId');

      // Uncomment when cloud_functions dependency is added:
      /*
      final callable = _functions.httpsCallable('loginReferralCheck');
      
      final result = await callable.call({
        'userId': userId,
      });

      final data = result.data;
      if (data['success'] == true) {
        final referralData = data['data'];
        if (referralData['enabled'] == true && referralData['referralCode'] != null) {
          print('✅ Login cloud function assigned referral code: ${referralData['referralCode']}');
          return referralData['referralCode'];
        } else {
          print('ℹ️ Referral system disabled or no code assigned');
          return null;
        }
      }

      print('⚠️ Login cloud function returned unsuccessful result (soft failure)');
      return null;
      */

      // Temporary fallback - remove when cloud functions are enabled
      print('⚠️ Cloud functions not enabled - falling back to HTTP service');
      return null;
    } catch (e) {
      print('⚠️ Login cloud function error: $e (soft failure)');
      return null;
    }
  }
}

/**
 * Instructions to enable Cloud Functions:
 * 
 * 1. Add to pubspec.yaml:
 *    dependencies:
 *      cloud_functions: ^4.6.0
 * 
 * 2. Uncomment the imports and method implementations above
 * 
 * 3. Deploy cloud functions:
 *    cd backend/functions
 *    firebase deploy --only functions
 * 
 * 4. Replace BackendService calls:
 *    // Before
 *    await BackendService.ensureReferralCodeForScreen(userId);
 *    
 *    // After
 *    await ReferralCloudService.ensureReferralCodeForScreen(userId);
 * 
 * 5. Benefits of Cloud Functions:
 *    - Automatic Firebase authentication
 *    - No manual token handling
 *    - Built-in retry logic
 *    - Better security
 *    - No HTTP status code issues
 *    - Automatic scaling
 */
