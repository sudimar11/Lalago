#!/usr/bin/env node

/**
 * Script to set up initial referral settings in Firebase
 * Run this script after deploying the backend to initialize the remote settings
 */

const { initializeFirebase, getFirestore, COLLECTIONS } = require('../services/firebaseService');
const logger = require('../utils/logger');

const setupReferralSettings = async () => {
  try {
    console.log('🚀 Setting up referral system settings...');
    
    // Initialize Firebase
    initializeFirebase();
    const firestore = getFirestore();

    // Default referral settings
    const referralSettings = {
      enableAutoGeneration: true, // Enable referral code auto-generation
      referralRewardAmount: '20.0', // Default reward amount
      maxReferralReward: '100.0', // Maximum total reward per user
      referralCodeLength: 6, // Length of referral codes
      lastUpdated: new Date(),
      createdAt: new Date(),
      description: 'Referral system configuration - toggle enableAutoGeneration to control rollout'
    };

    // Set referral settings
    await firestore
      .collection(COLLECTIONS.SETTINGS)
      .doc('referralSettings')
      .set(referralSettings, { merge: true });

    console.log('✅ Referral settings configured successfully');
    console.log('📋 Settings:', JSON.stringify(referralSettings, null, 2));

    // Also set up general referral amount setting for backward compatibility
    const referralAmountSetting = {
      referralAmount: '20.0',
      lastUpdated: new Date()
    };

    await firestore
      .collection(COLLECTIONS.SETTINGS)
      .doc('referral_amount')
      .set(referralAmountSetting, { merge: true });

    console.log('✅ Legacy referral amount setting configured');

    console.log('\n🎯 Next steps:');
    console.log('1. Deploy your backend server');
    console.log('2. Update your Flutter app to call the new backend endpoints');
    console.log('3. Test the referral code generation');
    console.log('4. To disable referral generation, set enableAutoGeneration to false in Firestore');

    process.exit(0);

  } catch (error) {
    console.error('❌ Error setting up referral settings:', error);
    process.exit(1);
  }
};

// Run the setup if this script is executed directly
if (require.main === module) {
  setupReferralSettings();
}

module.exports = { setupReferralSettings };
