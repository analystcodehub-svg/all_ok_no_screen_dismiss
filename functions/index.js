/**
 * Firebase Cloud Functions – SajniRe
 * ─────────────────────────────────────────────────────────────────────────────
 * DEPLOY COMMAND (from /functions directory):
 *   npm install
 *   firebase deploy --only functions
 *
 * SETUP:
 *   firebase init functions  (choose JavaScript / Node 18)
 *   npm install firebase-admin firebase-functions
 * ─────────────────────────────────────────────────────────────────────────────
 */

const admin = require("firebase-admin");
const functions = require("firebase-functions");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Send FCM Data-Only Message (silent push — wakes the background handler)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Sends a high-priority FCM *data* message (no notification block).
 * This silently wakes the app's background isolate so flutter_callkit_incoming
 * can display the native call screen / ringtone even when the app is killed.
 */
async function sendFcmMessage(fcmToken, data, notificationPayload = null) {
  const message = {
    token: fcmToken,
    data: data, // All string values
    android: {
      priority: "high", // Required to wake killed app on Android
      ttl: 30 * 1000,   // Message expires after 30s (call timeout)
    },
    apns: {
      headers: {
        "apns-priority": "10",       // High priority on iOS
        "apns-push-type": "voip",    // Required for CallKit on iOS
      },
    },
  };

  if (notificationPayload) {
    message.notification = notificationPayload;
  }

  try {
    const response = await messaging.send(message);
    functions.logger.info("FCM sent successfully:", response);
    return response;
  } catch (error) {
    functions.logger.error("FCM send error:", error);
    throw error;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD FUNCTION 1: onCallInitiated
// Triggered when a new document is created in the `calls` collection.
// ─────────────────────────────────────────────────────────────────────────────

exports.onCallInitiated = functions.region("asia-south1").firestore
  .document("calls/{callId}")
  .onCreate(async (snap, context) => {
    const callData = snap.data();
    const callId = context.params.callId;

    const receiverId = callData.receiverId; // Expert's nickname (lowercase)
    const callerId   = callData.callerId;   // Caller's nickname (lowercase)

    functions.logger.info(`[onCallInitiated] callId=${callId}, receiver=${receiverId}, caller=${callerId}`);

    if (!receiverId || !callerId) {
      functions.logger.warn("Missing receiverId or callerId — aborting.");
      return null;
    }

    // ── Step 1: Determine receiver's collection and fetch their doc ────────
    let receiverDoc = await db.collection("experts").doc(receiverId).get();
    let receiverData;
    let isExpert = false;

    if (receiverDoc.exists) {
      receiverData = receiverDoc.data();
      isExpert = true;
    } else {
      receiverDoc = await db.collection("users").doc(receiverId).get();
      if (!receiverDoc.exists) {
        functions.logger.warn(`Receiver '${receiverId}' not found in experts or users.`);
        return null;
      }
      receiverData = receiverDoc.data();
    }

    const gender   = receiverData.gender   || (isExpert ? "female" : "male");
    const isOnline = receiverData.isOnline || false;
    const fcmToken = receiverData.fcmToken || null;

    // ── Step 1.5: Check if caller is blocked by receiver ───────────────────
    const blockedDoc = await db.collection("blocked_users").doc(receiverId).get();
    if (blockedDoc.exists) {
      const blockedUids = blockedDoc.data().blocked_uids || [];
      if (blockedUids.includes(callerId)) {
        functions.logger.info(`Caller '${callerId}' is blocked by Receiver '${receiverId}'. Suppressing call notification.`);
        // Also update call status to 'rejected_blocked' so the caller gets feedback
        await snap.ref.update({ status: "rejected_blocked" });
        return null;
      }
    }

    // ── Step 2: Business Logic Gate ────────────────────────────────────────
    //
    // CONDITION 1 (Female/Expert): If isOnline == false → DO NOT send notification.
    // CONDITION 2 (Male/User):     Always send.
    //
    if (gender === "female" && isOnline === false) {
      functions.logger.info(
        `Receiver '${receiverId}' (female) is offline. Suppressing call notification.`
      );
      // Also update call status to 'rejected' so the caller gets feedback
      await snap.ref.update({ status: "rejected_offline" });
      return null;
    }

    if (!fcmToken) {
      functions.logger.warn(`Receiver '${receiverId}' has no FCM token.`);
      return null;
    }

    // ── Step 3: Fetch caller's display name ────────────────────────────────
    let callerName = callerId;
    let callerAvatar = "";

    // Try 'users' collection first (male callers), then 'experts'
    const callerUserDoc = await db.collection("users").doc(callerId).get();
    if (callerUserDoc.exists) {
      const d = callerUserDoc.data();
      callerName   = d.nickname   || callerId;
      callerAvatar = d.avatarPath || "";
    } else {
      const callerExpertDoc = await db.collection("experts").doc(callerId).get();
      if (callerExpertDoc.exists) {
        const d = callerExpertDoc.data();
        callerName   = d.nickname   || callerId;
        callerAvatar = d.avatarPath || "";
      }
    }

    // ── Step 4: Build FCM data payload ─────────────────────────────────────
    // All values MUST be strings for FCM data messages.
    const fcmData = {
      type:        "call",
      callUuid:    callId,           // Used as CallKit UUID
      callRoomId:  callId,           // Firestore document ID of the call
      callerName:  callerName,
      callerAvatar: callerAvatar,
      receiverId:  receiverId,
    };

    // ── Step 5: Send the FCM data message ──────────────────────────────────
    // Note: No notification block because CallKit handles the ringing UI directly.
    await sendFcmMessage(fcmToken, fcmData);

    functions.logger.info(
      `[onCallInitiated] Notification sent to expert '${receiverId}'.`
    );
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD FUNCTION 2: onMessageSent
// Triggered when a new message is written to `transit/messages/{receiverId}/{msgId}` in RTDB.
// ─────────────────────────────────────────────────────────────────────────────

exports.onMessageSent = functions.region("asia-south1").database
  .instance('zegochat-c44b0')
  .ref("transit/messages/{receiverId}/{msgId}")
  .onCreate(async (snap, context) => {
    const msgData = snap.val();
    const receiverId = context.params.receiverId;
    const msgId = context.params.msgId;

    const senderId = msgData.senderId;
    const messageText = msgData.text || "New message";
    const roomId = msgData.roomId;

    functions.logger.info(`[onMessageSent] msgId=${msgId}, roomId=${roomId}, from=${senderId}, to=${receiverId}`);

    if (!receiverId || !senderId) {
      functions.logger.warn("Missing senderId or receiverId — aborting.");
      return null;
    }

    // ── Step 1: Determine receiver's collection and fetch their doc ────────
    let receiverDoc = await db.collection("experts").doc(receiverId).get();
    let receiverData;
    let isExpert = false;

    if (receiverDoc.exists) {
      receiverData = receiverDoc.data();
      isExpert = true;
    } else {
      receiverDoc = await db.collection("users").doc(receiverId).get();
      if (!receiverDoc.exists) {
        functions.logger.warn(`Receiver '${receiverId}' not found.`);
        return null;
      }
      receiverData = receiverDoc.data();
    }

    const fcmToken = receiverData.fcmToken || null;
    const isOnline = receiverData.isOnline || false;
    const gender   = receiverData.gender   || (isExpert ? "female" : "male");

    // ── Step 1.5: Check if sender is blocked by receiver ───────────────────
    const blockedDoc = await db.collection("blocked_users").doc(receiverId).get();
    if (blockedDoc.exists) {
      const blockedUids = blockedDoc.data().blocked_uids || [];
      if (blockedUids.includes(senderId)) {
        functions.logger.info(`Sender '${senderId}' is blocked by Receiver '${receiverId}'. Suppressing message notification.`);
        return null;
      }
    }

    // ── Step 2: Business Logic Gate ────────────────────────────────────────
    // Female/Expert: do NOT notify if offline
    if (gender === "female" && isOnline === false) {
      functions.logger.info(
        `Expert '${receiverId}' is offline. Suppressing message notification.`
      );
      return null;
    }

    if (!fcmToken) {
      functions.logger.warn(`Receiver '${receiverId}' has no FCM token.`);
      return null;
    }

    // ── Step 3: Fetch Sender Name ──────────────────────────────────────────
    let senderName = senderId;
    let senderDoc = await db.collection("users").doc(senderId).get();
    if (senderDoc.exists) {
      senderName = senderDoc.data().nickname || senderId;
    } else {
      senderDoc = await db.collection("experts").doc(senderId).get();
      if (senderDoc.exists) {
        senderName = senderDoc.data().nickname || senderId;
      }
    }

    // ── Step 4: Build FCM data payload ─────────────────────────────────────
    const fcmData = {
      type:       "message",
      roomId:     roomId || "",
      senderId:   senderId,
      senderName: senderName,
      body:       messageText,
    };

    // ── Step 5: Send notification ───────────────────────────────────────────
    const notificationPayload = {
      title: senderName,
      body: messageText,
    };
    await sendFcmMessage(fcmToken, fcmData, notificationPayload);

    functions.logger.info(
      `[onMessageSent] Message notification sent to '${receiverId}'.`
    );
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD FUNCTION 3: onExpertOffline (optional helper)
// When an expert goes offline, cancel any pending call documents targeting them.
// ─────────────────────────────────────────────────────────────────────────────

exports.onExpertStatusChanged = functions.region("asia-south1").firestore
  .document("experts/{expertId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after  = change.after.data();
    const expertId = context.params.expertId;

    // Only act when isOnline flips from true → false
    if (before.isOnline === true && after.isOnline === false) {
      functions.logger.info(`Expert '${expertId}' went offline — rejecting pending calls.`);

      // Find any active calls targeting this expert
      const pendingCalls = await db.collection("calls")
        .where("receiverId", "==", expertId)
        .where("status", "==", "calling")
        .get();

      const batch = db.batch();
      pendingCalls.docs.forEach((doc) => {
        batch.update(doc.ref, { status: "rejected_offline" });
      });
      await batch.commit();

      functions.logger.info(
        `Rejected ${pendingCalls.size} pending call(s) for offline expert '${expertId}'.`
      );
    }
    return null;
  });
