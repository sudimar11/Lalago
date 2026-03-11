# Communication Rollout Test Matrix

## Scope
- Rider app, Restaurant app, Cloud Functions notification routing,
  canonical `order_communications`, legacy bridge `order_messages`.

## Dual Write and Migration
- [ ] Rider quick actions write to both `order_messages` and
  `order_communications/{orderId}/messages`.
- [ ] Restaurant quick actions write to both legacy and canonical paths.
- [ ] `migrateMessageReadField.js` sets `isRead` for old `isread` docs.
- [ ] `backfillOrderCommunications.js` mirrors historical `order_messages`.

## Notification Reliability
- [ ] New legacy message triggers push via
  `notifyOnOrderMessageWrite`.
- [ ] New canonical message triggers push via
  `notifyOnOrderCommunicationMessage`.
- [ ] Foreground tap opens communication panel/thread.
- [ ] Background tap opens communication panel/thread.
- [ ] Terminated-app tap opens communication panel/thread.

## Real-time Sync
- [ ] Message appears on other device without manual refresh.
- [ ] Read state updates from unread to read after opening thread.
- [ ] Typing indicator appears/disappears correctly.

## Issue Lifecycle
- [ ] Rider creates issue with category + note + optional photo.
- [ ] Restaurant can acknowledge, resolve, and escalate issue.
- [ ] Invalid transition is rejected by `validateIssueStateTransition`.
- [ ] Closed issue triggers satisfaction prompt on both sides.

## Analytics and Alerting
- [ ] `aggregateCommunicationMetrics` writes metrics every 15 minutes.
- [ ] Threshold breach writes `communication_alerts` doc.
- [ ] Webhook alert sends when configured.
- [ ] Admin communication analytics page renders latest metrics.

## Cost and Integrity Checks
- [ ] Verify Firestore indexes for `isRead`, `state`, and `createdAt`.
- [ ] Verify no duplicate notification loops.
- [ ] Verify unread counts are stable after app restart.

