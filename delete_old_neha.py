import firebase_admin
from firebase_admin import credentials, firestore, db

cred = credentials.Certificate("/home/oem/Desktop/check_expert/serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

db_fs = firestore.client()
# Delete old Neha_Bot from Firestore
db_fs.collection('experts').document('Neha_Bot').delete()
print("Deleted Neha_Bot from Firestore experts.")

# Delete from RTDB status and queue
db.reference('status/Neha_Bot').delete()
db.reference('experts_queue/Neha_Bot').delete()
print("Deleted Neha_Bot from RTDB.")
