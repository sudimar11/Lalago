/**
 * One-time migration: Add createdAt to users that lack it.
 * Users without createdAt are excluded from orderBy('createdAt') queries.
 * Run from Admin/functions:
 *   GCLOUD_PROJECT=lalago-v2 node migrations/backfillUsersCreatedAt.js
 * Auth: Run `gcloud auth application-default login` first, or set
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function getProjectId() {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  try {
    const firebaserc = path.join(__dirname, '../../.firebaserc');
    const data = JSON.parse(fs.readFileSync(firebaserc, 'utf8'));
    return data?.projects?.default || 'lalago-v2';
  } catch {
    return 'lalago-v2';
  }
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: getProjectId() });
}

async function backfillUsersCreatedAt() {
  const db = admin.firestore();
  const snapshot = await db.collection('users').get();
  let count = 0;

  const batchSize = 500;
  let batch = db.batch();
  let opCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!data.createdAt) {
      const createdAt = doc.createTime
        ? doc.createTime
        : admin.firestore.FieldValue.serverTimestamp();
      batch.update(doc.ref, { createdAt });
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

  console.log(`Updated ${count} users with createdAt`);
}

backfillUsersCreatedAt()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
