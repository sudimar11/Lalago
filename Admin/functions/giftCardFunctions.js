const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { generateGiftCardCode, getConfig, validateAmount, sendGiftCardFCM } = require('./giftCardHelpers');

function getDb() {
  if (!admin.apps.length) admin.initializeApp();
  return admin.firestore();
}

/**
 * Ensure code is unique by checking existing gift_cards.
 */
async function ensureUniqueCode(db, code) {
  const snap = await db.collection('gift_cards').where('code', '==', code).limit(1).get();
  return snap.empty;
}

/**
 * Callable: createGiftCard
 * Creates a new gift card with server-generated LALA- code.
 */
exports.createGiftCard = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const purchaserId = context.auth.uid;
    const amount = Number(data?.amount);
    const giftMessage = (data?.giftMessage || '').toString().trim();
    const deliveryMethod = (data?.deliveryMethod || 'direct').toString();
    const recipientEmail = (data?.recipientEmail || '').toString().trim() || null;
    const designTemplate = (data?.designTemplate || 'celebration').toString();

    const db = getDb();
    const config = await getConfig(db);
    if (!config || !config.enabled) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Gift cards are not enabled'
      );
    }

    const validation = validateAmount(amount, config);
    if (!validation.valid) {
      throw new functions.https.HttpsError('invalid-argument', validation.error);
    }

    let code = generateGiftCardCode();
    for (let attempts = 0; attempts < 5; attempts++) {
      const isUnique = await ensureUniqueCode(db, code);
      if (isUnique) break;
      code = generateGiftCardCode();
    }

    const validityDays = Number(config.validityDays) || 365;
    const purchasedAt = admin.firestore.Timestamp.now();
    const expiresAtDate = new Date(purchasedAt.toDate());
    expiresAtDate.setDate(expiresAtDate.getDate() + validityDays);
    const expiresAt = admin.firestore.Timestamp.fromDate(expiresAtDate);

    const cardData = {
      code,
      originalAmount: amount,
      remainingBalance: amount,
      currency: 'PHP',
      status: 'active',

      purchasedBy: purchaserId,
      ownedBy: recipientEmail ? purchaserId : purchaserId,
      pendingRecipientEmail: recipientEmail || null,

      purchasedAt,
      expiresAt,
      lastUsedAt: null,

      redemptionHistory: [],
      giftMessage,
      deliveryMethod,
      designTemplate,
      source: 'in_app_purchase',
    };

    const cardRef = db.collection('gift_cards').doc();
    const txRef = db.collection('gift_card_transactions').doc();

    await db.runTransaction(async (tx) => {
      tx.set(cardRef, { ...cardData, id: cardRef.id });
      tx.set(txRef, {
        cardId: cardRef.id,
        type: 'purchase',
        amount,
        previousBalance: 0,
        newBalance: amount,
        orderId: null,
        userId: purchaserId,
        timestamp: purchasedAt,
      });
    });

    try {
      const title = recipientEmail ? 'Gift card sent' : 'Gift card purchased';
      const body = recipientEmail
        ? `You sent a ${amount} PHP gift card to ${recipientEmail}`
        : `Your gift card (${code}) is ready. Balance: ${amount} PHP`;
      await sendGiftCardFCM(db, purchaserId, title, body, {
        type: 'gift_card_purchased',
        cardId: cardRef.id,
        code,
        amount: String(amount),
      });
    } catch (fcmErr) {
      console.warn('[createGiftCard] FCM failed:', fcmErr?.message);
    }

    return {
      cardId: cardRef.id,
      code,
      expiresAt: expiresAt.toDate().toISOString(),
    };
  });

/**
 * Callable: validateGiftCard
 * Validates a gift card code and returns balance info.
 */
