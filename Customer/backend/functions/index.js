/**
 * Firebase Cloud Functions for LalaGo Referral System
 * 
 * To deploy:
 * 1. cd backend/functions
 * 2. npm install
 * 3. firebase deploy --only functions
 */

// Import the referral functions
const { createReferralCode, loginReferralCheck } = require('./referralCloudFunction');

// Export the functions
exports.createReferralCode = createReferralCode;
exports.loginReferralCheck = loginReferralCheck;
