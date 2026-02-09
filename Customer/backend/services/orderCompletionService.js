const { getFirestore, COLLECTIONS, admin } = require('./firebaseService');
const logger = require('../utils/logger');

/**
 * Service to handle order completion and reward processing
 * Implements mutual exclusivity between referral rewards and ₱20 promo
 */

const REWARD_TYPES = {
  REFERRAL: 'referral',
  PROMO: 'promo_20'
};

const ORDER_STATUS = {
  PLACED: 'Order Placed',
  COMPLETED: 'Order Completed',
  DELIVERED: 'Order Delivered'
};

/**
 * Processes order completion and applies appropriate rewards
 * Ensures mutual exclusivity and idempotency
 */
const processOrderCompletion = async (orderId, userId) => {
  const firestore = getFirestore();
  
  try {
    logger.info(`Processing order completion for order: ${orderId}, user: ${userId}`);

    // Use Firestore transaction to ensure atomicity
    return await firestore.runTransaction(async (transaction) => {
      // Get user document
      const userRef = firestore.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await transaction.get(userRef);
      
      if (!userDoc.exists) {
        throw new Error(`User ${userId} not found`);
      }

      const user = userDoc.data();
      
      // Get order document
      const orderRef = firestore.collection('orders').doc(orderId);
      const orderDoc = await transaction.get(orderRef);
      
      if (!orderDoc.exists) {
        throw new Error(`Order ${orderId} not found`);
      }

      const order = orderDoc.data();

      // Check if this is the user's first completed order
      const isFirstOrder = await _isFirstCompletedOrder(transaction, userId, orderId);
      
      if (!isFirstOrder) {
        logger.info(`Not first order for user ${userId}, no rewards to process`);
        return {
          success: true,
          message: 'Order completed - not first order',
          rewardApplied: false
        };
      }

      // Check if rewards have already been processed for this order
      const existingReward = await _checkExistingReward(transaction, userId, orderId);
      if (existingReward) {
        logger.warn(`Reward already processed for order ${orderId}, user ${userId}`);
        return {
          success: true,
          message: 'Reward already processed (idempotency protection)',
          rewardApplied: false,
          existingReward
        };
      }

      // Determine reward type based on referral status
      const rewardResult = await _processRewardLogic(transaction, user, order, orderId);

      // Update user flags
      transaction.update(userRef, {
        hasCompletedFirstOrder: true,
        isReferralPath: rewardResult.type === REWARD_TYPES.REFERRAL,
        isPromoDisabled: rewardResult.type === REWARD_TYPES.REFERRAL,
        lastOrderCompletedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // Update order with reward information
      transaction.update(orderRef, {
        rewardProcessed: true,
        rewardType: rewardResult.type,
        rewardAmount: rewardResult.amount,
        auditNote: rewardResult.auditNote,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      logger.info(`Order completion processed successfully: ${JSON.stringify(rewardResult)}`);
      
      return {
        success: true,
        message: 'Order completed and reward processed',
        rewardApplied: true,
        ...rewardResult
      };
    });

  } catch (error) {
    logger.error(`Error processing order completion: ${error.message}`, error);
    throw error;
  }
};

/**
 * Determines and applies the appropriate reward logic
 */
const _processRewardLogic = async (transaction, user, order, orderId) => {
  const firestore = getFirestore();

  // Check if user is on referral path
  if (user.referredBy && user.referredBy.trim() !== '') {
    logger.info(`User ${user.id} is on referral path, processing referral reward`);
    
    // Find the referrer
    const referrerQuery = await firestore
      .collection(COLLECTIONS.USERS)
      .where('referralCode', '==', user.referredBy)
      .limit(1)
      .get();

    if (referrerQuery.empty) {
      logger.warn(`Referrer not found for code: ${user.referredBy}`);
      return _applyPromoReward(transaction, user, orderId);
    }

    const referrerDoc = referrerQuery.docs[0];
    const referrer = referrerDoc.data();

    // Apply referral reward
    return await _applyReferralReward(transaction, user, referrer, orderId);
  }

  // Apply ₱20 promo for non-referral users
  return await _applyPromoReward(transaction, user, orderId);
};

/**
 * Applies referral reward to referrer's wallet
 */
const _applyReferralReward = async (transaction, referee, referrer, orderId) => {
  const firestore = getFirestore();
  
  // Get referral settings
  const settingsDoc = await transaction.get(
    firestore.collection(COLLECTIONS.SETTINGS).doc('referralSettings')
  );
  
  const settings = settingsDoc.exists ? settingsDoc.data() : {};
  const rewardAmount = parseFloat(settings.referralRewardAmount || '20.0');

  // Update referrer's wallet
  const referrerRef = firestore.collection(COLLECTIONS.USERS).doc(referrer.id || referrer.userID);
  const currentWallet = parseFloat(referrer.wallet_amount || '0');
  const newWalletAmount = currentWallet + rewardAmount;

  transaction.update(referrerRef, {
    wallet_amount: newWalletAmount
  });

  // Create reward transaction record
  const rewardRecord = {
    id: `${orderId}_referral_reward`,
    type: REWARD_TYPES.REFERRAL,
    referrerId: referrer.id || referrer.userID,
    refereeId: referee.id || referee.userID,
    orderId: orderId,
    amount: rewardAmount,
    currency: 'PHP',
    status: 'completed',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    auditNote: `Referral reward: ₱${rewardAmount} credited to ${referrer.firstName} ${referrer.lastName} for successful referral of ${referee.firstName} ${referee.lastName}`
  };

  transaction.set(
    firestore.collection('rewardTransactions').doc(rewardRecord.id),
    rewardRecord
  );

  // Update pending referral record
  const pendingReferralRef = firestore.collection('pendingReferrals').doc(referee.id || referee.userID);
  transaction.update(pendingReferralRef, {
    isProcessed: true,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    rewardAmount: rewardAmount,
    status: 'completed'
  });

  logger.info(`Referral reward applied: ₱${rewardAmount} to referrer ${referrer.id || referrer.userID}`);

  return {
    type: REWARD_TYPES.REFERRAL,
    amount: rewardAmount,
    currency: 'PHP',
    referrerId: referrer.id || referrer.userID,
    referrerName: `${referrer.firstName} ${referrer.lastName}`,
    auditNote: `Referral active → ₱${rewardAmount} credited to referrer, ₱20 promo disabled (mutually exclusive)`
  };
};

/**
 * Applies ₱20 promo credit to user's wallet
 */
const _applyPromoReward = async (transaction, user, orderId) => {
  const firestore = getFirestore();
  const promoAmount = 20.0;

  // Update user's wallet
  const userRef = firestore.collection(COLLECTIONS.USERS).doc(user.id || user.userID);
  const currentWallet = parseFloat(user.wallet_amount || '0');
  const newWalletAmount = currentWallet + promoAmount;

  transaction.update(userRef, {
    wallet_amount: newWalletAmount
  });

  // Create promo reward record
  const promoRecord = {
    id: `${orderId}_promo_reward`,
    type: REWARD_TYPES.PROMO,
    userId: user.id || user.userID,
    orderId: orderId,
    amount: promoAmount,
    currency: 'PHP',
    status: 'completed',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    auditNote: `First order promo: ₱${promoAmount} credited to ${user.firstName} ${user.lastName}`
  };

  transaction.set(
    firestore.collection('rewardTransactions').doc(promoRecord.id),
    promoRecord
  );

  logger.info(`Promo reward applied: ₱${promoAmount} to user ${user.id || user.userID}`);

  return {
    type: REWARD_TYPES.PROMO,
    amount: promoAmount,
    currency: 'PHP',
    auditNote: `First order completed → ₱${promoAmount} promo credit applied`
  };
};

/**
 * Checks if this is the user's first completed order
 */
const _isFirstCompletedOrder = async (transaction, userId, currentOrderId) => {
  const firestore = getFirestore();
  
  // Check if user already has hasCompletedFirstOrder flag
  const userRef = firestore.collection(COLLECTIONS.USERS).doc(userId);
  const userDoc = await transaction.get(userRef);
  
  if (!userDoc.exists) {
    return false;
  }

  const user = userDoc.data();
  if (user.hasCompletedFirstOrder === true) {
    return false; // User has already completed first order
  }

  // Double-check by querying completed orders (excluding current one)
  const completedOrdersQuery = await firestore
    .collection('orders')
    .where('authorID', '==', userId)
    .where('status', 'in', [ORDER_STATUS.COMPLETED, ORDER_STATUS.DELIVERED])
    .get();

  const completedOrders = completedOrdersQuery.docs.filter(doc => doc.id !== currentOrderId);
  
  return completedOrders.length === 0; // True if no other completed orders
};

/**
 * Checks if reward has already been processed for this order
 */
const _checkExistingReward = async (transaction, userId, orderId) => {
  const firestore = getFirestore();
  
  // Check reward transactions
  const rewardQuery = await firestore
    .collection('rewardTransactions')
    .where('orderId', '==', orderId)
    .limit(1)
    .get();

  if (!rewardQuery.empty) {
    return rewardQuery.docs[0].data();
  }

  // Check order document
  const orderRef = firestore.collection('orders').doc(orderId);
  const orderDoc = await transaction.get(orderRef);
  
  if (orderDoc.exists) {
    const order = orderDoc.data();
    if (order.rewardProcessed === true) {
      return {
        type: order.rewardType,
        amount: order.rewardAmount,
        auditNote: order.auditNote
      };
    }
  }

  return null;
};

/**
 * Gets reward history for a user
 */
const getUserRewardHistory = async (userId) => {
  try {
    const firestore = getFirestore();
    
    const rewardsQuery = await firestore
      .collection('rewardTransactions')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();

    const referralRewardsQuery = await firestore
      .collection('rewardTransactions')
      .where('referrerId', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();

    const userRewards = rewardsQuery.docs.map(doc => doc.data());
    const referralRewards = referralRewardsQuery.docs.map(doc => doc.data());

    return {
      userRewards,
      referralRewards,
      totalEarned: userRewards.reduce((sum, reward) => sum + reward.amount, 0) +
                   referralRewards.reduce((sum, reward) => sum + reward.amount, 0)
    };
  } catch (error) {
    logger.error(`Error getting reward history for user ${userId}:`, error);
    throw error;
  }
};

/**
 * Validates referral code during signup
 */
const validateReferralCode = async (referralCode, newUserId) => {
  try {
    const firestore = getFirestore();

    // Check if referral code exists
    const referrerQuery = await firestore
      .collection(COLLECTIONS.USERS)
      .where('referralCode', '==', referralCode)
      .limit(1)
      .get();

    if (referrerQuery.empty) {
      return {
        valid: false,
        reason: 'Invalid referral code'
      };
    }

    const referrer = referrerQuery.docs[0].data();

    // Check for self-referral
    if ((referrer.id || referrer.userID) === newUserId) {
      return {
        valid: false,
        reason: 'Cannot use your own referral code'
      };
    }

    return {
      valid: true,
      referrer: referrer
    };
  } catch (error) {
    logger.error('Error validating referral code:', error);
    return {
      valid: false,
      reason: 'Error validating referral code'
    };
  }
};

module.exports = {
  processOrderCompletion,
  getUserRewardHistory,
  validateReferralCode,
  REWARD_TYPES,
  ORDER_STATUS
};
