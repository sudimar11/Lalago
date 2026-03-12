/**
 * Migration: normalize message read field to `isRead`.
 *
 * Usage:
 *   node migrations/migrateMessageReadField.js
 */
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function migrateCollectionGroupThread() {
  const snap = await db.collectionGroup('thread').get();
  let updated = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (Object.prototype.hasOwnProperty.call(data, 'isread')) {
      const next = Boolean(data.isread);
      await doc.ref.set(
        {
          isRead: next,
          isread: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );
      updated++;
    } else if (!Object.prototype.hasOwnProperty.call(data, 'isRead')) {
      await doc.ref.set({ isRead: false }, { merge: true });
      updated++;
    }
  }
  return updated;
}

async function migrateOrderMessages() {
  const snap = await db.collectionGroup('messages').get();
  let updated = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const parent = doc.ref.parent.parent;
    if (!parent) continue;
    if (parent.parent && parent.parent.id === 'order_messages') {
      if (!Object.prototype.hasOwnProperty.call(data, 'isRead')) {
        await doc.ref.set({ isRead: false }, { merge: true });
        updated++;
      }
    }
  }
  return updated;
}

async function migrateCanonicalMessages() {
  const snap = await db.collectionGroup('messages').get();
  let updated = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const parent = doc.ref.parent.parent;
    if (!parent) continue;
    if (parent.parent == null && parent.id) {
      // Guard no-op
    }
    if (doc.ref.path.includes('/order_communications/')) {
      if (!Object.prototype.hasOwnProperty.call(data, 'isRead')) {
        await doc.ref.set({ isRead: false }, { merge: true });
        updated++;
      }
    }
  }
  return updated;
}

async function main() {
  console.log('[migrateMessageReadField] starting...');
  const threadUpdated = await migrateCollectionGroupThread();
  const legacyUpdated = await migrateOrderMessages();
  const canonicalUpdated = await migrateCanonicalMessages();
  console.log(
    `[migrateMessageReadField] done thread=${threadUpdated}, order_messages=${legacyUpdated}, canonical=${canonicalUpdated}`
  );
  process.exit(0);
}

main().catch((err) => {
  console.error('[migrateMessageReadField] failed', err);
  process.exit(1);
});

