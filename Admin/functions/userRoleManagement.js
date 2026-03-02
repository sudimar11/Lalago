const functions = require('firebase-functions');

const AUDIT_LOGS = 'audit_logs';
const USERS = 'users';

/**
 * Returns true if the caller is a super admin (can edit roles).
 * Accepts role/userLevel === 'admin' for backward compatibility; rejects limited.
 */
function isSuperAdmin(callerData) {
  if (!callerData) return false;
  const role = callerData.role || callerData.userRole || callerData.userLevel || '';
  const adminLevel = callerData.adminLevel || '';
  if (adminLevel === 'limited') return false;
  return role === 'admin' || role === 'Admin' || adminLevel === 'super';
}

/**
 * updateUserRole - Single user role change with audit logging.
 * Params: { targetUserId: string, newRole: string }
 * Requires: caller adminLevel === 'super' (or legacy role === 'admin')
 */
async function updateUserRole(data, context, getDb) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const db = getDb();
  const callerId = context.auth.uid;
  const callerDoc = await db.collection(USERS).doc(callerId).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};

  if (!isSuperAdmin(callerData)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Super admin only',
    );
  }

  const targetUserId = data?.targetUserId;
  const newRole = data?.newRole;

  if (!targetUserId || typeof targetUserId !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'targetUserId is required',
    );
  }
  if (!newRole || typeof newRole !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'newRole is required',
    );
  }

  const allowedRoles = ['customer', 'driver', 'vendor', 'admin', 'teacher'];
  if (!allowedRoles.includes(newRole)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `newRole must be one of: ${allowedRoles.join(', ')}`,
    );
  }

  const targetRef = db.collection(USERS).doc(targetUserId);
  const targetDoc = await targetRef.get();
  if (!targetDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'User not found');
  }

  const targetData = targetDoc.data() || {};
  const oldRole = targetData.role || targetData.userLevel || '';

  await db.runTransaction(async (tx) => {
    tx.update(targetRef, {
      role: newRole,
      userLevel: newRole,
    });

    tx.set(db.collection(AUDIT_LOGS).doc(), {
      action: 'role_change',
      adminId: callerId,
      targetUserId,
      oldRole,
      newRole,
      timestamp: new Date(),
    });
  });

  return { success: true };
}

/**
 * batchUpdateUserRoles - Bulk role change with audit logging per user.
 * Params: { targetUserIds: string[], newRole: string }
 */
async function batchUpdateUserRoles(data, context, getDb) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const db = getDb();
  const callerId = context.auth.uid;
  const callerDoc = await db.collection(USERS).doc(callerId).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};

  if (!isSuperAdmin(callerData)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Super admin only',
    );
  }

  const targetUserIds = data?.targetUserIds;
  const newRole = data?.newRole;

  if (!Array.isArray(targetUserIds) || targetUserIds.length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'targetUserIds must be a non-empty array',
    );
  }
  if (!newRole || typeof newRole !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'newRole is required',
    );
  }

  const allowedRoles = ['customer', 'driver', 'vendor', 'admin', 'teacher'];
  if (!allowedRoles.includes(newRole)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `newRole must be one of: ${allowedRoles.join(', ')}`,
    );
  }

  let successCount = 0;
  let failureCount = 0;

  for (const targetUserId of targetUserIds) {
    if (!targetUserId || typeof targetUserId !== 'string') {
      failureCount++;
      continue;
    }
    try {
      const targetRef = db.collection(USERS).doc(targetUserId);
      const targetDoc = await targetRef.get();
      if (!targetDoc.exists) {
        failureCount++;
        continue;
      }
      const targetData = targetDoc.data() || {};
      const oldRole = targetData.role || targetData.userLevel || '';

      await db.runTransaction(async (tx) => {
        tx.update(targetRef, {
          role: newRole,
          userLevel: newRole,
        });
        tx.set(db.collection(AUDIT_LOGS).doc(), {
          action: 'role_change',
          adminId: callerId,
          targetUserId,
          oldRole,
          newRole,
          timestamp: new Date(),
        });
      });
      successCount++;
    } catch (e) {
      failureCount++;
    }
  }

  return { success: true, successCount, failureCount };
}

module.exports = {
  updateUserRole,
  batchUpdateUserRoles,
};
