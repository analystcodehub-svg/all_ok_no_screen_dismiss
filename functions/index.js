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

admin.initializeApp({
  databaseURL: "https://zegochat-c44b0.asia-southeast1.firebasedatabase.app",
});

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
async function sendFcmMessage(fcmToken, data, notificationPayload = null, isCall = false) {
  const message = {
    token: fcmToken,
    data: data, // All string values
    android: {
      priority: "high", // Required to wake killed app on Android
    },
    apns: {
      headers: {
        "apns-priority": "10",       // High priority on iOS
        "apns-push-type": "voip",    // Required for CallKit on iOS
      },
    },
  };

  // Only expire calls after 30 seconds. Messages should not expire.
  if (isCall) {
    message.android.ttl = 30 * 1000;
  }

  if (notificationPayload) {
    message.notification = notificationPayload;
    if (isCall) {
      // Calls use their specific channel for ringtone/fullscreen
      message.android.notification = {
        channelId: "calls_channel"
      };
    }
    // For messages, no channelId → Android uses the default from AndroidManifest.xml (messages_channel)
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

exports.onCallInitiated = functions.region("asia-south1").database
  .instance('zegochat-c44b0')
  .ref("calls/{callId}")
  .onCreate(async (snap, context) => {
    const callData = snap.val();
    const callId = context.params.callId;

    const receiverId = callData.receiverId; // Expert's nickname (lowercase)
    const callerId   = callData.callerId;   // Caller's nickname (lowercase)

    functions.logger.info(`[onCallInitiated] callId=${callId}, receiver=${receiverId}, caller=${callerId}`);

    if (!receiverId || !callerId) {
      functions.logger.warn("Missing receiverId or callerId — aborting.");
      return null;
    }

    // ── Ultra-Fast Parallel Lookups (< 100ms) ───────────────────────────
    // Run receiver lookups, block check, and RTDB presence concurrently
    const [receiverExpertDoc, receiverUserDoc, blockedDoc, statusSnap] = await Promise.all([
      db.collection("experts").doc(receiverId).get().catch((err) => {
        functions.logger.error("Error fetching expert doc:", err);
        return null;
      }),
      db.collection("users").doc(receiverId).get().catch((err) => {
        functions.logger.error("Error fetching user doc:", err);
        return null;
      }),
      db.collection("blocked_users").doc(receiverId).get().catch((err) => {
        functions.logger.error("Error fetching blocked_users doc:", err);
        return null;
      }),
      admin.database().ref(`status/${receiverId}`).once("value").catch((err) => {
        functions.logger.error("Error fetching RTDB status:", err);
        return null;
      }),
    ]);

    let receiverData = null;
    let isExpert = false;

    if (receiverExpertDoc && receiverExpertDoc.exists) {
      receiverData = receiverExpertDoc.data();
      isExpert = true;
    } else if (receiverUserDoc && receiverUserDoc.exists) {
      receiverData = receiverUserDoc.data();
      isExpert = false;
    } else {
      functions.logger.warn(`Receiver '${receiverId}' not found in experts or users.`);
      return null;
    }

    const gender   = receiverData.gender   || (isExpert ? "female" : "male");
    const isOnline = receiverData.isOnline || false;
    const fcmToken = receiverData.fcmToken || null;

    // ── Check if caller is blocked by receiver ───────────────────────────
    if (blockedDoc && blockedDoc.exists) {
      const blockedUids = blockedDoc.data().blocked_uids || [];
      if (blockedUids.includes(callerId)) {
        functions.logger.info(`Caller '${callerId}' is blocked by Receiver '${receiverId}'. Suppressing call notification.`);
        await snap.ref.update({ status: "rejected_blocked" });
        return null;
      }
    }

    // ── Presence Check: If Female/Expert is offline in RTDB → reject ─────
    const rtdbIsOnline = (statusSnap && statusSnap.exists()) ? (statusSnap.val().isOnline === true) : false;
    if (gender === "female" && !rtdbIsOnline) {
      functions.logger.info(
        `Receiver '${receiverId}' (female) is offline in RTDB. Suppressing call notification.`
      );
      await snap.ref.update({ status: "rejected_offline" });
      return null;
    }

    if (!fcmToken) {
      functions.logger.warn(`Receiver '${receiverId}' has no FCM token.`);
      await snap.ref.update({ status: "rejected_offline" });
      return null;
    }

    // ── Caller Name & Avatar (Fast Path) ─────────────────────────────────
    // If passed directly in callData (from extraRoomData), use immediately!
    let callerName = callData.callerName || "";
    let callerAvatar = callData.callerAvatar || "";

    if (!callerName || callerName === callerId || callerName === "Unknown Caller") {
      try {
        const callerUserDoc = await db.collection("users").doc(callerId).get();
        if (callerUserDoc && callerUserDoc.exists) {
          const d = callerUserDoc.data();
          callerName = d.nickname || callerId;
          callerAvatar = d.avatarPath || "";
        }
      } catch (_) {}
    }
    if (!callerName) {
      callerName = callerId;
    }

    // ── Step 4: Build FCM data payload ─────────────────────────────────────
    // All values MUST be strings for FCM data messages.
    const fcmData = {
      type:        "call",
      callUuid:    callId,           // Used as CallKit UUID
      callRoomId:  callId,           // Firestore document ID of the call
      callerId:    callerId,
      callerName:  callerName,
      callerAvatar: callerAvatar,
      callerAvatarIndex: String(callData.callerAvatarIndex || ""),
      receiverId:  receiverId,
      dbUrl:       "https://zegochat-c44b0.asia-southeast1.firebasedatabase.app",
    };

    try {
      await sendFcmMessage(fcmToken, fcmData, null, true);
      functions.logger.info(
        `[onCallInitiated] High-priority call push sent to '${receiverId}'.`
      );
      await snap.ref.update({
        status: "ringing",
        fcmSentAt: admin.database.ServerValue.TIMESTAMP,
      });
    } catch (fcmErr) {
      functions.logger.error(`[onCallInitiated] Failed to send call FCM to '${receiverId}':`, fcmErr);
      await snap.ref.update({ status: "rejected_offline" });
    }
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

    const gender = receiverData.gender || (isExpert ? "female" : "male");
    const fcmToken = receiverData.fcmToken || null;


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
    
    let rtdbIsOnline = false;
    if (gender === "female") {
      const statusSnap = await admin.database().ref(`status/${receiverId}`).once("value");
      if (statusSnap.exists()) {
        rtdbIsOnline = statusSnap.val().isOnline === true;
      }
    }

    if (gender === "female" && !rtdbIsOnline) {
      functions.logger.info(
        `Receiver '${receiverId}' (female) is offline in RTDB. Suppressing message notification.`
      );
      return null;
    }

    if (!fcmToken) {
      functions.logger.warn(`Receiver '${receiverId}' has no FCM token.`);
      return null;
    }

    // ── Step 3: Fetch Sender Name & Avatar ─────────────────────────────────
    let senderName = senderId;
    let senderAvatar = null;
    
    try {
      const newRtdb = admin.app().database("https://zegochat-c44b0-4cbfb.asia-southeast1.firebasedatabase.app");
      const userSnap = await newRtdb.ref(`users/${senderId}`).once("value");
      if (userSnap.exists()) {
        const d = userSnap.val();
        senderName = d.nickname || senderId;
        senderAvatar = d.avatarUrl || null;
      } else {
        const expertSnap = await newRtdb.ref(`experts/${senderId}`).once("value");
        if (expertSnap.exists()) {
          const d = expertSnap.val();
          senderName = d.nickname || senderId;
          senderAvatar = d.profileImageUrl || d.avatarUrl || null;
        }
      }
    } catch (_) {}

    if (senderName === senderId) {
      let senderDoc = await db.collection("users").doc(senderId).get();
      if (senderDoc.exists) {
        senderName = senderDoc.data().nickname || senderId;
        senderAvatar = senderDoc.data().avatarUrl || null;
      } else {
        senderDoc = await db.collection("experts").doc(senderId).get();
        if (senderDoc.exists) {
          senderName = senderDoc.data().nickname || senderId;
          senderAvatar = senderDoc.data().profileImageUrl || senderDoc.data().avatarUrl || null;
        }
      }
    }

    // ── Step 4: Build FCM data payload ─────────────────────────────────────
    const fcmData = {
      type:       "message",
      roomId:     roomId || "",
      senderId:   senderId,
      senderName: senderName,
      senderAvatar: senderAvatar || "",
      body:       messageText,
      receiverGender: gender,
    };

    // ── Step 5: Send data only ────────────────────────────
    // data block → wakes up background handler which creates a local notification with our custom circular avatar
    await sendFcmMessage(fcmToken, fcmData, null);


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

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD FUNCTION 4: onRtdbPresenceChanged
// Removes an expert from all queues when their RTDB status flips to offline.
// ─────────────────────────────────────────────────────────────────────────────

exports.onRtdbPresenceChanged = functions.region("asia-south1").database
  .instance('zegochat-c44b0')
  .ref("status/{expertId}")
  .onUpdate(async (change, context) => {
    const before = change.before.val();
    const after = change.after.val();
    const expertId = context.params.expertId;

    // Check if the expert went from online to offline
    if (before.isOnline === true && after.isOnline === false) {
      functions.logger.info(`Expert '${expertId}' went offline in RTDB. Removing from all queues.`);
      
      const adminDb = admin.database();
      
      try {
        // Fetch all buckets in 'queues' to find and remove the expert
        const queuesSnap = await adminDb.ref('queues').once('value');
        if (queuesSnap.exists()) {
          const queues = queuesSnap.val();
          
          // Loop through buckets (e.g., female_hindi, male_english, etc.)
          for (const bucketKey of Object.keys(queues)) {
            if (queues[bucketKey] && queues[bucketKey][expertId]) {
              await adminDb.ref(`queues/${bucketKey}/${expertId}`).remove();
              functions.logger.info(`Removed '${expertId}' from queue bucket '${bucketKey}'.`);
            }
          }
        }
        
        // Also ensure active_calls lock is cleared
        await adminDb.ref(`active_calls/${expertId}`).remove();
        
      } catch (error) {
        functions.logger.error(`Error sweeping expert '${expertId}':`, error);
      }
    }
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD FUNCTION 5: onFemaleIntroCallInitiated
// Dedicated trigger for new female-to-male 1-min free intro calls.
// Isolated on database instance: zegochat-c44b0-1e689
// Dispatches high-priority data-only FCM push to wake male users in killed state.
// ─────────────────────────────────────────────────────────────────────────────

exports.onFemaleIntroCallInitiated = functions.region("asia-southeast1").database
  .instance("zegochat-c44b0-1e689")
  .ref("calls/{callId}")
  .onCreate(async (snap, context) => {
    const callData = snap.val();
    const callId = context.params.callId;

    if (!callData) return null;

    const receiverId = callData.receiverId; // Male user UID
    const callerId   = callData.callerId;   // Female expert UID

    functions.logger.info(`[onFemaleIntroCallInitiated] callId=${callId}, caller=${callerId}, receiver=${receiverId}`);

    if (!receiverId || !callerId) {
      functions.logger.warn("Missing receiverId or callerId — aborting intro call.");
      return null;
    }

    const newDb = admin.app().database("https://zegochat-c44b0-1e689.asia-southeast1.firebasedatabase.app");

    // ── Safety Check: Has the male user already used their single 1-min free intro call? ──
    try {
      const recordSnap = await newDb.ref(`free_intro_call_records/${receiverId}`).once("value");
      if (recordSnap.exists() && (recordSnap.val().used === true || recordSnap.val().hasUsed === true)) {
        functions.logger.warn(`Male receiver '${receiverId}' has already consumed their free intro call.`);
        await snap.ref.update({ status: "rejected_already_used" });
        return null;
      }
    } catch (err) {
      functions.logger.error("Error checking free intro call records:", err);
    }

    // ── Check if caller is blocked by receiver ────────────────────────────
    try {
      const blockedDoc = await db.collection("blocked_users").doc(receiverId).get();
      if (blockedDoc.exists) {
        const blockedUids = blockedDoc.data().blocked_uids || [];
        if (blockedUids.includes(callerId)) {
          functions.logger.info(`Caller '${callerId}' is blocked by Receiver '${receiverId}'. Suppressing intro call.`);
          await snap.ref.update({ status: "rejected_blocked" });
          return null;
        }
      }
    } catch (err) {
      functions.logger.error("Error checking blocked status:", err);
    }

    // ── Retrieve Male FCM Token ──────────────────────────────────────────
    let fcmToken = null;

    // 1. Check isolated RTDB male_users first (most up-to-date)
    try {
      const maleSnap = await newDb.ref(`male_users/${receiverId}/fcmToken`).once("value");
      if (maleSnap.exists() && maleSnap.val()) {
        fcmToken = maleSnap.val();
      }
    } catch (err) {
      functions.logger.error("Error querying 1e689 male_users for FCM token:", err);
    }

    // 2. Check callData.receiverFcmToken if not found
    if (!fcmToken && callData.receiverFcmToken) {
      fcmToken = callData.receiverFcmToken;
    }

    // 3. Check new_males_pool
    if (!fcmToken) {
      try {
        const poolSnap = await newDb.ref(`new_males_pool/${receiverId}/fcmToken`).once("value");
        if (poolSnap.exists() && poolSnap.val()) {
          fcmToken = poolSnap.val();
        }
      } catch (err) {
        functions.logger.error("Error querying 1e689 new_males_pool for FCM token:", err);
      }
    }

    // 4. Fallback to Firestore users collection
    if (!fcmToken) {
      try {
        const userDoc = await db.collection("users").doc(receiverId).get();
        if (userDoc.exists && userDoc.data().fcmToken) {
          fcmToken = userDoc.data().fcmToken;
        }
      } catch (err) {
        functions.logger.error("Error querying Firestore users for FCM token:", err);
      }
    }

    // 5. Fallback to 4cbfb user DB
    if (!fcmToken) {
      try {
        const userRtdb = admin.app().database("https://zegochat-c44b0-4cbfb.asia-southeast1.firebasedatabase.app");
        const rtdbSnap = await userRtdb.ref(`users/${receiverId}/fcmToken`).once("value");
        if (rtdbSnap.exists() && rtdbSnap.val()) {
          fcmToken = rtdbSnap.val();
        }
      } catch (err) {
        functions.logger.error("Error querying 4cbfb for FCM token:", err);
      }
    }

    if (!fcmToken) {
      functions.logger.warn(`Male receiver '${receiverId}' has no FCM token — marking call rejected_offline.`);
      await snap.ref.update({
        status: "rejected_offline",
        endReason: "receiver_has_no_fcm_token",
      });
      return null;
    }

    // ── Retrieve Caller (Female) Display Info ─────────────────────────────
    let callerName = callData.callerName || "";
    let callerAvatar = callData.callerAvatar || "";

    if (!callerName || callerName === callerId) {
      try {
        const userRtdb = admin.app().database("https://zegochat-c44b0-4cbfb.asia-southeast1.firebasedatabase.app");
        const expertSnap = await userRtdb.ref(`experts/${callerId}`).once("value");
        if (expertSnap.exists()) {
          const d = expertSnap.val();
          callerName = d.nickname || d.name || callerId;
          callerAvatar = d.profileImageUrl || d.avatarUrl || "";
        }
      } catch (_) {}
    }

    if (!callerName || callerName === callerId) {
      try {
        const expertDoc = await db.collection("experts").doc(callerId).get();
        if (expertDoc.exists) {
          const d = expertDoc.data();
          callerName = d.nickname || d.name || callerId;
          callerAvatar = d.avatarPath || d.avatarUrl || "";
        }
      } catch (_) {}
    }

    // ── Build High-Priority FCM Data Payload (Wakes killed-state CallKit) ───
    const fcmData = {
      type: "call",
      callUuid: callId,
      callRoomId: callId,
      callerId: callerId,
      callerName: callerName || "Female Host",
      callerAvatar: callerAvatar || "",
      receiverId: receiverId,
      callerLanguage: callData.callerLanguage || "",
      receiverLanguage: callData.receiverLanguage || "",
      dbUrl: "https://zegochat-c44b0-1e689.asia-southeast1.firebasedatabase.app",
      isFreeIntroCall: "true",
      maxDurationSeconds: "60",
    };

    // Send data-only message (no notification block) to wake background isolate & CallKit
    try {
      await sendFcmMessage(fcmToken, fcmData, null, true);
      functions.logger.info(
        `[onFemaleIntroCallInitiated] High-priority intro call push sent to male '${receiverId}'.`
      );
      await snap.ref.update({
        status: "ringing",
        fcmSentAt: admin.database.ServerValue.TIMESTAMP,
      });
    } catch (fcmErr) {
      functions.logger.error(`[onFemaleIntroCallInitiated] FCM send failed for male '${receiverId}':`, fcmErr);
      
      const isUnregistered = fcmErr.message === "NotRegistered" ||
          (fcmErr.errorInfo && fcmErr.errorInfo.code === "messaging/registration-token-not-registered") ||
          fcmErr.code === "messaging/registration-token-not-registered";

      if (isUnregistered) {
        // Clean up invalid token from 1e689 so female hosts don't get stuck calling a dead session
        try {
          await newDb.ref(`male_users/${receiverId}/fcmToken`).remove();
          await newDb.ref(`new_males_pool/${receiverId}/fcmToken`).remove();
          const poolSnap = await newDb.ref(`new_males_pool/${receiverId}/languageKey`).get();
          if (poolSnap.exists()) {
            await newDb.ref(`new_males_buckets/${poolSnap.val()}/${receiverId}/fcmToken`).remove();
          }
          await newDb.ref(`new_males_buckets/all/${receiverId}/fcmToken`).remove();
        } catch (_) {}

        // Attempt fallback lookup from Firestore
        let fallbackToken = null;
        try {
          const userDoc = await db.collection("users").doc(receiverId).get();
          if (userDoc.exists && userDoc.data().fcmToken && userDoc.data().fcmToken !== fcmToken) {
            fallbackToken = userDoc.data().fcmToken;
          }
        } catch (_) {}

        if (fallbackToken) {
          try {
            await sendFcmMessage(fallbackToken, fcmData, null, true);
            functions.logger.info(`[onFemaleIntroCallInitiated] Fallback FCM push sent successfully to '${receiverId}'.`);
            await newDb.ref(`male_users/${receiverId}/fcmToken`).set(fallbackToken);
            await snap.ref.update({
              status: "ringing",
              fcmSentAt: admin.database.ServerValue.TIMESTAMP,
            });
            return null;
          } catch (e2) {
            functions.logger.error(`[onFemaleIntroCallInitiated] Fallback FCM push also failed:`, e2);
          }
        }
      }

      // Mark call rejected_offline so female UI transitions cleanly instead of hanging
      await snap.ref.update({
        status: "rejected_offline",
        endReason: "receiver_device_unreachable",
      });
    }
    return null;
  });


// ─────────────────────────────────────────────────────────────────────────────
