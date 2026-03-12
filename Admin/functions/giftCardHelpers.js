const crypto = require('crypto');
const admin = require('firebase-admin');

const ALPHANUM = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude 0,O,1,I for readability

/**
 * Get FCM tokens for a user.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} userId
 * @returns {Promise<string[]>}
 */
async function getUserFcmTokens(db, userId) {
  const doc = await db.collection('users').doc(userId).get();
  if (!doc.exists) return [];
  const data = doc.data() || {};
  const arr = data.fcmTokens;
  if (Array.isArray(arr) && arr.length > 0) {
    return arr.filter(t => typeof t === 'string' && t.trim().length > 0).map(t => t.trim());
  }
  const single = data.fcmToken;
  if (single && typeof single === 'string' && single.trim().length > 0) {
    return [single.trim()];
  }
  return [];
}

/**
 * Send FCM notification for gift card events.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} userId
 * @param {string} title
 * @param {string} body
 * @param {object} data
 */
async function sendGiftCardFCM(db, userId, title, body, data = {}) {
  const tokens = await getUserFcmTokens(db, userId);
  if (tokens.length === 0) return;
  const msgData = {
    timestamp: Date.now().toString(),
    type: 'gift_card',
    ...Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])
    ),
  };
  const messaging = admin.apps.length ? admin.messaging() : null;
  if (!messaging) return;
  try {
    await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: msgData,
      android: { priority: 'high', notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch (e) {
    console.warn('[sendGiftCardFCM] Failed:', e?.message || e);
  }
}

/**
 * Generate a LALA-XXXXXXXXXXXX format gift card code (code-only, no PIN).
 * Uses cryptographically secure random.
 * @returns {string} e.g. "LALA-A1B2C3D4E5F6"
 */
function generateGiftCardCode() {
  let result = 'LALA-';
  const bytes = crypto.randomBytes(12);
  for (let i = 0; i < 12; i++) {
    result += ALPHANUM[bytes[i] % ALPHANUM.length];
  }
  return result;
}

/**
 * Get gift card config from Firestore.
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<object|null>}
 */
async function getConfig(db) {
  const snap = await db.collection('settings').doc('giftCardConfig').get();
  if (!snap.exists) return null;
  return snap.data() || null;
}

/**
 * Validate amount against config (denominations or custom range).
 * @param {number} amount
 * @param {object} config - giftCardConfig
 * @returns {{ valid: boolean, error?: string }}
 */
function validateAmount(amount, config) {
  if (!config) return { valid: false, error: 'Gift card not configured' };
  const num = Number(amount);
  if (isNaN(num) || num <= 0) return { valid: false, error: 'Invalid amount' };

  const denominations = config.denominations;
  const allowCustom = config.allowCustomAmount === true;
  const minCustom = Number(config.customAmountMin) || 50;
  const maxCustom = Number(config.customAmountMax) || 10000;

  if (Array.isArray(denominations) && denominations.includes(num)) {
    return { valid: true };
  }
  if (allowCustom && num >= minCustom && num <= maxCustom) {
    return { valid: true };
  }
  return {
    valid: false,
    error: `Amount must be one of [${(denominations || []).join(', ')}] or between ${minCustom} and ${maxCustom}`,
  };
}

module.exports = {
  generateGiftCardCode,
  getConfig,
  validateAmount,
  getUserFcmTokens,
  sendGiftCardFCM,
};
