# Restaurant-to-Rider Delivery Fix Verification and Rollback

## Verification checklist

### 1) Cloud Function payload alignment
- [ ] Send a restaurant quick reply for an assigned order.
- [ ] Confirm `notifyOnOrderMessage` logs in Functions:
  - includes `orderId`, `messageId`
  - payload `data.type` is `order_communication`
  - payload `data.target` is `communicationPanel`
- [ ] Confirm log shows token resolution count > 0 for assigned rider.

### 2) Rider notification behavior by app state
- [ ] Foreground: Rider receives notification and sees local notification.
- [ ] Background: Rider receives notification; tapping opens order communication.
- [ ] Terminated: notification tap opens app and routes to order communication.
- [ ] Confirm both `order_message` and `order_communication` payload types route
      to the same communication screen during transition.

### 3) Message visibility and dual-read
- [ ] Restaurant sends quick reply from order details.
- [ ] Rider communication thread displays message even if only legacy write
      exists (temporary merged stream).
- [ ] No duplicate thread rows for the same message (canonical preferred).

### 4) Read receipt synchronization
- [ ] Rider opens the communication thread.
- [ ] Canonical message `isRead` changes to true.
- [ ] Legacy `order_messages` entry mirrors `isRead=true` and `readAt`.
- [ ] Restaurant unread indicator clears after rider view.

### 5) Duplicate notification prevention
- [ ] Confirm Rider `notifyOnOrderMessageWrite` function logs disabled message
      and exits immediately.
- [ ] Confirm only Admin legacy notification function is actively sending for
      `order_messages` events.
- [ ] Validate no duplicate push notifications per single quick reply.

## Edge case checklist
- [ ] Order without assigned `driverID`: function logs graceful skip.
- [ ] Rider with multiple tokens: notification fanout reaches all devices.
- [ ] Rapid message burst (5+ quick replies): no crash, no duplicate rows.
- [ ] Temporary network disruption during send: retry path logs and recovers.

## Rollback plan

1. Revert Admin payload changes in `notifyOnOrderMessage` if deep-link issues
   appear (keep existing data writes untouched).
2. Temporarily re-enable Rider legacy trigger only if Admin function is down.
3. Keep Restaurant dual-write enabled during rollback to avoid message loss.
4. If merged thread logic causes UI issues, fall back Rider thread rendering to
   canonical stream only while preserving background notifications.
5. Re-deploy last known stable functions and app builds from source control.

## Notes
- Temporary dual-read and canonical-to-legacy read-sync should be removed after
  Phase 2 full cutover to canonical `order_communications`.
