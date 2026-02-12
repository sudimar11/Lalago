const { admin } = require('../services/firebaseService');
const logger = require('../utils/logger');

/**
 * Middleware to verify Firebase ID tokens with proper status codes
 * Extracts user information from the token and adds it to req.user
 */
const verifyFirebaseToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      // Allow requests without auth for backward compatibility (soft failure)
      logger.warn('No Firebase auth token provided - proceeding without authentication');
      req.user = null;
      return next();
    }

    const idToken = authHeader.split('Bearer ')[1];
    
    if (!idToken) {
      logger.warn('Empty Firebase auth token - proceeding without authentication');
      req.user = null;
      return next();
    }

    try {
      // Verify the Firebase ID token
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      
      req.user = {
        uid: decodedToken.uid,
        email: decodedToken.email,
        emailVerified: decodedToken.email_verified,
        name: decodedToken.name,
        picture: decodedToken.picture,
        authTime: decodedToken.auth_time,
        firebase: decodedToken
      };
      
      logger.info(`Authenticated user: ${decodedToken.uid} (${decodedToken.email})`);
      next();
      
    } catch (tokenError) {
      // Invalid token - return 401 for better client handling
      logger.warn(`Invalid Firebase token: ${tokenError.message}`);
      
      // Check if this is a token expiration or invalid format
      if (tokenError.code === 'auth/id-token-expired') {
        return res.status(401).json({
          error: 'Token expired',
          code: 'TOKEN_EXPIRED',
          message: 'Firebase ID token has expired. Please refresh and try again.'
        });
      } else if (tokenError.code === 'auth/argument-error') {
        return res.status(401).json({
          error: 'Invalid token format',
          code: 'INVALID_TOKEN_FORMAT',
          message: 'Firebase ID token format is invalid.'
        });
      } else {
        return res.status(401).json({
          error: 'Invalid token',
          code: 'INVALID_TOKEN',
          message: 'Firebase ID token is invalid or malformed.'
        });
      }
    }
    
  } catch (error) {
    // Any other error - return 500
    logger.error(`Firebase auth middleware error: ${error.message}`, error);
    return res.status(500).json({
      error: 'Authentication error',
      code: 'AUTH_ERROR',
      message: 'Failed to process authentication'
    });
  }
};

/**
 * Middleware to require Firebase authentication
 * Use this for endpoints that must have authentication
 */
const requireFirebaseAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'Authentication required',
        code: 'NO_AUTH_TOKEN',
        message: 'Firebase ID token required in Authorization header'
      });
    }

    const idToken = authHeader.split('Bearer ')[1];
    
    if (!idToken) {
      return res.status(401).json({
        error: 'Authentication required',
        code: 'EMPTY_AUTH_TOKEN',
        message: 'Firebase ID token cannot be empty'
      });
    }

    try {
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      
      req.user = {
        uid: decodedToken.uid,
        email: decodedToken.email,
        emailVerified: decodedToken.email_verified,
        name: decodedToken.name,
        picture: decodedToken.picture,
        authTime: decodedToken.auth_time,
        firebase: decodedToken
      };
      
      logger.info(`Authenticated required user: ${decodedToken.uid}`);
      next();
      
    } catch (tokenError) {
      return res.status(401).json({
        error: 'Invalid authentication token',
        code: 'INVALID_TOKEN',
        message: tokenError.message
      });
    }
    
  } catch (error) {
    logger.error('Firebase auth middleware error:', error);
    return res.status(500).json({
      error: 'Authentication error',
      code: 'AUTH_ERROR',
      message: 'Failed to process authentication'
    });
  }
};

module.exports = {
  verifyFirebaseToken,
  requireFirebaseAuth
};
