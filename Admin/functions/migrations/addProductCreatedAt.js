/**
 * One-time migration: Add createdAt to vendor_products that lack it.
 * Run: node migrations/addProductCreatedAt.js
 * (from Admin/functions directory, with GOOGLE_APPLICATION_CREDENTIALS set if needed)
 */

const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

async function addProductCreatedAt() {
  const db = admin.firestore();
  const snapshot = await db.collection('vendor_products').get();
  let count = 0;

  const batchSize = 500;
  let batch = db.batch();
  let opCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!data.createdAt) {
      batch.update(doc.ref, {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
      opCount++;
    }
    if (opCount >= batchSize) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
  }

  console.log(`Updated ${count} products with createdAt`);
}

addProductCreatedAt()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
