/**
 * Firebase Cloud Function alternative for referral code management
 * This provides better integration with Firebase ecosystem
 * 
 * To use this instead of Express endpoints:
 * 1. Deploy this as a Firebase Cloud Function
 * 2. Update BackendService to call the function instead of HTTP endpoints
 * 3. Use firebase_functions package in Flutter for direct calling
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

/**
 * Cloud Function: createReferralCode
 * Ensures a user has a referral code, generating one if needed
 * Returns simple {code} response for easy client handling
 */
exports.createReferralCode = functions.https.onCall(async (data, context) => {
  try {
    // Strict authentication requirement for cloud functions
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Authentication required. Please log in to access referral features.'
      );
    }

    const { userId } = data;
    
    if (!userId) {
      throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
    }

    // Strict user validation - authenticated user must match requested user
    if (context.auth.uid !== userId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'You can only access your own referral code'
      );
    }

    console.log(`Ensuring referral code for authenticated user: ${userId} (${context.auth.email})`);

    // Check if referral generation is enabled
    const settingDoc = await firestore.collection('settings').doc('referralSettings').get();
    const settings = settingDoc.exists ? settingDoc.data() : {};
    const isEnabled = settings.enableAutoGeneration !== false;

    if (!isEnabled) {
      console.log('Referral code generation is disabled via remote settings');
    return {
      code: null,
      disabled: true
    };
    }

    // Get user document
    const userRef = firestore.collection('users').doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', `User ${userId} not found in database`);
    }

    const userData = userDoc.data();

    // Check if user already has a referral code
    if (userData.referralCode && userData.referralCode.trim() !== '') {
      console.log(`User ${userId} already has referral code: ${userData.referralCode}`);
      return {
        code: userData.referralCode
      };
    }

    // Generate new referral code with transaction for safety
    const newReferralCode = await firestore.runTransaction(async (transaction) => {
      const code = await generateUniqueReferralCode();
      
      // Update user document
      transaction.update(userRef, {
        referralCode: code,
        referralCodeGeneratedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // Update legacy REFERRAL collection for backward compatibility
      const referralRef = firestore.collection('referral').doc(userId);
      transaction.set(referralRef, {
        id: userId,
        referralCode: code,
        referralBy: userData.referredBy || ''
      }, { merge: true });

      return code;
    });

    console.log(`Assigned referral code ${newReferralCode} to user ${userId}`);

    return {
      code: newReferralCode
    };

  } catch (error) {
    console.error(`Error ensuring referral code for user ${data.userId}:`, error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    
    throw new functions.https.HttpsError('internal', `Failed to ensure referral code: ${error.message}`);
  }
});

/**
 * Generates a unique referral code
 */
const generateUniqueReferralCode = async () => {
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    const code = Math.floor(Math.random() * (999999 - 100000 + 1)) + 100000;
    
    // Check if code exists in users collection
    const querySnapshot = await firestore
      .collection('users')
      .where('referralCode', '==', code.toString())
      .limit(1)
      .get();

    if (querySnapshot.empty) {
      console.log(`Generated unique referral code: ${code} (attempt ${attempts + 1})`);
      return code.toString();
    }
    
    attempts++;
    console.warn(`Referral code ${code} already exists, generating new one... (attempt ${attempts})`);
  }

  // Fallback: generate with timestamp to ensure uniqueness
  const fallbackCode = `${Math.floor(Math.random() * (999999 - 100000 + 1)) + 100000}${Date.now().toString().substring(8)}`;
  console.log(`Using fallback referral code: ${fallbackCode}`);
  return fallbackCode;
};

/**
 * Cloud Function: loginReferralCheck
 * Checks and assigns referral code during login process
 */
exports.loginReferralCheck = functions.https.onCall(async (data, context) => {
  try {
    // Verify authentication
    if (!context.auth) {
      console.warn('No authentication context for login check');
    } else {
      console.log(`Authenticated login check for user: ${context.auth.uid}`);
    }

    const { userId } = data;
    
    if (!userId) {
      throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
    }

    console.log(`Login referral check for user: ${userId}`);

    // Check if generation is enabled
    const settingDoc = await firestore.collection('settings').doc('referralSettings').get();
    const settings = settingDoc.exists ? settingDoc.data() : {};
    const isEnabled = settings.enableAutoGeneration !== false;

    if (!isEnabled) {
      return {
        success: true,
        message: 'Referral system disabled',
        data: {
          userId,
          referralCode: null,
          enabled: false
        }
      };
    }

    // Ensure user has referral code (same logic as above)
    const userRef = firestore.collection('users').doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', `User ${userId} not found`);
    }

    const userData = userDoc.data();

    if (userData.referralCode && userData.referralCode.trim() !== '') {
      return {
        success: true,
        message: 'Login referral check completed',
        data: {
          userId,
          referralCode: userData.referralCode,
          enabled: true
        }
      };
    }

    // Generate new code
    const newReferralCode = await generateUniqueReferralCode();
    
    await userRef.update({
      referralCode: newReferralCode,
      referralCodeGeneratedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return {
      success: true,
      message: 'Login referral check completed',
      data: {
        userId,
        referralCode: newReferralCode,
        enabled: true
      }
    };

  } catch (error) {
    console.error(`Error in login referral check:`, error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    
    throw new functions.https.HttpsError('internal', 'Failed to complete login referral check');
  }
});
