async function getActiveTest(testName, db) {
  const testDoc = await db.collection('ab_tests').doc(testName).get();
  if (!testDoc.exists) return null;
  const test = testDoc.data() || {};
  if (test.status !== 'active') return null;
  return test;
}

async function assignUserToVariant(userId, testName, db) {
  const assignmentId = `${testName}_${userId}`;
  const assignmentDoc = await db.collection('ab_assignments').doc(assignmentId).get();

  if (assignmentDoc.exists) {
    return assignmentDoc.data()?.variant || 'control';
  }

  const test = await getActiveTest(testName, db);
  if (!test) return 'control';

  const variants = test.variants || [];
  if (variants.length === 0) return 'control';

  const rand = Math.random() * 100;
  let cumulative = 0;
  let assignedVariant = variants[0]?.name || 'control';

  for (const v of variants) {
    cumulative += Number(v.percentage) || 0;
    if (rand < cumulative) {
      assignedVariant = v.name || 'control';
      break;
    }
  }

  const admin = require('firebase-admin');
  await db.collection('ab_assignments').doc(assignmentId).set({
    userId,
    testName,
    variant: assignedVariant,
    assignedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return assignedVariant;
}

/**
 * Get variant-specific send hour for timing A/B test
 */
async function getSendHourForVariant(userId, testName, defaultHour, db) {
  const variant = await assignUserToVariant(userId, testName, db);

  const variantConfigs = {
    control: { hour: defaultHour },
    variant_a: { hour: defaultHour - 1 },
    variant_b: { hour: defaultHour + 1 },
    variant_c: { hour: 12 },
  };

  const config = variantConfigs[variant];
  const hour = config ? config.hour : defaultHour;
  return Math.max(0, Math.min(23, hour));
}

module.exports = {
  getActiveTest,
  assignUserToVariant,
  getSendHourForVariant,
};