exports.validateGiftCard = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const code = (data?.code || '').toString().trim().toUpperCase();
    if (!code) {
      throw new functions.https.HttpsError('invalid-argument', 'Code required');
    }

    const db = getDb();
    const snap = await db.collection('gift_cards').where('code', '==', code).limit(1).get();
    if (snap.empty) {
      return { valid: false, error: 'Invalid gift card code' };
    }

    const doc = snap.docs[0];
    const card = doc.data();
    const cardId = doc.id;

    if (card.status !== 'active') {
      return { valid: false, error: 'Gift card is no longer active' };
    }

    const now = admin.firestore.Timestamp.now();
    if (card.expiresAt && card.expiresAt.toMillis && card.expiresAt.toMillis() < now.toMillis()) {
      return { valid: false, error: 'Gift card has expired' };
    }

    const balance = Number(card.remainingBalance) || 0;
    if (balance <= 0) {
      return { valid: false, error: 'Gift card has no remaining balance' };
    }

    const needsClaim = !!(card.pendingRecipientEmail && card.pendingRecipientEmail.toString().trim());

    return {
      valid: true,
      cardId,
      remainingBalance: balance,
      needsClaim,
    };
  });

/**
 * Callable: redeemGiftCard
 * Deducts amount from gift card balance for an order.
 */
exports.redeemGiftCard = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const userId = context.auth.uid;
    const cardId = (data?.cardId || '').toString();
    const orderId = (data?.orderId || '').toString() || null;
    const amount = Number(data?.amount);

    if (!cardId || isNaN(amount) || amount <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'cardId and amount required');
    }

    const db = getDb();
    const cardRef = db.collection('gift_cards').doc(cardId);
    const cardSnap = await cardRef.get();
    if (!cardSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Gift card not found');
    }

    const card = cardSnap.data();
    if (card.ownedBy !== userId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'You do not own this gift card'
      );
    }
    if (card.status !== 'active') {
      throw new functions.https.HttpsError('failed-precondition', 'Gift card is not active');
    }

    const remainingBalance = Number(card.remainingBalance) || 0;
    if (amount > remainingBalance) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `Insufficient balance. Available: ${remainingBalance}`
      );
    }

    const now = admin.firestore.Timestamp.now();
    if (card.expiresAt && card.expiresAt.toMillis && card.expiresAt.toMillis() < now.toMillis()) {
      throw new functions.https.HttpsError('failed-precondition', 'Gift card has expired');
    }

    const newBalance = remainingBalance - amount;
    const redemptionHistory = Array.isArray(card.redemptionHistory) ? [...card.redemptionHistory] : [];
    redemptionHistory.push({
      orderId: orderId || null,
      amount,
      redeemedAt: now,
      remainingAfter: newBalance,
    });

    const updateData = {
      remainingBalance: newBalance,
      redemptionHistory,
      lastUsedAt: now,
    };
    if (newBalance <= 0) {
      updateData.status = 'redeemed';
    }

    const txRef = db.collection('gift_card_transactions').doc();
    await db.runTransaction(async (tx) => {
      tx.update(cardRef, updateData);
      tx.set(txRef, {
        cardId,
        type: 'redemption',
        amount,
        previousBalance: remainingBalance,
        newBalance,
        orderId: orderId || null,
        userId,
        timestamp: now,
      });
    });

    return { success: true, newBalance };
  });

/**
 * Callable: claimGiftCard
 * Transfers ownership when recipient claims a gift sent to their email.
 */
