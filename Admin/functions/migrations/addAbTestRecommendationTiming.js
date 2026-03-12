/**
 * One-time migration: Create ab_tests/recommendation_timing_test for A/B timing.
 * Run: node migrations/addAbTestRecommendationTiming.js
 * (from Admin/functions directory, with GOOGLE_APPLICATION_CREDENTIALS set if needed)
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Resolve project ID from Firebase config or env
let projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
if (!projectId) {
  try {
    const firebaserc = JSON.parse(
      fs.readFileSync(path.join(__dirname, '../../.firebaserc'), 'utf8')
    );
    projectId = firebaserc.projects?.default;
  } catch (_) {}
}

if (!admin.apps.length) {
  admin.initializeApp(projectId ? { projectId } : {});
}

async function addAbTestRecommendationTiming() {
  const db = admin.firestore();
  const ref = db.collection('ab_tests').doc('recommendation_timing_test');
  const doc = await ref.get();

  if (doc.exists) {
    console.log('ab_tests/recommendation_timing_test already exists');
    return;
  }

  await ref.set({
    status: 'active',
    variants: [
      { name: 'control', percentage: 50 },
      { name: 'variant_a', percentage: 25 },
      { name: 'variant_b', percentage: 25 },
    ],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log('Created ab_tests/recommendation_timing_test');
}

addAbTestRecommendationTiming()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
