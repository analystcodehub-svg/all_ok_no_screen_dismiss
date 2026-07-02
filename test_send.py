import firebase_admin
from firebase_admin import credentials, db
import time

cred = credentials.Certificate("/home/oem/Desktop/check_expert/serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app'
})

ref = db.reference('transit/messages/Priya_Bot/test1234')
ref.set({
    'msgId': 'test1234',
    'roomId': 'dummy_room',
    'senderId': 'test_user',
    'text': 'Hello from test script!',
    'timestamp': int(time.time() * 1000),
    'status': 1
})
print("Message sent to RTDB!")
