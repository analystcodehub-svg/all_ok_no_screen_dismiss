import firebase_admin
from firebase_admin import credentials, db
import json

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

print(json.dumps(db.reference('queues').get(), indent=2))
