/**
 * One-time script to generate embeddings for all existing vendor_products.
 *
 * Prerequisites:
 * - Vertex AI API enabled
 * - Firestore vector index created on vendor_products.embedding
 * - GOOGLE_APPLICATION_CREDENTIALS set or gcloud auth application-default login
 *
 * Run from Admin directory:
 *   node functions/scripts/backfillProductEmbeddings.js
 *
 * Or from functions directory:
 *   node scripts/backfillProductEmbeddings.js
 */

const admin = require('firebase-admin');
const { Firestore, FieldValue } = require('@google-cloud/firestore');
const { PredictionServiceClient } = require('@google-cloud/aiplatform').v1;
const { helpers } = require('@google-cloud/aiplatform');

const EMBEDDING_MODEL = 'text-multilingual-embedding-002';
const EMBEDDING_DIM = 768;
const VENDOR_PRODUCTS = 'vendor_products';
const VENDOR_CATEGORIES = 'vendor_categories';
const BATCH_SIZE = 50;
const DELAY_MS = 100;

function buildProductText(data, categoryTitle = '') {
  const name = (data.name || '').toString().trim();
  const desc = (data.description || '').toString().trim();
  const parts = [name, desc];
  if (categoryTitle) parts.push(categoryTitle);
  return parts.filter(Boolean).join(' ').trim() || name || 'product';
}

async function generateEmbedding(client, project, text) {
  const endpoint = `projects/${project}/locations/us-central1/publishers/google/models/${EMBEDDING_MODEL}`;
  const instance = helpers.toValue({ content: text });
  const parameters = helpers.toValue({ outputDimensionality: EMBEDDING_DIM });
  const [response] = await client.predict({
    endpoint,
    instances: [instance],
    parameters,
  });
  const predictions = response.predictions || [];
  if (predictions.length === 0) throw new Error('No embedding returned');
  const p = predictions[0];
  const valuesProto = p.structValue?.fields?.embeddings?.structValue?.fields?.values;
  const values = valuesProto?.listValue?.values || [];
  return values.map((v) => parseFloat(v.numberValue || 0));
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!project) {
    console.error('Set GCLOUD_PROJECT or GCP_PROJECT');
    process.exit(1);
  }

  const db = admin.firestore();
  const fs = new Firestore({ projectId: project });
  const predClient = new PredictionServiceClient({
    apiEndpoint: 'us-central1-aiplatform.googleapis.com',
  });

  const categoryCache = {};
  async function getCategoryTitle(categoryID) {
    if (!categoryID || categoryCache[categoryID]) return categoryCache[categoryID] || '';
    try {
      const snap = await db.collection(VENDOR_CATEGORIES).doc(categoryID).get();
      const title = snap.exists && snap.data() ? (snap.data().title || '') : '';
      categoryCache[categoryID] = title;
      return title;
    } catch (e) {
      return '';
    }
  }

  const snapshot = await db.collection(VENDOR_PRODUCTS).get();
  console.log(`Found ${snapshot.size} products. Generating embeddings...`);
  let done = 0;
  let errCount = 0;

  const batches = [];
  for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
    batches.push(snapshot.docs.slice(i, i + BATCH_SIZE));
  }

  for (const batch of batches) {
    await Promise.all(
      batch.map(async (doc) => {
        try {
          const data = doc.data();
          const categoryID = (data.categoryID || '').toString();
          const categoryTitle = await getCategoryTitle(categoryID);
          const text = buildProductText(data, categoryTitle);
          if (!text) return;
          const embedding = await generateEmbedding(predClient, project, text);
          await fs.collection(VENDOR_PRODUCTS).doc(doc.id).update({
            embedding: FieldValue.vector(embedding),
          });
          done++;
          if (done % 20 === 0) console.log(`  Processed ${done}/${snapshot.size}`);
        } catch (e) {
          errCount++;
          console.error(`  Error for ${doc.id}:`, e.message);
        }
      })
    );
    if (batches.indexOf(batch) < batches.length - 1) {
      await new Promise((r) => setTimeout(r, DELAY_MS));
    }
  }

  console.log(`Done. Success: ${done}, Errors: ${errCount}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
