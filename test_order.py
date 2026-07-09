import firebase_admin
from firebase_admin import credentials, db

cred = credentials.Certificate("/home/oem/Desktop/check_expert/serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

ref = db.reference('queues/female_hindi')
print(ref.order_by_child('totalTalkSeconds').limit_to_last(150).get())
