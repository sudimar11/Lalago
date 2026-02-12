const { google } = require('googleapis');
const logger = require('../utils/logger');

class PlayIntegrityService {
  constructor() {
    this.projectId = process.env.GOOGLE_CLOUD_PROJECT_ID;
    this.projectNumber = process.env.GOOGLE_CLOUD_PROJECT_NUMBER;
    this.expectedPackageName = process.env.EXPECTED_PACKAGE_NAME;
    this.expectedCertificateSha256 = process.env.EXPECTED_APP_CERTIFICATE_SHA256;
    
    // Initialize Google Auth
    this.auth = new google.auth.GoogleAuth({
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      scopes: ['https://www.googleapis.com/auth/playintegrity']
    });

    // Initialize Play Integrity API client
    this.playIntegrity = google.playintegrity('v1');
  }

  /**
   * Validates a Play Integrity API token
   * @param {string} integrityToken - The integrity token from the client
   * @param {Object} options - Validation options
   * @param {string} options.packageName - Package name from client (optional)
   * @param {string} options.expectedPackageName - Override expected package name
   * @returns {Promise<Object>} Validation result
   */
  async validateIntegrityToken(integrityToken, options = {}) {
    try {
      logger.info('Starting integrity token validation', {
        hasToken: !!integrityToken,
        projectId: this.projectId,
        projectNumber: this.projectNumber
      });

      if (!integrityToken) {
        throw new Error('Integrity token is required');
      }

      if (!this.projectId || !this.projectNumber) {
        throw new Error('Google Cloud project configuration is missing');
      }

      // Get authenticated client
      const authClient = await this.auth.getClient();
      
      // Call Google Play Integrity API
      const response = await this.playIntegrity.v1.decodeIntegrityToken({
        auth: authClient,
        packageName: this.expectedPackageName,
        requestBody: {
          integrityToken: integrityToken
        }
      });

      logger.info('Received response from Play Integrity API', {
        hasTokenPayloadExternal: !!response.data.tokenPayloadExternal,
        hasSymbol: !!response.data.symbol
      });

      if (!response.data.tokenPayloadExternal) {
        return {
          isValid: false,
          error: 'Invalid token payload received from Google',
          code: 'INVALID_TOKEN_PAYLOAD',
          timestamp: new Date().toISOString()
        };
      }

      // Parse the token payload
      const payload = response.data.tokenPayloadExternal;
      
      // Extract verdicts
      const requestDetails = payload.requestDetails || {};
      const appIntegrity = payload.appIntegrity || {};
      const deviceIntegrity = payload.deviceIntegrity || {};
      const accountDetails = payload.accountDetails || {};

      const packageName = requestDetails.requestPackageName;
      const appVerdict = appIntegrity.appRecognitionVerdict;
      const deviceVerdict = deviceIntegrity.deviceRecognitionVerdict;
      const accountVerdict = accountDetails.appLicensingVerdict;

      logger.info('Token payload extracted', {
        packageName,
        appVerdict,
        deviceVerdict,
        accountVerdict,
        timestampMs: requestDetails.timestampMillis
      });

      // Validate package name
      const expectedPkg = options.expectedPackageName || this.expectedPackageName;
      const packageNameValid = this.validatePackageName(packageName, expectedPkg);

      // Validate integrity verdicts
      const integrityValid = this.validateIntegrityVerdicts(appVerdict, deviceVerdict);

      // Validate certificate (if configured)
      const certificateValid = this.validateCertificate(appIntegrity.certificateSha256Digest);

      const isValid = packageNameValid && integrityValid && certificateValid;

      const result = {
        isValid,
        packageName,
        appVerdict,
        deviceVerdict,
        accountVerdict,
        timestamp: new Date().toISOString(),
        requestTimestamp: requestDetails.timestampMillis ? 
          new Date(parseInt(requestDetails.timestampMillis)).toISOString() : null
      };

      if (!isValid) {
        result.error = this.generateErrorMessage(packageNameValid, integrityValid, certificateValid);
        result.code = this.generateErrorCode(packageNameValid, integrityValid, certificateValid);
        
        result.details = {
          packageNameValid,
          integrityValid,
          certificateValid,
          expectedPackageName: expectedPkg,
          actualPackageName: packageName,
          expectedCertificate: this.expectedCertificateSha256,
          actualCertificate: appIntegrity.certificateSha256Digest
        };
      }

      logger.info('Integrity validation completed', {
        isValid,
        packageNameValid,
        integrityValid,
        certificateValid
      });

      return result;

    } catch (error) {
      logger.error('Error validating integrity token', {
        error: error.message,
        stack: error.stack,
        code: error.code
      });

      // Handle specific Google API errors
      if (error.code === 400) {
        return {
          isValid: false,
          error: 'Invalid integrity token format',
          code: 'INVALID_TOKEN_FORMAT',
          timestamp: new Date().toISOString()
        };
      }

      if (error.code === 403) {
        return {
          isValid: false,
          error: 'Play Integrity API access denied - check service account permissions',
          code: 'ACCESS_DENIED',
          timestamp: new Date().toISOString()
        };
      }

      if (error.code === 404) {
        return {
          isValid: false,
          error: 'Play Integrity API not found - ensure API is enabled',
          code: 'API_NOT_FOUND',
          timestamp: new Date().toISOString()
        };
      }

      return {
        isValid: false,
        error: `Integrity validation failed: ${error.message}`,
        code: 'VALIDATION_ERROR',
        timestamp: new Date().toISOString()
      };
    }
  }

