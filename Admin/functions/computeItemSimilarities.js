/**
 * Daily Cloud Function: Compute item (product) similarities from order co-occurrence.
 * Runs at 3 AM Asia/Manila.
 * Stores results in item_similarities collection.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const SIMILARITIES = 'item_similarities';

exports.computeItemSimilarities = functions
  .region('us-central1')
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = admin.firestore();
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const ordersSnap = await db
      .collection(ORDERS)
      .where('createdAt', '>=', thirtyDaysAgo)
      .get();

    const cooccurrence = {};
    const itemCounts = {};

    for (const doc of ordersSnap.docs) {
      const order = doc.data();
      const products = order.products || [];

      for (const p of products) {
        const productId = p.id || p['id'];
        if (!productId || typeof productId !== 'string') continue;
        itemCounts[productId] = (itemCounts[productId] || 0) + 1;
      }

      const ids = products
        .map((p) => p.id || p['id'])
        .filter((id) => id && typeof id === 'string');
      const uniqueIds = [...new Set(ids)];

      for (let i = 0; i < uniqueIds.length; i++) {
        for (let j = i + 1; j < uniqueIds.length; j++) {
          const pair = [uniqueIds[i], uniqueIds[j]].sort().join('_');
          cooccurrence[pair] = (cooccurrence[pair] || 0) + 1;
        }
      }
    }

    const batchSize = 500;
    let batch = db.batch();
    let opCount = 0;

    for (const pair of Object.keys(cooccurrence)) {
      const [item1, item2] = pair.split('_');
      const coCount = cooccurrence[pair];
      const count1 = itemCounts[item1] || 0;
      const count2 = itemCounts[item2] || 0;
      const similarity =
        count1 + count2 - coCount > 0
          ? coCount / (count1 + count2 - coCount)
          : 0;

      if (similarity > 0.1) {
        const ref = db.collection(SIMILARITIES).doc(pair);
        batch.set(ref, {
          item1,
          item2,
          cooccurrenceCount: coCount,
          similarity,
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });
        opCount++;

        if (opCount >= batchSize) {
          await batch.commit();
          batch = db.batch();
          opCount = 0;
        }
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    console.log(
      `Computed similarities for ${Object.keys(cooccurrence).length} item pairs`
    );
  });
