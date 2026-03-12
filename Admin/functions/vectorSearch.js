/**
 * Multi-stage vector search for Lalago AI product search.
 * - onProductWrite: generates embeddings when products are created/updated
 * - vectorSearchProducts: callable that performs vector similarity search
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { Firestore, FieldValue } = require('@google-cloud/firestore');
const { PredictionServiceClient } = require('@google-cloud/aiplatform').v1;
const { helpers } = require('@google-cloud/aiplatform');

const EMBEDDING_MODEL = 'text-multilingual-embedding-002';
const EMBEDDING_DIM = 768;
const VENDOR_PRODUCTS = 'vendor_products';
const VENDORS = 'vendors';
const VENDOR_CATEGORIES = 'vendor_categories';

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function getFirestoreForVector() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return new Firestore({ projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT });
}

/**
 * Generate embedding for text using Vertex AI.
 */
async function generateEmbedding(text) {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!project) {
    throw new Error('GCLOUD_PROJECT not set');
  }
  const client = new PredictionServiceClient({
    apiEndpoint: 'us-central1-aiplatform.googleapis.com',
  });
  const endpoint = `projects/${project}/locations/us-central1/publishers/google/models/${EMBEDDING_MODEL}`;
  const instance = helpers.toValue({ content: text });
  const parameters = helpers.toValue({ outputDimensionality: EMBEDDING_DIM });
  const [response] = await client.predict({
    endpoint,
    instances: [instance],
    parameters,
  });
  const predictions = response.predictions || [];
  if (predictions.length === 0) {
    throw new Error('No embedding returned');
  }
  const p = predictions[0];
  const embeddingsProto = p.structValue?.fields?.embeddings;
  const valuesProto = embeddingsProto?.structValue?.fields?.values;
  const values = valuesProto?.listValue?.values || [];
  return values.map((v) => parseFloat(v.numberValue || 0));
}

/**
 * Build text for product embedding: name, description, category.
 */
function buildProductText(data, categoryTitle = '') {
  const name = (data.name || '').toString().trim();
  const desc = (data.description || '').toString().trim();
  const parts = [name, desc];
  if (categoryTitle) {
    parts.push(categoryTitle);
  }
  return parts.filter(Boolean).join(' ').trim() || name || 'product';
}

/**
 * Firestore trigger: generate and store embedding when product is created/updated.
 */
exports.onProductWrite = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .firestore.document(`${VENDOR_PRODUCTS}/{productId}`)
  .onWrite(async (change, context) => {
    const productId = context.params.productId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) return null;

    const nameBefore = before?.name || '';
    const descBefore = before?.description || '';
    const nameAfter = (after.name || '').toString();
    const descAfter = (after.description || '').toString();

    if (nameBefore === nameAfter && descBefore === descAfter && before) {
      return null;
    }

    const db = getDb();
    let categoryTitle = '';
    const categoryID = (after.categoryID || '').toString();
    if (categoryID) {
      try {
        const catSnap = await db.collection(VENDOR_CATEGORIES).doc(categoryID).get();
        if (catSnap.exists && catSnap.data()) {
          categoryTitle = (catSnap.data().title || '').toString();
        }
      } catch (e) {
        console.warn('[onProductWrite] Could not fetch category:', e.message);
      }
    }

    const text = buildProductText(after, categoryTitle);
    if (!text) return null;

    try {
      const embedding = await generateEmbedding(text);
      const fs = getFirestoreForVector();
      await fs.collection(VENDOR_PRODUCTS).doc(productId).update({
        embedding: FieldValue.vector(embedding),
      });
      console.log(`[onProductWrite] Updated embedding for product ${productId}`);
    } catch (e) {
      console.error(`[onProductWrite] Error for product ${productId}:`, e);
    }
    return null;
  });

/**
 * Callable: vector search products. Returns same shape as AiProductSearchService.
 */
exports.vectorSearchProducts = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '512MB' })
  .https.onCall(async (data, context) => {
    const query = (data?.query || '').toString().trim();
    if (!query) {
      return { products: [], error: 'Query is required' };
    }

    const fs = getFirestoreForVector();
    const db = getDb();
    const vendorCache = {};

    async function getVendorName(vendorID) {
      if (!vendorID) return '';
      if (vendorCache[vendorID]) return vendorCache[vendorID];
      try {
        const doc = await db.collection(VENDORS).doc(vendorID).get();
        const title = doc.exists && doc.data() ? (doc.data().title || '') : '';
        vendorCache[vendorID] = title;
        return title;
      } catch (e) {
        return '';
      }
    }

    function toImageUrl(photo) {
      const url = (photo || '').toString().trim();
      return url || 'https://via.placeholder.com/150';
    }

    try {
      const queryEmbedding = await generateEmbedding(query);

      const coll = fs.collection(VENDOR_PRODUCTS);
      const vectorQuery = coll.findNearest({
        vectorField: 'embedding',
        queryVector: queryEmbedding,
        limit: 200,
        distanceMeasure: 'COSINE',
      });

      const snapshot = await vectorQuery.get();
      const results = [];

      let pos = 0;
      for (const doc of snapshot.docs) {
        const d = doc.data();
        if (d.publish !== true) continue;
        const vendorID = (d.vendorID || '').toString();
        const rating = (d.reviewsCount > 0 && d.reviewsSum != null)
          ? (d.reviewsSum / d.reviewsCount)
          : 0;
        const orderCount = (d.orderCount || 0) | 0;
        const posBoost = 1 / (pos + 1);
        const rankScore = posBoost * (1 + 0.2 * (rating / 5)) * (1 + 0.1 * Math.min(orderCount / 50, 1));
        pos++;
        results.push({
          id: (d.id || doc.id).toString(),
          name: (d.name || '').toString(),
          price: (d.price || '0').toString(),
          vendorID,
          imageUrl: toImageUrl(d.photo),
          _rankScore: rankScore,
        });
      }

      results.sort((a, b) => b._rankScore - a._rankScore);
      const top = results.slice(0, 30);

      for (const p of top) {
        delete p._rankScore;
        p.vendorName = await getVendorName(p.vendorID);
      }

      return { products: top };
    } catch (e) {
      console.error('[vectorSearchProducts] Error:', e);
      return { products: [], error: e.message };
    }
  });
