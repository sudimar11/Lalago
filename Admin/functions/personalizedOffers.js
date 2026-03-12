/**
 * Personalized loyalty offers based on user preference profiles.
 * generatePersonalizedOffers: Pub/Sub weekly (Sunday 3 AM Asia/Manila).
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const USERS = 'users';
const CUSTOMER_OFFERS = 'customer_offers';
const MAX_OFFERS_PER_USER = 5;
const OFFER_EXPIRY_DAYS = 14;

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

/**
 * Rule-based offer generation from preferenceProfile.
 */
function generateOffersForUser(userId, pref, loyalty) {
  const offers = [];
  const tokens = loyalty?.tokensThisCycle ?? 0;
  const tier = (loyalty?.currentTier || 'bronze').toLowerCase();
  const favRestaurants = pref.favoriteRestaurants || [];
  const avgSpend = Number(pref.avgSpend) || 0;
  const cuisinePrefs = pref.cuisinePreferences || {};
  const lastVendorId = pref.lastOrderVendorId;

  if (favRestaurants.length > 0 && lastVendorId) {
    const topVendor = favRestaurants[0];
    const vendorId = topVendor.vendorId || topVendor.id || lastVendorId;
    offers.push({
      offerType: 'double_points_favorite',
      description: `Double points on your next order at your favorite restaurant!`,
      vendorId,
      pointsMultiplier: 2,
      expiresAt: null,
    });
  }

  if (avgSpend >= 300) {
    const minSpend = Math.round(avgSpend * 1.2);
    const bonusPoints = Math.min(15, Math.floor(minSpend / 50));
    if (bonusPoints >= 5) {
      offers.push({
        offerType: 'spend_bonus',
        description: `Spend ₱${minSpend}, earn ${bonusPoints} bonus points`,
        minSpend,
        pointsMultiplier: 1,
        bonusPoints,
        expiresAt: null,
      });
    }
  }

  if (Object.keys(cuisinePrefs).length > 0) {
    offers.push({
      offerType: 'try_new_restaurant',
      description: 'Bonus points for trying a new restaurant in your preferred cuisine',
      pointsMultiplier: 1.5,
      bonusPoints: 5,
      expiresAt: null,
    });
  }

  if (tier === 'bronze' || tier === 'silver') {
    offers.push({
      offerType: 'tier_boost',
      description: 'Complete 2 more orders this cycle to move up a tier!',
      pointsMultiplier: 1,
      expiresAt: null,
    });
  }

  return offers.slice(0, MAX_OFFERS_PER_USER);
}

/**
 * Pub/Sub: Generate personalized offers for users with preferenceProfile.
 */
exports.generatePersonalizedOffers = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 3 * * 0')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + OFFER_EXPIRY_DAYS * 86400000);

    const usersSnap = await db
      .collection(USERS)
      .where('role', '==', 'customer')
      .limit(500)
      .get();

    let created = 0;

    for (const doc of usersSnap.docs) {
      const pref = doc.data().preferenceProfile;
      if (!pref || typeof pref !== 'object') continue;

      const loyalty = doc.data().loyalty;
      const offers = generateOffersForUser(doc.id, pref, loyalty);
      if (offers.length === 0) continue;

      const batch = db.batch();

      for (const o of offers) {
        const ref = db.collection(CUSTOMER_OFFERS).doc();
        batch.set(ref, {
          userId: doc.id,
          offerType: o.offerType,
          description: o.description,
          vendorId: o.vendorId || null,
          productId: o.productId || null,
          pointsMultiplier: o.pointsMultiplier ?? 1,
          minSpend: o.minSpend ?? null,
          bonusPoints: o.bonusPoints ?? null,
          expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
          redeemedAt: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        created++;
      }

      await batch.commit();
    }

    console.log(
      `[generatePersonalizedOffers] Created ${created} offers for users with preferences`
    );
  });