exports.claimGiftCard = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const userId = context.auth.uid;
    const code = (data?.code || '').toString().trim().toUpperCase();
    if (!code) {
      throw new functions.https.HttpsError('invalid-argument', 'Code required');
    }

    const db = getDb();
    const snap = await db.collection('gift_cards').where('code', '==', code).limit(1).get();
    if (snap.empty) {
      throw new functions.https.HttpsError('not-found', 'Gift card not found');
    }

    const doc = snap.docs[0];
    const card = doc.data();
    const cardId = doc.id;
    const pendingEmail = (card.pendingRecipientEmail || '').toString().trim().toLowerCase();

    if (!pendingEmail) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'This gift card is not pending claim. You can redeem it directly if you own it.'
      );
    }

    if (card.status !== 'active') {
      throw new functions.https.HttpsError('failed-precondition', 'Gift card is no longer active');
    }

    const userSnap = await db.collection('users').doc(userId).get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }
    const userData = userSnap.data() || {};
    const userEmail = (userData.email || userData.Email || '').toString().trim().toLowerCase();

    if (userEmail !== pendingEmail) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'This gift was sent to a different email address'
      );
    }

    const now = admin.firestore.Timestamp.now();
    const amount = Number(card.remainingBalance) || 0;

    await db.runTransaction(async (tx) => {
      tx.update(doc.ref, {
        ownedBy: userId,
        pendingRecipientEmail: null,
      });
    });

    try {
      await sendGiftCardFCM(db, userId, 'Gift card received', `You claimed a gift card worth ${amount} PHP`, {
        type: 'gift_card_received',
        cardId,
        amount: String(amount),
      });
    } catch (fcmErr) {
      console.warn('[claimGiftCard] FCM failed:', fcmErr?.message);
    }

    return {
      success: true,
      cardId,
      remainingBalance: amount,
    };
  });

/**
 * Scheduled/Manual: migrateLegacyGiftCards
 * Migrates unredeemed gift_purchases to new gift_cards schema.
 */
exports.migrateLegacyGiftCards = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540 })
  .https.onRequest(async (req, res) => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();

    const legacySnap = await db
      .collection('gift_purchases')
      .where('redeem', '==', false)
      .get();

    let migrated = 0;
    for (const doc of legacySnap.docs) {
      const d = doc.data();
      const expireDate = d.expireDate;
      if (expireDate && expireDate.toMillis && expireDate.toMillis() < now.toMillis()) {
        continue;
      }
      if (d.migratedTo) continue;

      let code = generateGiftCardCode();
      for (let i = 0; i < 5; i++) {
        const isUnique = await ensureUniqueCode(db, code);
        if (isUnique) break;
        code = generateGiftCardCode();
      }

      const amount = parseFloat(d.price) || 0;
      if (amount <= 0) continue;

      const cardRef = db.collection('gift_cards').doc();
      const cardData = {
        code,
        originalAmount: amount,
        remainingBalance: amount,
        currency: 'PHP',
        status: 'active',
        purchasedBy: d.userid || '',
        ownedBy: d.userid || '',
        pendingRecipientEmail: null,
        purchasedAt: d.createdDate || now,
        expiresAt: expireDate || admin.firestore.Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)),
        lastUsedAt: null,
        redemptionHistory: [],
        giftMessage: d.message || '',
        deliveryMethod: 'direct',
        designTemplate: 'celebration',
        source: 'legacy_migration',
        legacyPurchaseId: doc.id,
      };

      await db.runTransaction(async (tx) => {
        tx.set(cardRef, { ...cardData, id: cardRef.id });
        tx.set(db.collection('gift_card_transactions').doc(), {
          cardId: cardRef.id,
          type: 'purchase',
          amount,
          previousBalance: 0,
          newBalance: amount,
          orderId: null,
          userId: d.userid || '',
          timestamp: now,
        });
        tx.update(doc.ref, { migratedTo: cardRef.id, migratedAt: now });
      });
      migrated++;
    }

    res.status(200).json({ migrated, total: legacySnap.size });
  });

/**
 * Scheduled: processExpiredGiftCards
 * Runs daily to mark expired cards and send expiry reminders.
 */
