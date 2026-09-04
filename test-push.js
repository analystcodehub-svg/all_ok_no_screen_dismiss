const admin = require("firebase-admin");
const serviceAccount = require("./functions/serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const token = "d0mN6G2ZQsyrnUuBov3z5e:APA91bFRu3R9fG3gQ0V-28T_q4iOqYxV65BqYgD_zZp49H4jP6h1eKx1_uI08Mv_G5_JqO8PjQv8wI_M_qX4H_M8X9-Tq4iOqYxV65BqYgD_zZp49H4jP6h1eKx1_uI08Mv_G5_JqO8PjQv"; // Wait, I don't know the FCM token!
// Let's just fetch the token from Firestore for the male caller (since they are testing)!
const db = admin.firestore();

async function run() {
  // Assuming the user is a male caller, maybe their ID is in users collection
  const users = await db.collection("users").limit(1).get();
  if (users.empty) {
    console.log("No users found");
    return;
  }
  const token = users.docs[0].data().fcmToken;
  if (!token) {
    console.log("No token for user");
    return;
  }

  const message = {
    token: token,
    data: {
      type: "message",
      senderId: "test_expert",
      senderName: "Test Female",
      body: "Hello from background test!",
      senderAvatar: "https://via.placeholder.com/150"
    },
    android: {
      priority: "high"
    }
  };

  try {
    const res = await admin.messaging().send(message);
    console.log("Sent successfully:", res);
  } catch (e) {
    console.error("Error:", e);
  }
}

run();
