const express = require('express');
const { body, param, validationResult } = require('express-validator');
const { ensureUserHasReferralCode, batchEnsureReferralCodes, isReferralGenerationEnabled } = require('../services/referralService');
const { getFirestore, COLLECTIONS } = require('../services/firebaseService');
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
 * POST /api/v1/referral/ensure-code
 * Ensures a user has a referral code, generating one if needed
 */
router.post('/ensure-code',
  verifyFirebaseToken, // Add Firebase auth middleware
  [
    body('userId')
      .notEmpty()
      .withMessage('User ID is required')
      .isString()
      .withMessage('User ID must be a string')
      .trim()
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { userId } = req.body;
      
      // Enhanced authentication validation
      if (req.user) {
        if (req.user.uid !== userId) {
          logger.warn(`Auth user ${req.user.uid} trying to access user ${userId}`);
          return res.status(403).json({
            error: 'Authorization failed',
            code: 'USER_MISMATCH',
            message: 'Authenticated user does not match requested user ID'
          });
        }
        logger.info(`Ensuring referral code for authenticated user: ${userId}`);
      } else {
        logger.warn(`No authentication provided for user: ${userId} - proceeding with caution`);
      }
      
      const referralCode = await ensureUserHasReferralCode(userId);
      
      if (referralCode === null) {
        return res.status(200).json({
          success: true,
          message: 'Referral code generation is disabled',
          data: {
            userId,
            referralCode: null,
            generated: false,
            disabled: true
          }
        });
      }

      // Always return 200 with the referral code (no redirects)
      res.status(200).json({
        success: true,
        message: 'Referral code ensured successfully',
        data: {
          userId,
          referralCode,
          generated: true,
          authenticated: req.user ? true : false
        }
      });

    } catch (error) {
      logger.error('Error in ensure-code endpoint:', error);
      
      // Return appropriate error status
      if (error.message.includes('not found')) {
        res.status(404).json({
          error: 'User not found',
          code: 'USER_NOT_FOUND',
          message: `User ${req.body.userId} not found in database`
        });
      } else {
        res.status(500).json({
          error: 'Internal server error',
          code: 'INTERNAL_ERROR',
          message: 'Failed to ensure referral code'
        });
      }
    }
  }
);

/**
 * POST /api/v1/referral/login-check
 * Checks and assigns referral code during login process
 */
router.post('/login-check',
  verifyFirebaseToken, // Add Firebase auth middleware
  [
    body('userId')
      .notEmpty()
      .withMessage('User ID is required')
      .isString()
      .withMessage('User ID must be a string')
      .trim()
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { userId } = req.body;
      
      // Enhanced authentication validation
      if (req.user) {
        if (req.user.uid !== userId) {
          logger.warn(`Auth user ${req.user.uid} trying to access user ${userId}`);
          return res.status(403).json({
            error: 'Authorization failed',
            code: 'USER_MISMATCH',
            message: 'Authenticated user does not match requested user ID'
          });
        }
        logger.info(`Login referral check for authenticated user: ${userId}`);
      } else {
        logger.warn(`No authentication provided for login check: ${userId} - proceeding with caution`);
      }
      
      // Check if generation is enabled
      const isEnabled = await isReferralGenerationEnabled();
      if (!isEnabled) {
        return res.status(200).json({
          success: true,
          message: 'Referral system disabled',
          data: {
            userId,
            referralCode: null,
            enabled: false
          }
        });
      }

      const referralCode = await ensureUserHasReferralCode(userId);
      
      // Always return 200 with clear response (no redirects)
      res.status(200).json({
        success: true,
        message: 'Login referral check completed',
        data: {
          userId,
          referralCode,
          enabled: true,
          authenticated: req.user ? true : false
        }
      });

    } catch (error) {
      logger.error('Error in login-check endpoint:', error);
      
      // Return appropriate error status
      if (error.message.includes('not found')) {
        res.status(404).json({
          error: 'User not found',
          code: 'USER_NOT_FOUND',
          message: `User ${req.body.userId} not found in database`
        });
      } else {
        res.status(500).json({
          error: 'Internal server error',
          code: 'INTERNAL_ERROR',
          message: 'Failed to complete login referral check'
        });
      }
    }
  }
);

/**
 * GET /api/v1/referral/settings
 * Gets current referral system settings
 */
router.get('/settings', async (req, res) => {
  try {
    const firestore = getFirestore();
    const settingDoc = await firestore
      .collection(COLLECTIONS.SETTINGS)
      .doc('referralSettings')
      .get();

    let settings = {
      enableAutoGeneration: true, // Default
      lastUpdated: null
    };

    if (settingDoc.exists) {
      settings = { ...settings, ...settingDoc.data() };
    }

    res.status(200).json({
      success: true,
      data: settings
    });

  } catch (error) {
    logger.error('Error fetching referral settings:', error);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to fetch referral settings'
    });
  }
});

/**
 * POST /api/v1/referral/batch-ensure
 * Batch process multiple users to ensure they have referral codes
 * Useful for migration or admin operations
 */
router.post('/batch-ensure',
  [
    body('userIds')
      .isArray({ min: 1 })
      .withMessage('User IDs must be a non-empty array'),
    body('userIds.*')
      .isString()
      .withMessage('Each user ID must be a string')
      .trim()
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { userIds } = req.body;
      
      if (userIds.length > 100) {
        return res.status(400).json({
          error: 'Too many users',
          code: 'BATCH_SIZE_EXCEEDED',
          message: 'Maximum 100 users per batch request'
        });
      }

      logger.info(`Batch ensuring referral codes for ${userIds.length} users`);
      
      const results = await batchEnsureReferralCodes(userIds);
      
      const successful = results.filter(r => r.success).length;
      const failed = results.filter(r => !r.success).length;

      res.status(200).json({
        success: true,
        message: `Batch operation completed: ${successful} successful, ${failed} failed`,
        data: {
          total: userIds.length,
          successful,
          failed,
          results
        }
      });

    } catch (error) {
      logger.error('Error in batch-ensure endpoint:', error);
      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: 'Failed to complete batch operation'
      });
    }
  }
);

module.exports = router;
