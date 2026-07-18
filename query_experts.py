import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('../check_expert/serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()
docs = db.collection('experts').limit(5).stream()
for doc in docs:
    print(doc.to_dict())
