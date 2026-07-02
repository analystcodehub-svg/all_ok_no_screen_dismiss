import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("/home/oem/Desktop/check_expert/serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

db = firestore.client()
experts = db.collection('experts').stream()
for exp in experts:
    print(exp.id, exp.to_dict().get('nickname'))
