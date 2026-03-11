/**
 * Backfill legacy order_messages -> canonical order_communications.
 *
 * Usage:
 *   node migrations/backfillOrderCommunications.js
 */
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function backfill() {
  const ordersSnap = await db.collection('order_messages').get();
  let migratedOrders = 0;
  let migratedMessages = 0;

  for (const orderDoc of ordersSnap.docs) {
    const orderId = orderDoc.id;
    const msgsSnap = await orderDoc.ref
      .collection('messages')
      .orderBy('createdAt', 'asc')
      .get();
    if (msgsSnap.empty) continue;

    const canonicalDoc = db.collection('order_communications').doc(orderId);
    await canonicalDoc.set(
      {
        orderId,
        migratedFromLegacyAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    for (const msg of msgsSnap.docs) {
      const d = msg.data() || {};
      await canonicalDoc.collection('messages').doc(msg.id).set(
        {
          type: d.messageType === 'issue' ? 'issue' : 'quick_action',
          messageKey: d.messageKey || '',
          text: d.messageText || '',
          senderRole: d.senderType === 'restaurant' ? 'restaurant' : 'rider',
          senderId: d.senderId || '',
          status: d.isRead ? 'read' : 'sent',
          isRead: Boolean(d.isRead),
          createdAt:
            d.createdAt || admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          legacyRef: msg.ref.path,
        },
        { merge: true }
      );
      migratedMessages++;
    }
    migratedOrders++;
  }

  console.log(
    `[backfillOrderCommunications] migratedOrders=${migratedOrders} migratedMessages=${migratedMessages}`
  );
}

backfill()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('[backfillOrderCommunications] failed', e);
    process.exit(1);
  });

