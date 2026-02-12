#!/usr/bin/env node

/**
 * Setup verification script for Play Integrity API backend
 * This script checks if all required configuration is in place
 */

const fs = require('fs');
const path = require('path');
const { google } = require('googleapis');

require('dotenv').config();

console.log('🔍 Verifying Play Integrity API Backend Setup...\n');

let hasErrors = false;
let hasWarnings = false;

function error(message) {
  console.log(`❌ ERROR: ${message}`);
  hasErrors = true;
}

function warning(message) {
  console.log(`⚠️  WARNING: ${message}`);
  hasWarnings = true;
}

function success(message) {
  console.log(`✅ ${message}`);
}

function info(message) {
  console.log(`ℹ️  ${message}`);
}

// Check Node.js version
function checkNodeVersion() {
  const nodeVersion = process.version;
  const majorVersion = parseInt(nodeVersion.split('.')[0].substring(1));
  
  if (majorVersion >= 16) {
    success(`Node.js version: ${nodeVersion}`);
  } else {
    error(`Node.js version ${nodeVersion} is not supported. Please use Node.js 16 or higher.`);
  }
}

// Check environment variables
function checkEnvironmentVariables() {
  const requiredVars = [
    'GOOGLE_CLOUD_PROJECT_ID',
    'GOOGLE_CLOUD_PROJECT_NUMBER',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'EXPECTED_PACKAGE_NAME',
    'API_KEY'
  ];

  const optionalVars = [
    'EXPECTED_APP_CERTIFICATE_SHA256',
    'PORT',
    'NODE_ENV',
    'LOG_LEVEL'
  ];

  console.log('\n📋 Environment Variables:');
  
  for (const varName of requiredVars) {
    const value = process.env[varName];
    if (value) {
      if (varName === 'API_KEY') {
        success(`${varName}: ${'*'.repeat(Math.min(value.length, 8))}... (${value.length} chars)`);
        if (value.length < 32) {
          warning(`${varName} is shorter than recommended 32 characters`);
        }
      } else if (varName === 'GOOGLE_APPLICATION_CREDENTIALS') {
        success(`${varName}: ${value}`);
      } else {
        success(`${varName}: ${value}`);
      }
    } else {
      error(`${varName} is not set`);
    }
  }

  for (const varName of optionalVars) {
    const value = process.env[varName];
    if (value) {
      if (varName === 'EXPECTED_APP_CERTIFICATE_SHA256') {
        success(`${varName}: ${value.substring(0, 8)}... (${value.length} chars)`);
      } else {
        success(`${varName}: ${value}`);
      }
    } else {
      info(`${varName}: not set (optional)`);
    }
  }
}

// Check service account file
function checkServiceAccountFile() {
  console.log('\n🔑 Service Account:');
  
  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialsPath) {
    error('GOOGLE_APPLICATION_CREDENTIALS not set');
    return;
  }

  const fullPath = path.resolve(credentialsPath);
  
  if (!fs.existsSync(fullPath)) {
    error(`Service account file not found: ${fullPath}`);
    return;
  }

  try {
    const credentials = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
    
    success(`Service account file found: ${fullPath}`);
    
    if (credentials.type === 'service_account') {
      success(`Service account type: ${credentials.type}`);
    } else {
      warning(`Unexpected credential type: ${credentials.type}`);
    }

    if (credentials.project_id) {
      success(`Service account project: ${credentials.project_id}`);
      
      if (credentials.project_id !== process.env.GOOGLE_CLOUD_PROJECT_ID) {
        warning(`Service account project (${credentials.project_id}) doesn't match GOOGLE_CLOUD_PROJECT_ID (${process.env.GOOGLE_CLOUD_PROJECT_ID})`);
      }
    }

    if (credentials.client_email) {
      success(`Service account email: ${credentials.client_email}`);
    }

  } catch (err) {
    error(`Failed to parse service account file: ${err.message}`);
  }
}

// Check Google Cloud authentication
async function checkGoogleCloudAuth() {
  console.log('\n☁️  Google Cloud Authentication:');
  
  try {
    const auth = new google.auth.GoogleAuth({
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      scopes: ['https://www.googleapis.com/auth/playintegrity']
    });

    const client = await auth.getClient();
    success('Google Cloud authentication successful');

    // Try to get project info
    const projectId = await auth.getProjectId();
    if (projectId) {
      success(`Authenticated project: ${projectId}`);
      
      if (projectId !== process.env.GOOGLE_CLOUD_PROJECT_ID) {
        warning(`Authenticated project (${projectId}) doesn't match GOOGLE_CLOUD_PROJECT_ID (${process.env.GOOGLE_CLOUD_PROJECT_ID})`);
      }
    }

  } catch (err) {
    error(`Google Cloud authentication failed: ${err.message}`);
  }
}

