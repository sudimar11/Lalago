const express = require('express');
const { body, param, validationResult } = require('express-validator');
const { 
  processOrderCompletion, 
  getUserRewardHistory, 
  validateReferralCode 
} = require('../services/orderCompletionService');
const { verifyFirebaseToken } = require('../middleware/firebaseAuth');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * Middleware to handle validation errors
 */
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      error: 'Validation failed',
      code: 'VALIDATION_ERROR',
      details: errors.array()
    });
  }
  next();
};

/**
 * POST /api/v1/orders/complete
 * Process order completion and apply appropriate rewards
 */
router.post('/complete',
  verifyFirebaseToken, // Add Firebase auth middleware
  [
    body('orderId')
      .notEmpty()
      .withMessage('Order ID is required')
      .isString()
      .withMessage('Order ID must be a string'),
    body('userId')
      .notEmpty()
      .withMessage('User ID is required')
      .isString()
      .withMessage('User ID must be a string')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { orderId, userId } = req.body;
      
      logger.info(`Processing order completion: ${orderId} for user: ${userId}`);
      
      const result = await processOrderCompletion(orderId, userId);
      
      res.status(200).json({
        success: true,
        message: 'Order completion processed successfully',
        data: result
      });

    } catch (error) {
      logger.error('Error in order completion endpoint:', error);
      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: 'Failed to process order completion'
      });
    }
  }
);

/**
 * GET /api/v1/orders/rewards/:userId
 * Get reward history for a user
 */
router.get('/rewards/:userId',
  [
    param('userId')
      .notEmpty()
      .withMessage('User ID is required')
      .isString()
      .withMessage('User ID must be a string')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { userId } = req.params;
      
      logger.info(`Getting reward history for user: ${userId}`);
      
      const rewardHistory = await getUserRewardHistory(userId);
      
      res.status(200).json({
        success: true,
        data: rewardHistory
      });

    } catch (error) {
      logger.error('Error getting reward history:', error);
      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: 'Failed to get reward history'
      });
    }
  }
);

/**
 * POST /api/v1/orders/validate-referral
 * Validate referral code during signup
 */
router.post('/validate-referral',
  [
    body('referralCode')
      .notEmpty()
      .withMessage('Referral code is required')
      .isString()
      .withMessage('Referral code must be a string'),
    body('userId')
      .notEmpty()
      .withMessage('User ID is required')
      .isString()
      .withMessage('User ID must be a string')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { referralCode, userId } = req.body;
      
      logger.info(`Validating referral code: ${referralCode} for user: ${userId}`);
      
      const validation = await validateReferralCode(referralCode, userId);
      
      res.status(200).json({
        success: true,
        data: validation
      });

    } catch (error) {
      logger.error('Error validating referral code:', error);
      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: 'Failed to validate referral code'
      });
    }
  }
);

/**
 * POST /api/v1/orders/test-scenarios
 * Test endpoint for running QA scenarios
 */
router.post('/test-scenarios',
  [
    body('scenario')
      .notEmpty()
      .withMessage('Scenario is required')
      .isString()
      .withMessage('Scenario must be a string')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { scenario, data } = req.body;
      
      logger.info(`Running test scenario: ${scenario}`);
      
      let result;
      
      switch (scenario) {
        case 'referral_happy_flow':
          result = await _testReferralHappyFlow(data);
          break;
        case 'promo_only':
          result = await _testPromoOnly(data);
          break;
        case 'conflict_attempt':
          result = await _testConflictAttempt(data);
          break;
        case 'idempotency_check':
          result = await _testIdempotencyCheck(data);
          break;
        case 'self_referral':
          result = await _testSelfReferral(data);
          break;
        case 'legacy_user':
          result = await _testLegacyUser(data);
          break;
        default:
          throw new Error(`Unknown test scenario: ${scenario}`);
      }
      
      res.status(200).json({
        success: true,
        scenario: scenario,
        data: result
      });

    } catch (error) {
      logger.error(`Error running test scenario:`, error);
      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: `Failed to run test scenario: ${error.message}`
      });
    }
  }
);

/**
 * Test scenario implementations
 */
const _testReferralHappyFlow = async (data) => {
  const { userA, userB, orderId } = data;
  
  // Step 1: Validate referral code
  const validation = await validateReferralCode(userA.referralCode, userB.userID);
  
  // Step 2: Process order completion
  const completion = await processOrderCompletion(orderId, userB.userID);
  
  // Step 3: Get reward history
  const rewardHistory = await getUserRewardHistory(userA.userID);
  
  return {
    validation,
    completion,
    rewardHistory,
    expectedBehavior: {
      referralActive: true,
      promoDisabled: true,
      walletCredited: true,
      auditNote: 'Referral reward applied'
    }
  };
};

const _testPromoOnly = async (data) => {
  const { userB, orderId } = data;
  
  // Process order completion for non-referral user
  const completion = await processOrderCompletion(orderId, userB.userID);
  
  // Get reward history
  const rewardHistory = await getUserRewardHistory(userB.userID);
  
  return {
    completion,
    rewardHistory,
    expectedBehavior: {
      referralActive: false,
      promoDisabled: false,
      promoApplied: true,
      auditNote: 'First order promo applied'
    }
  };
};

const _testConflictAttempt = async (data) => {
  const { userB, orderId } = data;
  
  // This should automatically choose referral path over promo
  const completion = await processOrderCompletion(orderId, userB.userID);
  
  return {
    completion,
    expectedBehavior: {
      referralTakesPrecedence: true,
      promoExcluded: true,
      onlyOneCredit: true
    }
  };
};

const _testIdempotencyCheck = async (data) => {
  const { userB, orderId } = data;
  
  // Process order completion twice
  const firstCompletion = await processOrderCompletion(orderId, userB.userID);
  const secondCompletion = await processOrderCompletion(orderId, userB.userID);
  
  // Get reward history
  const rewardHistory = await getUserRewardHistory(userB.userID);
  
  return {
    firstCompletion,
    secondCompletion,
    rewardHistory,
    expectedBehavior: {
      noDuplicateCredits: true,
      idempotencyProtection: true,
      walletCorrect: true
    }
  };
};

const _testSelfReferral = async (data) => {
  const { userA } = data;
  
  // Attempt self-referral
  const validation = await validateReferralCode(userA.referralCode, userA.userID);
  
  return {
    validation,
    expectedBehavior: {
      selfReferralBlocked: true,
      signupNotBlocked: true,
      systemContinuesGracefully: true
    }
  };
};

const _testLegacyUser = async (data) => {
  // This would be handled by the referral service
  return {
    expectedBehavior: {
      codeGenerated: true,
      existingCodesPreserved: true,
      toggleControlled: true
    }
  };
};

module.exports = router;
