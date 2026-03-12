/**
 * HTTP webhook for payment failures (PayMongo, GCash, etc.).
 * Updates order status and triggers OrderRecoveryService.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OrderRecoveryService = require('./orderRecoveryService');

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function setCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Max-Age', '86400');
}

exports.handlePaymentFailure = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    setCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    try {
      const body = req.body || {};
      const orderId = body.orderId || body.order_id;
      const paymentIntentId = body.paymentIntentId || body.payment_intent_id;
      const failureCode = body.failureCode || body.failure_code;
      const failureMessage = body.failureMessage || body.failure_message || 'Payment processing failed';
      const paymentMethod = body.paymentMethod || body.payment_method || '';

      if (!orderId) {
        res.status(400).json({ error: 'Missing orderId' });
        return;
      }

      const db = getDb();
      const orderRef = db.collection('restaurant_orders').doc(orderId);
      const orderDoc = await orderRef.get();

      if (!orderDoc.exists) {
        res.status(404).json({ error: 'Order not found' });
        return;
      }

      const orderData = orderDoc.data() || {};

      await orderRef.update({
        status: 'Payment Failed',
        failureType: 'payment',
        failureReason: failureMessage,
        failureDetails: {
          paymentIntentId: paymentIntentId || null,
          failureCode: failureCode || null,
          paymentMethod: paymentMethod || null,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });

      const fullOrderData = { id: orderId, ...orderData };
      await OrderRecoveryService.handleOrderFailure(
        fullOrderData,
        'payment_failed',
        { failureCode, failureMessage, paymentMethod, paymentIntentId }
      );

      res.status(200).json({ success: true });
    } catch (error) {
      console.error('[handlePaymentFailure] Error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
