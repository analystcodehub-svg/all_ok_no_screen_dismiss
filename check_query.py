import firebase_admin
from firebase_admin import credentials, db
import json

cred = credentials.Certificate('/home/oem/Desktop/check_expert/serviceAccountKey.json')
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

ref = db.reference('queues/female_hindi')
results = ref.order_by_child('totalTalkSeconds').limit_to_last(150).get()
print(json.dumps(results, indent=2))