// Check Play Integrity API access
async function checkPlayIntegrityAPI() {
  console.log('\n🎮 Play Integrity API:');
  
  try {
    const auth = new google.auth.GoogleAuth({
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      scopes: ['https://www.googleapis.com/auth/playintegrity']
    });

    const playIntegrity = google.playintegrity('v1');
    
    // This will fail with a real token validation, but we can check if the API is accessible
    success('Play Integrity API client initialized');
    
    info('Note: Full API access can only be verified with a real integrity token from your app');

  } catch (err) {
    error(`Play Integrity API initialization failed: ${err.message}`);
  }
}

// Check package configuration
function checkPackageConfiguration() {
  console.log('\n📦 Package Configuration:');
  
  const packageName = process.env.EXPECTED_PACKAGE_NAME;
  if (packageName) {
    success(`Expected package name: ${packageName}`);
    
    // Basic validation of package name format
    if (!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(packageName)) {
      warning('Package name format may be invalid (should be like com.example.app)');
    }
  }

  const certificate = process.env.EXPECTED_APP_CERTIFICATE_SHA256;
  if (certificate) {
    success(`Expected certificate SHA256: ${certificate.substring(0, 8)}...`);
    
    // Basic validation of SHA256 format
    if (!/^[A-Fa-f0-9]{64}$/.test(certificate)) {
      warning('Certificate SHA256 format may be invalid (should be 64 hex characters)');
    }
  } else {
    info('Certificate validation disabled (EXPECTED_APP_CERTIFICATE_SHA256 not set)');
  }
}

// Check dependencies
function checkDependencies() {
  console.log('\n📚 Dependencies:');
  
  const packageJsonPath = path.join(__dirname, '..', 'package.json');
  
  if (!fs.existsSync(packageJsonPath)) {
    error('package.json not found');
    return;
  }

  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    const dependencies = packageJson.dependencies || {};
    
    const requiredDeps = [
      'express',
      'googleapis',
      'dotenv',
      'winston',
      'helmet',
      'cors'
    ];

    for (const dep of requiredDeps) {
      if (dependencies[dep]) {
        success(`${dep}: ${dependencies[dep]}`);
      } else {
        error(`Required dependency missing: ${dep}`);
      }
    }

  } catch (err) {
    error(`Failed to read package.json: ${err.message}`);
  }
}

// Check log directory
function checkLogConfiguration() {
  console.log('\n📝 Logging Configuration:');
  
  const logFile = process.env.LOG_FILE;
  if (logFile) {
    const logDir = path.dirname(path.resolve(logFile));
    
    if (!fs.existsSync(logDir)) {
      try {
        fs.mkdirSync(logDir, { recursive: true });
        success(`Created log directory: ${logDir}`);
      } catch (err) {
        error(`Failed to create log directory: ${err.message}`);
      }
    } else {
      success(`Log directory exists: ${logDir}`);
    }
    
    success(`Log file configured: ${logFile}`);
  } else {
    info('Log file not configured (will log to console only)');
  }

  const logLevel = process.env.LOG_LEVEL || 'info';
  success(`Log level: ${logLevel}`);
}

// Main verification function
async function main() {
  console.log('Play Integrity API Backend Setup Verification');
  console.log('='.repeat(50));

  checkNodeVersion();
  checkEnvironmentVariables();
  checkServiceAccountFile();
  await checkGoogleCloudAuth();
  await checkPlayIntegrityAPI();
  checkPackageConfiguration();
  checkDependencies();
  checkLogConfiguration();

  console.log('\n' + '='.repeat(50));
  
  if (hasErrors) {
    console.log('❌ Setup verification FAILED');
    console.log('Please fix the errors above before starting the server.');
    process.exit(1);
  } else if (hasWarnings) {
    console.log('⚠️  Setup verification completed with WARNINGS');
    console.log('The server should work, but consider addressing the warnings above.');
  } else {
    console.log('✅ Setup verification PASSED');
    console.log('Your backend server is ready to run!');
  }

  console.log('\nNext steps:');
  console.log('1. Start the server: npm start');
  console.log('2. Test health endpoint: curl http://localhost:3000/health');
  console.log('3. Test with a real integrity token from your Flutter app');
}

if (require.main === module) {
  main().catch(err => {
    console.error('Verification failed:', err.message);
    process.exit(1);
  });
}

module.exports = { main };