exports.processExpiredGiftCards = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 300 })
  .pubsub.schedule('0 2 * * *')  // 2 AM daily
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();

    const activeSnap = await db
      .collection('gift_cards')
      .where('status', '==', 'active')
      .get();

    let expiredCount = 0;
    const reminderDays = [30, 7, 1];
    const usersToRemind = new Map(); // ownedBy -> [{ cardId, code, amount, expiresAt }]

    for (const doc of activeSnap.docs) {
      const card = doc.data();
      const expiresAt = card.expiresAt;
      if (!expiresAt || !expiresAt.toMillis) continue;

      const expiresMs = expiresAt.toMillis();
      const remainingBalance = Number(card.remainingBalance) || 0;

      if (expiresMs < nowMs) {
        await db.runTransaction(async (tx) => {
          tx.update(doc.ref, { status: 'expired' });
          tx.set(db.collection('gift_card_transactions').doc(), {
            cardId: doc.id,
            type: 'expiry',
            amount: remainingBalance,
            previousBalance: remainingBalance,
            newBalance: 0,
            orderId: null,
            userId: card.ownedBy || '',
            timestamp: now,
          });
        });
        expiredCount++;
      } else {
        const daysLeft = Math.floor((expiresMs - nowMs) / (24 * 60 * 60 * 1000));
        if (reminderDays.includes(daysLeft) && card.ownedBy) {
          const arr = usersToRemind.get(card.ownedBy) || [];
          arr.push({
            cardId: doc.id,
            code: card.code,
            amount: remainingBalance,
            expiresAt: expiresAt.toDate().toISOString().split('T')[0],
            daysLeft,
          });
          usersToRemind.set(card.ownedBy, arr);
        }
      }
    }

    for (const [userId, cards] of usersToRemind) {
      const c = cards[0];
      const title = `Gift card expiring in ${c.daysLeft} day${c.daysLeft > 1 ? 's' : ''}`;
      const body = `Your gift card (${c.code}) with balance ${c.amount} PHP expires on ${c.expiresAt}. Use it soon!`;
      try {
        await sendGiftCardFCM(db, userId, title, body, {
          type: 'gift_card_reminder',
          cardId: c.cardId,
          daysLeft: String(c.daysLeft),
        });
      } catch (e) {
        console.warn('[processExpiredGiftCards] FCM reminder failed:', e?.message);
      }
    }

    console.log(`[processExpiredGiftCards] Expired ${expiredCount} cards, sent ${usersToRemind.size} reminders`);
    return null;
  });

/**
 * Refund a gift card redemption (restore balance).
 * Used when an order is cancelled.
 */
async function refundGiftCardForOrder(db, cardId, amount, orderId) {
  const cardRef = db.collection('gift_cards').doc(cardId);
  const snap = await cardRef.get();
  if (!snap.exists) {
    console.warn(`[refundGiftCard] Card ${cardId} not found`);
    return;
  }
  const card = snap.data();
  if (card.status === 'expired') {
    console.warn(`[refundGiftCard] Card ${cardId} is expired, skip refund`);
    return;
  }
  const currentBalance = Number(card.remainingBalance) || 0;
  const newBalance = currentBalance + amount;
  const now = admin.firestore.Timestamp.now();
  const history = Array.isArray(card.redemptionHistory) ? [...card.redemptionHistory] : [];
  history.push({
    orderId,
    amount: -amount,
    redeemedAt: now,
    remainingAfter: newBalance,
    type: 'refund',
  });
  await db.runTransaction(async (tx) => {
    tx.update(cardRef, {
      remainingBalance: newBalance,
      status: 'active',
      redemptionHistory: history,
      lastUsedAt: now,
    });
    tx.set(db.collection('gift_card_transactions').doc(), {
      cardId,
      type: 'refund',
      amount,
      previousBalance: currentBalance,
      newBalance,
      orderId,
      userId: card.ownedBy || '',
      timestamp: now,
    });
  });
}

/**
 * Callable: refundGiftCard
 * Admin/System use - refunds a gift card for a cancelled order.
 */
exports.refundGiftCard = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }
    const cardId = (data?.cardId || '').toString();
    const amount = Number(data?.amount);
    const orderId = (data?.orderId || '').toString() || null;
    if (!cardId || isNaN(amount) || amount <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'cardId and amount required');
    }
    const db = getDb();
    await refundGiftCardForOrder(db, cardId, amount, orderId);
    return { success: true };
  });

exports._refundGiftCardForOrder = refundGiftCardForOrder;
