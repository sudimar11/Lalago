const winston = require('winston');
const path = require('path');

// Define log format
const logFormat = winston.format.combine(
  winston.format.timestamp({
    format: 'YYYY-MM-DD HH:mm:ss'
  }),
  winston.format.errors({ stack: true }),
  winston.format.json(),
  winston.format.prettyPrint()
);

// Create logger instance
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: logFormat,
  defaultMeta: {
    service: 'play-integrity-api',
    version: process.env.npm_package_version || '1.0.0'
  },
  transports: [
    // Console transport
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// Add file transport if log file is specified
if (process.env.LOG_FILE) {
  const logDir = path.dirname(process.env.LOG_FILE);
  
  // Ensure log directory exists
  const fs = require('fs');
  if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
  }

  // Add file transport
  logger.add(new winston.transports.File({
    filename: process.env.LOG_FILE,
    maxsize: 10485760, // 10MB
    maxFiles: 5,
    format: logFormat
  }));

  // Add error file transport
  logger.add(new winston.transports.File({
    filename: process.env.LOG_FILE.replace('.log', '-error.log'),
    level: 'error',
    maxsize: 10485760, // 10MB
    maxFiles: 5,
    format: logFormat
  }));
}

// Log uncaught exceptions and unhandled rejections
logger.exceptions.handle(
  new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.simple()
    )
  })
);

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', {
    promise: promise,
    reason: reason
  });
});

// Add request logging helper
logger.logRequest = (req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    const logData = {
      method: req.method,
      url: req.originalUrl,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      contentLength: res.get('Content-Length') || 0
    };

    if (res.statusCode >= 400) {
      logger.warn('HTTP Request', logData);
    } else {
      logger.info('HTTP Request', logData);
    }
  });

  if (next) next();
};

// Add structured logging methods
logger.logIntegrityValidation = (data) => {
  logger.info('Integrity Validation', {
    type: 'integrity_validation',
    ...data
  });
};

logger.logSecurityEvent = (event, data) => {
  logger.warn('Security Event', {
    type: 'security_event',
    event,
    ...data
  });
};

logger.logApiUsage = (endpoint, data) => {
  logger.info('API Usage', {
    type: 'api_usage',
    endpoint,
    ...data
  });
};

module.exports = logger;
