const admin = require('firebase-admin');
const logger = require('../utils/logger');

// Initialize Firebase Admin SDK
let firestore;

const initializeFirebase = () => {
  try {
    // Initialize Firebase Admin SDK with service account
    if (!admin.apps.length) {
      const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_KEY 
        ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY)
        : require(process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '../firebase-service-account.json');

      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: process.env.FIREBASE_PROJECT_ID
      });
    }

    firestore = admin.firestore();
    logger.info('Firebase Admin SDK initialized successfully');
    return firestore;
  } catch (error) {
    logger.error('Failed to initialize Firebase Admin SDK:', error);
    throw error;
  }
};

const getFirestore = () => {
  if (!firestore) {
    return initializeFirebase();
  }
  return firestore;
};

// Firebase collections constants
const COLLECTIONS = {
  USERS: 'users',
  REFERRAL: 'referral',
  SETTINGS: 'settings'
};

module.exports = {
  initializeFirebase,
  getFirestore,
  COLLECTIONS,
  admin
};