  /**
   * Validates multiple integrity tokens in batch
   * @param {string[]} tokens - Array of integrity tokens
   * @param {Object} options - Validation options
   * @returns {Promise<Object[]>} Array of validation results
   */
  async validateIntegrityTokensBatch(tokens, options = {}) {
    logger.info('Starting batch integrity validation', {
      tokenCount: tokens.length
    });

    const results = await Promise.allSettled(
      tokens.map(token => this.validateIntegrityToken(token, options))
    );

    return results.map((result, index) => {
      if (result.status === 'fulfilled') {
        return result.value;
      } else {
        logger.error(`Batch validation failed for token ${index}`, {
          error: result.reason.message
        });
        return {
          isValid: false,
          error: `Batch validation failed: ${result.reason.message}`,
          code: 'BATCH_VALIDATION_ERROR',
          timestamp: new Date().toISOString()
        };
      }
    });
  }

  /**
   * Validates package name against expected value
   * @param {string} actualPackageName - Package name from token
   * @param {string} expectedPackageName - Expected package name
   * @returns {boolean} Whether package name is valid
   */
  validatePackageName(actualPackageName, expectedPackageName) {
    if (!expectedPackageName) {
      logger.warn('No expected package name configured - skipping validation');
      return true;
    }

    const isValid = actualPackageName === expectedPackageName;
    
    if (!isValid) {
      logger.warn('Package name validation failed', {
        expected: expectedPackageName,
        actual: actualPackageName
      });
    }

    return isValid;
  }

  /**
   * Validates integrity verdicts
   * @param {string} appVerdict - App integrity verdict
   * @param {string} deviceVerdict - Device integrity verdict
   * @returns {boolean} Whether integrity verdicts are acceptable
   */
  validateIntegrityVerdicts(appVerdict, deviceVerdict) {
    // Define acceptable verdicts
    const acceptableAppVerdicts = ['PLAY_RECOGNIZED', 'UNRECOGNIZED_VERSION'];
    const acceptableDeviceVerdicts = ['MEETS_DEVICE_INTEGRITY', 'MEETS_BASIC_INTEGRITY'];

    const appValid = acceptableAppVerdicts.includes(appVerdict);
    const deviceValid = acceptableDeviceVerdicts.includes(deviceVerdict);

    if (!appValid) {
      logger.warn('App integrity verdict failed', {
        verdict: appVerdict,
        acceptable: acceptableAppVerdicts
      });
    }

    if (!deviceValid) {
      logger.warn('Device integrity verdict failed', {
        verdict: deviceVerdict,
        acceptable: acceptableDeviceVerdicts
      });
    }

    return appValid && deviceValid;
  }

  /**
   * Validates certificate SHA256 digest
   * @param {string} actualCertificate - Certificate from token
   * @returns {boolean} Whether certificate is valid
   */
  validateCertificate(actualCertificate) {
    if (!this.expectedCertificateSha256) {
      logger.info('No expected certificate configured - skipping validation');
      return true;
    }

    const isValid = actualCertificate === this.expectedCertificateSha256;
    
    if (!isValid) {
      logger.warn('Certificate validation failed', {
        expected: this.expectedCertificateSha256,
        actual: actualCertificate
      });
    }

    return isValid;
  }

  /**
   * Generates error message based on validation failures
   * @param {boolean} packageNameValid - Package name validation result
   * @param {boolean} integrityValid - Integrity validation result
   * @param {boolean} certificateValid - Certificate validation result
   * @returns {string} Error message
   */
  generateErrorMessage(packageNameValid, integrityValid, certificateValid) {
    const errors = [];

    if (!packageNameValid) {
      errors.push('Package name mismatch');
    }

    if (!integrityValid) {
      errors.push('Integrity verdict failed');
    }

    if (!certificateValid) {
      errors.push('Certificate validation failed');
    }

    return errors.join(', ');
  }

  /**
   * Generates error code based on validation failures
   * @param {boolean} packageNameValid - Package name validation result
   * @param {boolean} integrityValid - Integrity validation result
   * @param {boolean} certificateValid - Certificate validation result
   * @returns {string} Error code
   */
  generateErrorCode(packageNameValid, integrityValid, certificateValid) {
    if (!packageNameValid && !integrityValid && !certificateValid) {
      return 'MULTIPLE_VALIDATION_FAILURES';
    }

    if (!packageNameValid) {
      return 'PACKAGE_NAME_MISMATCH';
    }

    if (!integrityValid) {
      return 'INTEGRITY_VERDICT_FAILED';
    }

    if (!certificateValid) {
      return 'CERTIFICATE_VALIDATION_FAILED';
    }

    return 'VALIDATION_FAILED';
  }

  /**
   * Gets current service configuration
   * @returns {Object} Configuration object
   */
  getConfiguration() {
    return {
      projectId: this.projectId,
      projectNumber: this.projectNumber,
      expectedPackageName: this.expectedPackageName,
      expectedCertificateSha256: this.expectedCertificateSha256 ? 
        `${this.expectedCertificateSha256.substring(0, 8)}...` : null,
      hasServiceAccount: !!process.env.GOOGLE_APPLICATION_CREDENTIALS
    };
  }
}

module.exports = new PlayIntegrityService();
