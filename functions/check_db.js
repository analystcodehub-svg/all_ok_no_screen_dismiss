const admin = require("firebase-admin");
admin.initializeApp({ databaseURL: "https://zegochat-c44b0.asia-southeast1.firebasedatabase.app" });
admin.database().ref("status").once("value").then(snap => {
  console.log(snap.val());
  process.exit(0);
});
