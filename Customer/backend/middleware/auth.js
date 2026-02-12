const logger = require('../utils/logger');

/**
 * Middleware to authenticate API key
 * Checks for API key in Authorization header or x-api-key header
 */
const authenticateApiKey = (req, res, next) => {
  try {
    const apiKey = process.env.API_KEY;
    
    if (!apiKey) {
      logger.error('API_KEY not configured in environment variables');
      return res.status(500).json({
        error: 'Server configuration error',
        code: 'MISSING_API_KEY_CONFIG'
      });
    }

    // Check Authorization header (Bearer token)
    const authHeader = req.headers.authorization;
    let providedApiKey = null;

    if (authHeader && authHeader.startsWith('Bearer ')) {
      providedApiKey = authHeader.substring(7);
    }

    // Check x-api-key header as alternative
    if (!providedApiKey) {
      providedApiKey = req.headers['x-api-key'];
    }

    if (!providedApiKey) {
      logger.warn('API key authentication failed - no key provided', {
        ip: req.ip,
        path: req.path,
        method: req.method
      });

      return res.status(401).json({
        error: 'Authentication required',
        code: 'MISSING_API_KEY',
        message: 'Provide API key in Authorization header (Bearer token) or x-api-key header'
      });
    }

    // Validate API key
    if (providedApiKey !== apiKey) {
      logger.warn('API key authentication failed - invalid key', {
        ip: req.ip,
        path: req.path,
        method: req.method,
        providedKeyLength: providedApiKey.length
      });

      return res.status(401).json({
        error: 'Invalid API key',
        code: 'INVALID_API_KEY'
      });
    }

    // Authentication successful
    logger.debug('API key authentication successful', {
      ip: req.ip,
      path: req.path,
      method: req.method
    });

    next();

  } catch (error) {
    logger.error('Error in API key authentication middleware', {
      error: error.message,
      stack: error.stack,
      ip: req.ip
    });

    res.status(500).json({
      error: 'Authentication error',
      code: 'AUTH_MIDDLEWARE_ERROR'
    });
  }
};

/**
 * Optional API key authentication - continues even if no key provided
 * Used for endpoints that have public access but provide enhanced features with auth
 */
const optionalApiKeyAuth = (req, res, next) => {
  try {
    const apiKey = process.env.API_KEY;
    
    if (!apiKey) {
      req.isAuthenticated = false;
      return next();
    }

    // Check for API key
    const authHeader = req.headers.authorization;
    let providedApiKey = null;

    if (authHeader && authHeader.startsWith('Bearer ')) {
      providedApiKey = authHeader.substring(7);
    }

    if (!providedApiKey) {
      providedApiKey = req.headers['x-api-key'];
    }

    if (!providedApiKey) {
      req.isAuthenticated = false;
      return next();
    }

    // Validate API key
    req.isAuthenticated = providedApiKey === apiKey;
    
    if (req.isAuthenticated) {
      logger.debug('Optional API key authentication successful', {
        ip: req.ip,
        path: req.path
      });
    } else {
      logger.debug('Optional API key authentication failed - invalid key', {
        ip: req.ip,
        path: req.path
      });
    }

    next();

  } catch (error) {
    logger.error('Error in optional API key authentication', {
      error: error.message,
      ip: req.ip
    });
    
    req.isAuthenticated = false;
    next();
  }
};

module.exports = {
  authenticateApiKey,
  optionalApiKeyAuth
};
