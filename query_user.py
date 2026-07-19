import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

cred = credentials.Certificate('/home/oem/Desktop/Jaimakali/Icestate_completed/zegochat-c44b0-firebase-adminsdk-h8q7k-45920baeb9.json')
firebase_admin.initialize_app(cred)

db = firestore.client()
users = db.collection('users').stream()
for user in users:
    if user.id.endswith('dhhd'):
        print(f"Found user: {user.id}")
        print(user.to_dict())
