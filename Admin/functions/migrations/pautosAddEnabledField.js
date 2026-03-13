/**
 * One-time migration: Add `enabled` field to settings/PAUTOS_SETTINGS.
 * Defaults to true for backward compatibility.
 *
 * Run: node migrations/pautosAddEnabledField.js
 * (from Admin/functions directory, with GOOGLE_APPLICATION_CREDENTIALS set if needed)
 *
 * Or: firebase use <project> && node migrations/pautosAddEnabledField.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

if (!admin.apps.length) {
  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    (() => {
      try {
        const firebaserc = JSON.parse(
          fs.readFileSync(
            path.join(__dirname, '../../.firebaserc'),
            'utf8',
          ),
        );
        return firebaserc.projects?.default;
      } catch {
        return 'lalago-v2';
      }
    })();
  admin.initializeApp({ projectId });
}

async function addPautosEnabledField() {
  const db = admin.firestore();
  const ref = db.collection('settings').doc('PAUTOS_SETTINGS');

  await ref.set({ enabled: true }, { merge: true });
  console.log('Added enabled: true to settings/PAUTOS_SETTINGS');
}

addPautosEnabledField()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
