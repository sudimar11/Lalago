const { getFirestore, COLLECTIONS } = require('./firebaseService');
const logger = require('../utils/logger');

/**
 * Generates a referral code using the same format as the frontend
 * 6-digit number between 100000-999999
 */
const generateReferralCode = () => {
  const min = 100000;
  const max = 999999;
  return Math.floor(Math.random() * (max - min + 1)) + min;
};

/**
 * Checks if a referral code already exists in the users collection
 */
const isReferralCodeExists = async (code) => {
  try {
    const firestore = getFirestore();
    const querySnapshot = await firestore
      .collection(COLLECTIONS.USERS)
      .where('referralCode', '==', code.toString())
      .limit(1)
      .get();

    return !querySnapshot.empty;
  } catch (error) {
    logger.error('Error checking referral code existence:', error);
    return false;
  }
};

/**
 * Generates a unique referral code
 * Tries up to 10 times before using fallback with timestamp
 */
const generateUniqueReferralCode = async () => {
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    const code = generateReferralCode();
    const exists = await isReferralCodeExists(code);
    
    if (!exists) {
      logger.info(`Generated unique referral code: ${code} (attempt ${attempts + 1})`);
      return code.toString();
    }
    
    attempts++;
    logger.warn(`Referral code ${code} already exists, generating new one... (attempt ${attempts})`);
  }

  // Fallback: generate with timestamp to ensure uniqueness
  const fallbackCode = `${generateReferralCode()}${Date.now().toString().substring(8)}`;
  logger.info(`Using fallback referral code: ${fallbackCode}`);
  return fallbackCode;
};

/**
 * Checks if referral code generation is enabled via remote settings
 */
const isReferralGenerationEnabled = async () => {
  try {
    const firestore = getFirestore();
    const settingDoc = await firestore
      .collection(COLLECTIONS.SETTINGS)
      .doc('referralSettings')
      .get();

    if (settingDoc.exists) {
      const data = settingDoc.data();
      return data.enableAutoGeneration !== false; // Default to true if not set
    }
    
    return true; // Default to enabled if setting doesn't exist
  } catch (error) {
    logger.error('Error checking referral generation setting:', error);
    return true; // Default to enabled on error
  }
};

/**
 * Assigns a referral code to a user if they don't have one
 * Returns the assigned code or null if generation is disabled
 */
const ensureUserHasReferralCode = async (userId) => {
  try {
    // Check if feature is enabled
    const isEnabled = await isReferralGenerationEnabled();
    if (!isEnabled) {
      logger.info('Referral code generation is disabled via remote settings');
      return null;
    }

    const firestore = getFirestore();
    const userRef = firestore.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      logger.error(`User ${userId} not found`);
      return null;
    }

    const userData = userDoc.data();

    // Check if user already has a referral code
    if (userData.referralCode && userData.referralCode.trim() !== '') {
      logger.info(`User ${userId} already has referral code: ${userData.referralCode}`);
      return userData.referralCode;
    }

    // Generate and assign new referral code
    const newReferralCode = await generateUniqueReferralCode();
    
    await userRef.update({
      referralCode: newReferralCode,
      referralCodeGeneratedAt: new Date()
    });

    // Update legacy REFERRAL collection for backward compatibility
    await updateReferralCollection(userId, newReferralCode, userData.referredBy || '');

    logger.info(`Assigned referral code ${newReferralCode} to user ${userId}`);
    return newReferralCode;

  } catch (error) {
    logger.error(`Error ensuring referral code for user ${userId}:`, error);
    return null;
  }
};

/**
 * Updates the legacy REFERRAL collection for backward compatibility
 */
const updateReferralCollection = async (userId, referralCode, referredBy) => {
  try {
    const firestore = getFirestore();
    const referralData = {
      id: userId,
      referralCode: referralCode,
      referralBy: referredBy
    };

    await firestore
      .collection(COLLECTIONS.REFERRAL)
      .doc(userId)
      .set(referralData, { merge: true });

    logger.info(`Updated REFERRAL collection for user ${userId}`);
  } catch (error) {
    logger.error(`Error updating REFERRAL collection for user ${userId}:`, error);
  }
};

/**
 * Batch process multiple users to ensure they have referral codes
 * Useful for migration or bulk operations
 */
const batchEnsureReferralCodes = async (userIds) => {
  const results = [];
  
  for (const userId of userIds) {
    try {
      const referralCode = await ensureUserHasReferralCode(userId);
      results.push({ userId, referralCode, success: true });
    } catch (error) {
      logger.error(`Failed to process user ${userId}:`, error);
      results.push({ userId, referralCode: null, success: false, error: error.message });
    }
  }

  return results;
};

module.exports = {
  generateReferralCode,
  generateUniqueReferralCode,
  isReferralCodeExists,
  isReferralGenerationEnabled,
  ensureUserHasReferralCode,
  updateReferralCollection,
  batchEnsureReferralCodes
};
