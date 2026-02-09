const express = require('express');
const { body, validationResult } = require('express-validator');
const router = express.Router();

const PlayIntegrityService = require('../services/playIntegrityService');
const { authenticateApiKey } = require('../middleware/auth');
const logger = require('../utils/logger');

/**
 * POST /api/v1/integrity/validate
 * Validates a Play Integrity API token from the client
 */
router.post('/validate',
  // API key authentication
  authenticateApiKey,
  
  // Input validation
  [
    body('token')
      .notEmpty()
      .withMessage('Token is required')
      .isString()
      .withMessage('Token must be a string')
      .isLength({ min: 10 })
      .withMessage('Token appears to be invalid (too short)'),
    
    body('packageName')
      .optional()
      .isString()
      .withMessage('Package name must be a string'),
      
    body('expectedPackageName')
      .optional()
      .isString()
      .withMessage('Expected package name must be a string')
  ],
  
  async (req, res) => {
    try {
      // Check validation errors
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        logger.warn('Validation failed for integrity token request', {
          errors: errors.array(),
          ip: req.ip
        });
        return res.status(400).json({
          error: 'Validation failed',
          code: 'VALIDATION_ERROR',
          details: errors.array()
        });
      }

      const { token, packageName, expectedPackageName } = req.body;

      logger.info('Processing integrity token validation request', {
        hasToken: !!token,
        packageName: packageName || 'not provided',
        expectedPackageName: expectedPackageName || 'using default',
        ip: req.ip
      });

      // Validate the integrity token
      const result = await PlayIntegrityService.validateIntegrityToken(token, {
        packageName,
        expectedPackageName
      });

      if (result.isValid) {
        logger.info('Integrity token validation successful', {
          packageName: result.packageName,
          deviceVerdict: result.deviceVerdict,
          appVerdict: result.appVerdict,
          ip: req.ip
        });

        res.status(200).json({
          success: true,
          valid: true,
          data: {
            packageName: result.packageName,
            deviceVerdict: result.deviceVerdict,
            appVerdict: result.appVerdict,
            accountVerdict: result.accountVerdict,
            timestamp: result.timestamp
          },
          message: 'Integrity token validated successfully'
        });
      } else {
        logger.warn('Integrity token validation failed', {
          error: result.error,
          code: result.code,
          packageName: result.packageName,
          ip: req.ip
        });

        res.status(400).json({
          success: false,
          valid: false,
          error: result.error,
          code: result.code,
          data: {
            packageName: result.packageName,
            deviceVerdict: result.deviceVerdict,
            appVerdict: result.appVerdict,
            accountVerdict: result.accountVerdict,
            timestamp: result.timestamp
          },
          message: 'Integrity token validation failed'
        });
      }

    } catch (error) {
      logger.error('Unexpected error during integrity validation', {
        error: error.message,
        stack: error.stack,
        ip: req.ip
      });

      res.status(500).json({
        error: 'Internal server error during integrity validation',
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred while validating the integrity token'
      });
    }
  }
);

/**
 * GET /api/v1/integrity/config
 * Returns the current configuration (for debugging)
 */
router.get('/config',
  authenticateApiKey,
  (req, res) => {
    try {
      const config = PlayIntegrityService.getConfiguration();
      
      logger.info('Configuration requested', {
        ip: req.ip
      });

      res.status(200).json({
        success: true,
        data: config,
        message: 'Configuration retrieved successfully'
      });

    } catch (error) {
      logger.error('Error retrieving configuration', {
        error: error.message,
        ip: req.ip
      });

      res.status(500).json({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        message: 'Could not retrieve configuration'
      });
    }
  }
);

/**
 * POST /api/v1/integrity/batch-validate
 * Validates multiple integrity tokens in a batch
 */
router.post('/batch-validate',
  authenticateApiKey,
  
  [
    body('tokens')
      .isArray()
      .withMessage('Tokens must be an array')
      .isLength({ min: 1, max: 10 })
      .withMessage('Must provide 1-10 tokens'),
    
    body('tokens.*')
      .isString()
      .withMessage('Each token must be a string')
      .isLength({ min: 10 })
      .withMessage('Each token appears to be invalid (too short)')
  ],
  
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          error: 'Validation failed',
          code: 'VALIDATION_ERROR',
          details: errors.array()
        });
      }

      const { tokens, expectedPackageName } = req.body;

      logger.info('Processing batch integrity validation', {
        tokenCount: tokens.length,
        ip: req.ip
      });

      const results = await PlayIntegrityService.validateIntegrityTokensBatch(tokens, {
        expectedPackageName
      });

      const validCount = results.filter(r => r.isValid).length;
      const invalidCount = results.length - validCount;

      logger.info('Batch integrity validation completed', {
        total: results.length,
        valid: validCount,
        invalid: invalidCount,
        ip: req.ip
      });

      res.status(200).json({
        success: true,
        data: {
          results,
          summary: {
            total: results.length,
            valid: validCount,
            invalid: invalidCount
          }
        },
        message: 'Batch validation completed'
      });

    } catch (error) {
      logger.error('Error during batch validation', {
        error: error.message,
        stack: error.stack,
        ip: req.ip
      });

      res.status(500).json({
        error: 'Internal server error during batch validation',
        code: 'INTERNAL_ERROR'
      });
    }
  }
);

module.exports = router;
