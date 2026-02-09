const logger = require('../utils/logger');

/**
 * Global error handling middleware
 * Catches all unhandled errors and provides consistent error responses
 */
const errorHandler = (err, req, res, next) => {
  // Log the error
  logger.error('Unhandled error occurred', {
    error: err.message,
    stack: err.stack,
    url: req.originalUrl,
    method: req.method,
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    body: req.body,
    params: req.params,
    query: req.query
  });

  // Default error response
  let statusCode = 500;
  let errorResponse = {
    error: 'Internal server error',
    code: 'INTERNAL_SERVER_ERROR',
    message: 'An unexpected error occurred'
  };

  // Handle specific error types
  if (err.name === 'ValidationError') {
    statusCode = 400;
    errorResponse = {
      error: 'Validation error',
      code: 'VALIDATION_ERROR',
      message: err.message,
      details: err.details || []
    };
  } else if (err.name === 'UnauthorizedError') {
    statusCode = 401;
    errorResponse = {
      error: 'Unauthorized',
      code: 'UNAUTHORIZED',
      message: 'Authentication required'
    };
  } else if (err.name === 'ForbiddenError') {
    statusCode = 403;
    errorResponse = {
      error: 'Forbidden',
      code: 'FORBIDDEN',
      message: 'Access denied'
    };
  } else if (err.name === 'NotFoundError') {
    statusCode = 404;
    errorResponse = {
      error: 'Not found',
      code: 'NOT_FOUND',
      message: err.message || 'Resource not found'
    };
  } else if (err.code === 'LIMIT_FILE_SIZE') {
    statusCode = 413;
    errorResponse = {
      error: 'File too large',
      code: 'FILE_TOO_LARGE',
      message: 'The uploaded file exceeds the size limit'
    };
  } else if (err.type === 'entity.parse.failed') {
    statusCode = 400;
    errorResponse = {
      error: 'Invalid JSON',
      code: 'INVALID_JSON',
      message: 'Request body contains invalid JSON'
    };
  } else if (err.code === 'ENOTFOUND' || err.code === 'ECONNREFUSED') {
    statusCode = 503;
    errorResponse = {
      error: 'Service unavailable',
      code: 'SERVICE_UNAVAILABLE',
      message: 'External service is currently unavailable'
    };
  } else if (err.code === 'ETIMEDOUT') {
    statusCode = 504;
    errorResponse = {
      error: 'Gateway timeout',
      code: 'GATEWAY_TIMEOUT',
      message: 'Request timed out'
    };
  }

  // Add request ID for tracking
  errorResponse.requestId = req.id || generateRequestId();
  errorResponse.timestamp = new Date().toISOString();

  // In development, include stack trace
  if (process.env.NODE_ENV === 'development') {
    errorResponse.stack = err.stack;
  }

  res.status(statusCode).json(errorResponse);
};

/**
 * Async error wrapper
 * Wraps async route handlers to catch errors and pass them to error handler
 */
const asyncHandler = (fn) => {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};

/**
 * 404 handler for unknown routes
 */
const notFoundHandler = (req, res) => {
  logger.warn('404 - Route not found', {
    url: req.originalUrl,
    method: req.method,
    ip: req.ip
  });

  res.status(404).json({
    error: 'Not found',
    code: 'ROUTE_NOT_FOUND',
    message: `Route ${req.method} ${req.originalUrl} not found`,
    timestamp: new Date().toISOString()
  });
};

/**
 * Generate a simple request ID for error tracking
 */
const generateRequestId = () => {
  return Date.now().toString(36) + Math.random().toString(36).substr(2);
};

module.exports = {
  errorHandler,
  asyncHandler,
  notFoundHandler
};
