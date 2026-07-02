import firebase_admin
from firebase_admin import credentials, firestore, db

cred = credentials.Certificate("/home/oem/Desktop/check_expert/serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

db_fs = firestore.client()
experts = db_fs.collection('experts').stream()
for exp in experts:
    data = exp.to_dict()
    print(f"Firestore ID: {exp.id}, Name: {data.get('nickname')}")
    
status = db.reference('status').get()
if status:
    print("\nRTDB Statuses:")
    for uid, s in status.items():
        print(f"RTDB ID: {uid}, isOnline: {s.get('isOnline')}")
