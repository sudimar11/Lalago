# Backend FCM Setup for Chat Notifications

## Overview

This document describes the backend Cloud Function requirements for sending FCM push notifications when drivers send messages to customers.

## Firebase Cloud Function Setup

### Prerequisites

- Firebase project: `lalago-v2`
- Service account credentials (provided)
- Firebase Admin SDK initialized

### Cloud Function Implementation

Create a Cloud Function that triggers on writes to the `chat_driver/{orderId}/thread` collection:

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin with service account
admin.initializeApp({
  credential: admin.credential.cert({
    projectId: "lalago-v2",
    privateKeyId: "b98c6f62158a725864dab59b77fff82b900b5d3b",
    privateKey: "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
    clientEmail: "firebase-adminsdk-fbsvc@lalago-v2.iam.gserviceaccount.com",
    clientId: "101067610325350325339",
    authUri: "https://accounts.google.com/o/oauth2/auth",
    tokenUri: "https://oauth2.googleapis.com/token",
    authProviderX509CertUrl: "https://www.googleapis.com/oauth2/v1/certs",
    clientX509CertUrl:
      "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40lalago-v2.iam.gserviceaccount.com",
    universeDomain: "googleapis.com",
  }),
});

exports.onDriverMessage = functions.firestore
  .document("chat_driver/{orderId}/thread/{messageId}")
  .onCreate(async (snap, context) => {
    const messageData = snap.data();
    const orderId = context.params.orderId;

    try {
      // Get the inbox document
      const inboxDoc = await admin
        .firestore()
        .collection("chat_driver")
        .doc(orderId)
        .get();

      if (!inboxDoc.exists) {
        console.log("Inbox document not found");
        return null;
      }

      const inboxData = inboxDoc.data();
      const customerId = inboxData.customerId;

      // Only send notification if message is from driver (not customer)
      if (messageData.senderId === customerId) {
        return null; // Customer sent the message, no notification needed
      }

      // Get customer's FCM token
      const customerDoc = await admin
        .firestore()
        .collection("users")
        .doc(customerId)
        .get();

      if (!customerDoc.exists) {
        console.log("Customer document not found");
        return null;
      }

      const customerData = customerDoc.data();
      const fcmToken = customerData.fcmToken;

      if (!fcmToken) {
        console.log("Customer FCM token not found");
        return null;
      }

      // Get driver/restaurant user info for notification title
      const driverDoc = await admin
        .firestore()
        .collection("users")
        .doc(messageData.senderId)
        .get();

      const driverName = driverDoc.exists
        ? `${driverDoc.data().firstName} ${driverDoc.data().lastName}`
        : "Driver";

      // Prepare message preview
      let messageBody = "";
      if (messageData.messageType === "text") {
        messageBody = messageData.message || "New message";
      } else if (messageData.messageType === "image") {
        messageBody = "📷 Sent an image";
      } else if (messageData.messageType === "video") {
        messageBody = "🎥 Sent a video";
      } else {
        messageBody = "New message";
      }

      // Increment unread count in inbox document
      const currentUnread = inboxData.unreadCount || 0;
      await admin
        .firestore()
        .collection("chat_driver")
        .doc(orderId)
        .update({
          unreadCount: currentUnread + 1,
          lastMessage: messageBody,
          lastSenderId: messageData.senderId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      // Prepare notification payload
      const notification = {
        notification: {
          title: `New message from ${driverName}`,
          body: messageBody,
          sound: "default",
        },
        data: {
          type: "chat",
          orderId: orderId,
          customerId: customerId,
          restaurantId: messageData.receiverId,
          chatType: "Driver",
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "chat_messages",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: currentUnread + 1,
            },
          },
        },
      };

      // Send notification
      const response = await admin.messaging().send(notification);
      console.log("Successfully sent message:", response);

      return null;
    } catch (error) {
      console.error("Error sending notification:", error);
      return null;
    }
  });
```

## Notification Payload Structure

### Required Data Fields

- `type`: Must be `"chat"` for chat notifications
- `orderId`: The order ID associated with the chat
- `customerId`: The customer's user ID
- `restaurantId`: The driver/restaurant user ID
- `chatType`: Should be `"Driver"` for driver chats

### Notification Content

- **Title**: "New message from {driverName}"
- **Body**: Message preview (text, image indicator, or video indicator)
- **Sound**: Default notification sound
- **Badge**: Incremented unread count (iOS)

## Firestore Document Updates

The Cloud Function should update the inbox document (`chat_driver/{orderId}`) with:

- `unreadCount`: Incremented by 1
- `lastMessage`: Preview of the latest message
- `lastSenderId`: ID of the message sender
- `createdAt`: Server timestamp

## Testing

1. Send a message from the driver app
2. Verify the notification is received on the customer app
3. Check that `unreadCount` is incremented in Firestore
4. Verify badge count updates in the customer app
5. Test notification tap navigation to chat screen

## Security Considerations

- Store service account credentials securely (use environment variables or Firebase Functions config)
- Validate message data before processing
- Handle errors gracefully
- Rate limit notifications if needed
